"""Base W06: espelho por dia civil, alocação histórica e abonos por escopo.

Não altera marcações. Intervalos previstos sem horário de pausa são
distribuídos proporcionalmente; apuração definitiva/folha pertence ao W10+.
"""

from collections import defaultdict
from datetime import date, datetime, time, timedelta, timezone
from fractions import Fraction
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import or_, select

from app.models import (
    Afastamentos, Alocacoes, Empresas, Escalas, Feriados, JustificativasAjustes,
    PoliticaLocalizacao, RegistrosPonto, SelfiesPonto, Setores, SituacaoPonto, StatusAjuste, TipoAfastamento, TipoPonto,
)
from .check_schedule_conflict_service import CheckScheduleConflictService, ScheduleValidationError
from .rh_access import GestaoError, executar_empresa
from .espelho_ajustes import auditoria, projetar_decisoes
from .w06_validation import funcionario


def _agora_utc():
    return datetime.now(timezone.utc)


def _segundos(inicio, fim):
    delta = fim - inicio
    return Fraction(delta.days * 86400 + delta.seconds) + Fraction(delta.microseconds, 1000000)


def _unir(intervalos):
    result = []
    for inicio, fim in sorted(intervalos):
        if inicio >= fim:
            continue
        if result and inicio <= result[-1][1]:
            result[-1] = (result[-1][0], max(fim, result[-1][1]))
        else:
            result.append((inicio, fim))
    return result


def _cobertura(intervalos, inicio, fim):
    return sum((_segundos(max(a, inicio), min(b, fim)) for a, b in intervalos
        if a < fim and b > inicio), Fraction())


def _segmentar(inicio, fim, zona):
    atual = inicio.astimezone(timezone.utc)
    limite = fim.astimezone(timezone.utc)
    while atual < limite:
        dia = atual.astimezone(zona).date()
        proximo = datetime.combine(dia + timedelta(days=1), time.min, zona).astimezone(timezone.utc)
        final = min(limite, proximo)
        yield dia, atual, final
        atual = final


def _minutos(segundos):
    return round(float(segundos / 60), 2)


class EspelhoService:
    @staticmethod
    def consultar(usuario_id, empresa_id, filtros, session=None):
        def operacao(session, empresa):
            if not isinstance(filtros, dict) or filtros.keys() - {"funcionario_id", "ano", "mes"}:
                raise GestaoError("Informe funcionário, ano e mês.")
            try:
                ano, mes = (int(filtros[k]) for k in ("ano", "mes"))
            except (KeyError, ValueError, TypeError):
                raise GestaoError("Informe ano e mês válidos.") from None
            return EspelhoService.gerar_mensal(usuario_id, empresa, None, ano, mes,
                funcionario_id=filtros.get("funcionario_id"), session=session)
        return executar_empresa(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def _periodo(ano, mes):
        if type(ano) is not int or type(mes) is not int or not 2 <= ano <= 9998 or not 1 <= mes <= 12:
            raise GestaoError("Informe ano entre 2 e 9998 e mês entre 1 e 12.")
        inicio = date(ano, mes, 1)
        proximo = date(ano + int(mes == 12), 1 if mes == 12 else mes + 1, 1)
        return inicio, proximo - timedelta(days=1), proximo

    @staticmethod
    def _pares(marcacoes, zona, avisos):
        """Trabalho exclui pausa; presença inclui a pausa entre entrada/saída."""
        trabalho, presenca = defaultdict(list), defaultdict(list)
        grupos = defaultdict(list)
        for ponto in marcacoes:
            if ponto.situacao != SituacaoPonto.ACEITA:
                avisos[ponto.ocorrido_em.astimezone(zona).date()].add("MARCACAO_NAO_ACEITA")
            else:
                grupos[ponto.alocacao_id].append(ponto)
        for aid, grupo in grupos.items():
            entrada = inicio_trabalho = None
            em_intervalo = False
            for ponto in grupo:
                instante = ponto.ocorrido_em.astimezone(timezone.utc)
                dia = instante.astimezone(zona).date()
                if ponto.tipo == TipoPonto.ENTRADA and entrada is None:
                    entrada = inicio_trabalho = instante
                elif ponto.tipo == TipoPonto.INICIO_INTERVALO and inicio_trabalho is not None:
                    trabalho[aid].append((inicio_trabalho, instante))
                    inicio_trabalho, em_intervalo = None, True
                elif ponto.tipo == TipoPonto.FIM_INTERVALO and em_intervalo:
                    inicio_trabalho, em_intervalo = instante, False
                elif ponto.tipo == TipoPonto.SAIDA and inicio_trabalho is not None:
                    trabalho[aid].append((inicio_trabalho, instante))
                    presenca[aid].append((entrada, instante))
                    entrada = inicio_trabalho = None
                else:
                    avisos[dia].add("SEQUENCIA_INCOMPLETA_OU_INVALIDA")
                    if entrada is not None:
                        for dia_, _, _ in _segmentar(entrada, instante + timedelta(microseconds=1), zona):
                            avisos[dia_].add("SEQUENCIA_INCOMPLETA_OU_INVALIDA")
                    # Não inventa pares quando houver entradas duplicadas ou saída sem entrada.
                    entrada = inicio_trabalho = None
                    em_intervalo = False
            if entrada is not None:
                # Até 25 horas reais cobre inclusive a virada de DST de um turno de 24h.
                for dia_, _, _ in _segmentar(entrada, entrada + timedelta(hours=25), zona):
                    avisos[dia_].add("SEQUENCIA_INCOMPLETA_OU_INVALIDA")
        return ({aid: _unir(v) for aid, v in trabalho.items()},
            {aid: _unir(v) for aid, v in presenca.items()})

    @staticmethod
    def gerar_mensal(usuario_id, empresa_id, usuario_alvo_id, ano, mes, *, funcionario_id=None, session=None):
        """Retorna (DTO, status HTTP). Não depende do status ativo dos vínculos antigos.

        usuario_id é o RH solicitante; usuario_alvo_id identifica o funcionário.
        Para funcionário sem login, informe usuario_alvo_id=None e funcionario_id.
        Horas não aceitas, pares incompletos, W10 pendente e escalas sem turnos
        geram pendência de apuração, em vez de criar faltas automaticamente.
        """
        def operacao(session, empresa):
            inicio, fim, proximo = EspelhoService._periodo(ano, mes)
            alvo = funcionario(session, empresa, funcionario_id=funcionario_id, usuario_id=usuario_alvo_id)
            companhia = session.scalar(select(Empresas).where(Empresas.id == empresa))
            try:
                zona = ZoneInfo(companhia.fuso_horario)
            except (ZoneInfoNotFoundError, ValueError):
                raise GestaoError("Fuso da empresa indisponível.", 503, "FUSO_INVALIDO") from None
            agora = _agora_utc()
            # Busca a véspera: um plantão do mês anterior pode ocupar o primeiro dia.
            margem_inicio = inicio - timedelta(days=1)
            janela_inicio = datetime.combine(margem_inicio, time.min, zona).astimezone(timezone.utc)
            janela_fim = datetime.combine(proximo + timedelta(days=1), time.min, zona).astimezone(timezone.utc)
            linhas = session.execute(select(Alocacoes, Setores, Escalas).join(Setores,
                (Setores.id == Alocacoes.setor_id) & (Setores.empresa_id == Alocacoes.empresa_id)
            ).outerjoin(Escalas,
                (Escalas.id == Alocacoes.escala_id) & (Escalas.empresa_id == Alocacoes.empresa_id)
            ).where(Alocacoes.empresa_id == empresa, Alocacoes.funcionario_id == alvo.id,
                Setores.empresa_id == empresa, or_(Escalas.id.is_(None), Escalas.empresa_id == empresa),
                Alocacoes.data_inicio <= fim,
                or_(Alocacoes.data_fim.is_(None), Alocacoes.data_fim >= margem_inicio)
            ).order_by(Alocacoes.data_inicio, Alocacoes.id)).all()
            feriados = session.scalars(select(Feriados).where(Feriados.empresa_id == empresa,
                Feriados.data.between(inicio, fim)).order_by(Feriados.data, Feriados.id)).all()
            afastamentos = session.scalars(select(Afastamentos).where(Afastamentos.empresa_id == empresa,
                Afastamentos.funcionario_id == alvo.id, Afastamentos.data_inicio <= fim,
                Afastamentos.data_fim >= inicio).order_by(Afastamentos.data_inicio, Afastamentos.id)).all()
            pontos = []
            fotos = {}
            invalidacoes = {}
            aprovacoes, correcoes, manuais, ajustes = {}, {}, [], []
            avisos = defaultdict(set)
            if alvo.usuario_id is not None:
                pontos = session.scalars(select(RegistrosPonto).where(RegistrosPonto.empresa_id == empresa,
                    RegistrosPonto.usuario_id == alvo.usuario_id,
                    RegistrosPonto.ocorrido_em >= janela_inicio,
                    RegistrosPonto.ocorrido_em < janela_fim
                ).order_by(RegistrosPonto.ocorrido_em, RegistrosPonto.recebido_em, RegistrosPonto.id)).all()
                ajustes = session.scalars(select(JustificativasAjustes).where(
                    JustificativasAjustes.empresa_id == empresa, JustificativasAjustes.usuario_id == alvo.usuario_id,
                    JustificativasAjustes.status != StatusAjuste.REJEITADO,
                    or_((JustificativasAjustes.ocorrido_em_proposto >= janela_inicio)
                        & (JustificativasAjustes.ocorrido_em_proposto < janela_fim),
                        JustificativasAjustes.registro_ponto_id.in_([p.id for p in pontos])))).all()
                # Uma correção pode trazer ao mês uma marcação de outro período.
                referencias = {a.registro_ponto_id for a in ajustes if a.registro_ponto_id is not None}
                if referencias:
                    complementares = session.scalars(select(JustificativasAjustes).where(
                        JustificativasAjustes.empresa_id == empresa, JustificativasAjustes.usuario_id == alvo.usuario_id,
                        JustificativasAjustes.registro_ponto_id.in_(referencias),
                        JustificativasAjustes.status != StatusAjuste.REJEITADO)).all()
                    ajustes = list({a.id: a for a in [*ajustes, *complementares]}.values())
                    faltantes = referencias - {p.id for p in pontos}
                    if faltantes:
                        pontos.extend(session.scalars(select(RegistrosPonto).where(
                            RegistrosPonto.empresa_id == empresa, RegistrosPonto.usuario_id == alvo.usuario_id,
                            RegistrosPonto.id.in_(faltantes))).all())
                # Apenas metadados, incluindo originais corrigidos de outro mês.
                if pontos:
                    fotos = {foto.evento_cliente_id: foto.criado_em for foto in session.execute(
                        select(SelfiesPonto.evento_cliente_id, SelfiesPonto.criado_em).where(
                            SelfiesPonto.empresa_id == empresa,
                            SelfiesPonto.usuario_id == alvo.usuario_id,
                            SelfiesPonto.evento_cliente_id.in_([p.evento_cliente_id for p in pontos]),
                        )).all()}
            efetivos, invalidacoes, aprovacoes, correcoes, manuais, decisoes = projetar_decisoes(pontos, ajustes, linhas, zona, avisos)
            for ponto in efetivos:
                if ponto.ocorrido_em > agora:
                    avisos[ponto.ocorrido_em.astimezone(zona).date()].add("MARCACAO_FUTURA")
            trabalho, presenca = EspelhoService._pares(efetivos, zona, avisos)
            ocupados = sorted(i for v in trabalho.values() for i in v)
            limite_anterior = None
            for a, b in ocupados:
                if limite_anterior is not None and a < limite_anterior:
                    for dia_, _, _ in _segmentar(a, min(b, limite_anterior), zona):
                        avisos[dia_].add("MARCACOES_CONFLITANTES")
                limite_anterior = max(b, limite_anterior) if limite_anterior is not None else b
            jornadas = defaultdict(list)
            historico = []
            for alocacao, setor, escala in linhas:
                historico.append({"id": str(alocacao.id), "data_inicio": alocacao.data_inicio.isoformat(),
                    "data_fim": alocacao.data_fim.isoformat() if alocacao.data_fim else None,
                    "setor": {"id": str(setor.id), "nome": setor.nome},
                    "escala": {"id": str(escala.id), "nome": escala.nome} if escala else None})
                primeiro = max(margem_inicio, alocacao.data_inicio)
                ultimo = min(fim, alocacao.data_fim or fim)
                try:
                    if escala is None:
                        raise ValueError("Alocação sem escala.")
                    turnos = CheckScheduleConflictService._projetar(session, empresa, escala,
                        primeiro, ultimo, zona, detalhar=True)
                except (ValueError, ScheduleValidationError):
                    for n in range(max(0, (ultimo - max(inicio, primeiro)).days + 1)):
                        avisos[max(inicio, primeiro) + timedelta(days=n)].add("ESCALA_SEM_PROJECAO")
                    continue
                for turno in turnos:
                    a, b = turno["inicio"], turno["fim"]
                    bruto = _segundos(a, b)
                    liquido = bruto - turno["tempo_intervalo"] * 60
                    for dia, start, end in _segmentar(a, b, zona):
                        if inicio <= dia <= fim:
                            jornadas[dia].append({"alocacao_id": alocacao.id, "setor_id": setor.id,
                                "escala_id": escala.id, "setor_nome": setor.nome, "escala_nome": escala.nome,
                                "inicio": start, "fim": end, "inicio_turno": a, "fim_turno": b,
                                "liquido": liquido * _segundos(start, end) / bruto,
                                "tolerancia": escala.tolerancia_minutos * 60})
            trabalho_total = _unir([i for pares in trabalho.values() for i in pares])
            dias = []
            totais = defaultdict(Fraction)
            for numero in range((fim - inicio).days + 1):
                dia = inicio + timedelta(days=numero)
                a = datetime.combine(dia, time.min, zona).astimezone(timezone.utc)
                b = datetime.combine(dia + timedelta(days=1), time.min, zona).astimezone(timezone.utc)
                folgas = [r for r in afastamentos if r.data_inicio <= dia <= r.data_fim]
                feriados_dia = [r for r in feriados if r.data == dia]
                agenda = sorted(jornadas[dia], key=lambda j: (j["inicio"], str(j["alocacao_id"])))
                limite_agenda = None
                for j in agenda:
                    if limite_agenda is not None and j["inicio"] < limite_agenda:
                        avisos[dia].add("ESCALAS_CONFLITANTES")
                    limite_agenda = max(j["fim"], limite_agenda) if limite_agenda is not None else j["fim"]
                previstos = abonados = faltas = atrasos = Fraction()
                intervalos = []
                em_aberto = False
                for jornada in agenda:
                    correspondentes = [r for r in feriados_dia if r.setor_id is None or r.setor_id == jornada["setor_id"]]
                    abonado = bool(folgas or correspondentes)
                    previstos += jornada["liquido"]
                    if abonado:
                        abonados += jornada["liquido"]
                    elif jornada["fim_turno"] > agora:
                        em_aberto = True
                    elif not avisos[dia]:
                        assistidos = presenca.get(jornada["alocacao_id"], [])
                        bruto_dia = _segundos(jornada["inicio"], jornada["fim"])
                        coberto = _cobertura(assistidos, jornada["inicio"], jornada["fim"])
                        faltas += jornada["liquido"] * max(Fraction(), bruto_dia - coberto) / bruto_dia
                        primeiro = min((max(x, jornada["inicio"]) for x, y in assistidos
                            if x < jornada["fim"] and y > jornada["inicio"]), default=None)
                        if primeiro is not None:
                            atrasos += max(Fraction(), _segundos(jornada["inicio"], primeiro) - jornada["tolerancia"])
                    intervalos.append({
                        "alocacao_id": str(jornada["alocacao_id"]), "setor_id": str(jornada["setor_id"]),
                        "setor_nome": jornada["setor_nome"], "escala_id": str(jornada["escala_id"]),
                        "escala_nome": jornada["escala_nome"],
                        "inicio": jornada["inicio"].astimezone(zona).isoformat(),
                        "fim": jornada["fim"].astimezone(zona).isoformat(),
                        "inicio_turno": jornada["inicio_turno"].astimezone(zona).isoformat(),
                        "fim_turno": jornada["fim_turno"].astimezone(zona).isoformat(),
                        "minutos_previstos": _minutos(jornada["liquido"]), "abonado": abonado,
                    })
                # Feriado de outro setor não abona, nem mesmo nos dias sem turno.
                setores_vigentes = {s.id for al, s, _ in linhas if al.data_inicio <= dia and (al.data_fim is None or al.data_fim >= dia)}
                feriados_aplicaveis = [r for r in feriados_dia if r.setor_id is None or r.setor_id in setores_vigentes
                    or any(j["setor_id"] == r.setor_id for j in jornadas[dia])]
                if folgas or (previstos > 0 and abonados == previstos) or (not previstos and feriados_aplicaveis):
                    status = "ABONADO_JUSTIFICADO"
                elif avisos[dia]:
                    status = "APURACAO_PENDENTE"
                elif em_aberto:
                    status = "PREVISTO" if a > agora else "EM_ANDAMENTO"
                elif faltas > 0:
                    status = "ABONO_PARCIAL" if abonados else "FALTA" if faltas == previstos else "ATRASO" if atrasos else "JORNADA_INCOMPLETA"
                elif atrasos > 0:
                    status = "ATRASO"
                elif previstos:
                    status = "ABONO_PARCIAL" if abonados else "TRABALHADO"
                else:
                    status = "FOLGA" if setores_vigentes else "SEM_ALOCACAO"
                trabalhados = _cobertura(trabalho_total, a, min(b, agora)) if a < agora else Fraction()
                obrigatorios = previstos - abonados
                # Excedente diário preliminar; não calcula adicionais ou banco de horas.
                extras = max(Fraction(), trabalhados - obrigatorios) if not avisos[dia] and not em_aberto else Fraction()
                if extras and status in {"FOLGA", "SEM_ALOCACAO"}:
                    status = "TRABALHADO"
                medidas = {"previstos": previstos, "abonados": abonados, "exigiveis": obrigatorios,
                    "trabalhados": trabalhados, "faltas": faltas, "atrasos": atrasos, "extras": extras}
                for campo, valor in medidas.items():
                    totais[campo] += valor
                dias.append({"data": dia.isoformat(), "status": status,
                    "descricao_status": "Abonado/Justificado" if status == "ABONADO_JUSTIFICADO" else status,
                    **{"minutos_" + campo: _minutos(valor) for campo, valor in medidas.items()},
                    "intervalos_previstos": intervalos,
                    "feriados": [{"id": str(r.id), "descricao": r.descricao,
                        "setor_id": str(r.setor_id) if r.setor_id else None} for r in feriados_aplicaveis],
                    "afastamentos": [{"id": str(r.id), "tipo": TipoAfastamento(r.tipo).value} for r in folgas],
                    "pendencias": sorted(avisos[dia]),
                    "marcacoes": [{"id": str(p.id), "alocacao_id": str(p.alocacao_id),
                    "tipo": TipoPonto(p.tipo).value, "situacao": SituacaoPonto(p.situacao).value,
                        "invalidado": p.id in invalidacoes,
                        "invalidacao": invalidacoes.get(p.id),
                        "origem": "REGISTRO",
                        "motivos": p.motivos,
                        "aprovado_gestor": p.id in aprovacoes,
                        "aprovacao": aprovacoes.get(p.id),
                        "reaprovado_rh": aprovacoes.get(p.id, {}).get("tipo_ocorrencia") == "REAPROVACAO_RH",
                        "historico_decisoes": decisoes.get(p.id, []),
                        "correcao": auditoria(correcoes[p.id]) if p.id in correcoes else None,
                        "tipo_efetivo": TipoPonto(correcoes[p.id].tipo_proposto).value if p.id in correcoes else TipoPonto(p.tipo).value,
                        "ocorrido_em_efetivo": correcoes[p.id].ocorrido_em_proposto.astimezone(zona).isoformat() if p.id in correcoes else p.ocorrido_em.astimezone(zona).isoformat(),
                        "foto_url": f"/api/v1/admin/pontos/{p.id}/selfie" if p.evento_cliente_id in fotos else None,
                        "foto_recebida_em": fotos[p.evento_cliente_id].astimezone(zona).isoformat()
                            if p.evento_cliente_id in fotos else None,
                        "geofence": {"raio_metros": float(p.raio_validado_metros),
                            "distancia_metros": float(p.distancia_centro_metros) if p.distancia_centro_metros is not None else None,
                            "politica": PoliticaLocalizacao(p.politica_localizacao_validada).value},
                        "ocorrido_em": p.ocorrido_em.astimezone(zona).isoformat()} for p in pontos
                        if (correcoes[p.id].ocorrido_em_proposto if p.id in correcoes else p.ocorrido_em).astimezone(zona).date() == dia]
                        + [{"id": str(m.id), "origem": "MANUAL_RH", "tipo": TipoPonto(m.tipo_proposto).value,
                            "situacao": SituacaoPonto.ACEITA.value, "invalidado": False,
                            "aprovado_gestor": True, "aprovacao": auditoria(m),
                            "ocorrido_em": m.ocorrido_em_proposto.astimezone(zona).isoformat(),
                            "foto_url": None, "foto_recebida_em": None, "geofence": None, "motivos": []}
                           for m in manuais if m.ocorrido_em_proposto.astimezone(zona).date() == dia]})
            return {"espelho": {"empresa_id": str(empresa), "ano": ano, "mes": mes,
                "fuso_horario": zona.key, "apuracao_definitiva": False,
                "funcionario": {"id": str(alvo.id), "usuario_id": str(alvo.usuario_id) if alvo.usuario_id else None,
                    "nome": alvo.nome, "matricula": alvo.matricula}, "alocacoes_historicas": historico,
                "dias": dias, "totais": {"minutos_" + campo: _minutos(valor) for campo, valor in totais.items()},
                "tem_pendencias": any(d["pendencias"] for d in dias)}}, 200
        return executar_empresa(usuario_id, empresa_id, operacao, session)
