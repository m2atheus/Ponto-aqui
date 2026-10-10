"""W05: projeção histórica e conflito de intervalos semiabertos entre setores."""

from datetime import date, datetime, time, timedelta, timezone
import uuid
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import or_, select
from sqlalchemy.exc import SQLAlchemyError

from app import db
from app.models import Alocacoes, Empresas, Escalas, Funcionarios, ModeloEscala, Turnos, Usuarios
from app.utils.time_calculator import TimeCalculator


class ScheduleValidationError(ValueError):
    def __init__(self, codigo, mensagem, status=400, detalhes=None):
        super().__init__(mensagem)
        self.codigo, self.status, self.detalhes = codigo, status, detalhes

    def response(self):
        erro = {"codigo": self.codigo, "mensagem": str(self)}
        if self.detalhes is not None:
            erro["detalhes"] = self.detalhes
        return {"erro": erro}, self.status


def _uuid(valor):
    try:
        return uuid.UUID(str(valor))
    except (ValueError, TypeError, AttributeError):
        raise ScheduleValidationError("IDENTIFICADOR_INVALIDO", "Informe identificadores UUID válidos.") from None


def _data(valor):
    if isinstance(valor, str):
        try:
            valor = date.fromisoformat(valor)
        except ValueError:
            raise ScheduleValidationError("PERIODO_INVALIDO", "Use datas AAAA-MM-DD.") from None
    if type(valor) is not date:
        raise ScheduleValidationError("PERIODO_INVALIDO", "Informe início e fim como datas, sem horário.")
    return valor


class CheckScheduleConflictService:
    MAX_DIAS_PROJECAO = 3660

    @staticmethod
    def intervalos_sobrepostos(start_a, end_a, start_b, end_b):
        """[a,b) ∩ [c,d): endpoints iguais não conflitam; exige instantes aware."""
        valores = (start_a, end_a, start_b, end_b)
        if any(not isinstance(v, datetime) or v.utcoffset() is None for v in valores):
            raise ValueError("Intervalos exigem datetimes com fuso horário.")
        a, b, c, d = (v.astimezone(timezone.utc) for v in valores)
        if a >= b or c >= d:
            raise ValueError("Início deve anteceder o fim de cada intervalo.")
        return a < d and c < b

    @staticmethod
    def _turnos(session, empresa_id, escala):
        turnos = session.scalars(select(Turnos).where(
            Turnos.empresa_id == empresa_id, Turnos.escala_id == escala.id,
        ).order_by(Turnos.ordem)).all()
        if not turnos or escala.modelo == ModeloEscala.LEGADO:
            raise ScheduleValidationError("ESCALA_SEM_TURNOS", "Escala sem turnos estruturados para projeção.",
                                          detalhes={"escala_id": str(escala.id)})
        return turnos

    @staticmethod
    def _projetar(session, empresa_id, escala, inicio, fim, zona, *, detalhar=False):
        if inicio > fim:
            return []
        turnos = CheckScheduleConflictService._turnos(session, empresa_id, escala)
        intervalos = []
        metadados = {}
        if escala.modelo in (ModeloEscala.PLANTAO_12X36, ModeloEscala.PLANTAO_24X72):
            duracao_plantao = 720 if escala.modelo == ModeloEscala.PLANTAO_12X36 else 1440
            ancora_hora = turnos[0].hora_inicio
            ancora_minutos = ancora_hora.hour * 60 + ancora_hora.minute
            componentes = []
            turnos_por_componente = {}
            for turno in turnos:
                offset = (turno.hora_inicio.hour * 60 + turno.hora_inicio.minute - ancora_minutos) % 1440
                duracao = TimeCalculator.calcular_duracao_turno(
                    turno.hora_inicio, turno.hora_fim, fim_dia_seguinte=turno.fim_dia_seguinte,
                )
                # Valida intervalo sem encurtar a ocupação do plantão.
                TimeCalculator.calcular_duracao_turno(turno.hora_inicio, turno.hora_fim,
                    turno.tempo_intervalo, fim_dia_seguinte=turno.fim_dia_seguinte)
                if offset + duracao > duracao_plantao:
                    raise ValueError("Componente ultrapassa a duração do plantão cíclico.")
                componentes.append((offset, offset + duracao))
                turnos_por_componente[(offset, offset + duracao)] = turno
            componentes.sort()
            if max(f for _, f in componentes) != duracao_plantao:
                raise ValueError("Os turnos devem cobrir o início e o término do plantão cíclico.")
            if any(b > c for (_, b), (c, _) in zip(componentes, componentes[1:])):
                raise ValueError("Turnos da própria escala se sobrepõem.")
            minutos_fim = (ancora_minutos + duracao_plantao) % 1440
            dias = TimeCalculator.projetar_escala_ciclica(
                escala.modelo, escala.data_referencia, ancora_hora,
                time(minutos_fim // 60, minutos_fim % 60), (fim - inicio).days + 1,
                data_inicio=inicio, fim_dia_seguinte=duracao_plantao == 1440,
                fuso_horario=zona.key,
            )
            plantas = {i["inicio_turno"] for dia in dias for i in dia["intervalos"]}
            for instante in plantas:
                start = datetime.fromisoformat(instante)
                # Vigência refere-se ao dia local de início, não à madrugada seguinte.
                if inicio <= start.date() <= fim:
                    start = start.astimezone(timezone.utc)
                    for a, b in componentes:
                        par = (start + timedelta(minutes=a), start + timedelta(minutes=b))
                        intervalos.append(par)
                        metadados[par] = turnos_por_componente[(a, b)]
        else:
            for numero in range((fim - inicio).days + 1):
                dia = inicio + timedelta(days=numero)
                for turno in turnos:
                    if escala.modelo == ModeloEscala.COMERCIAL_5X2 and set(turno.dias_semana) - set(range(1, 6)):
                        raise ValueError("Escala 5x2 só pode conter dias de segunda a sexta.")
                    if dia.isoweekday() not in turno.dias_semana:
                        continue
                    TimeCalculator.calcular_duracao_turno(turno.hora_inicio, turno.hora_fim,
                        turno.tempo_intervalo, fim_dia_seguinte=turno.fim_dia_seguinte)
                    dia_fim = dia + timedelta(days=int(turno.fim_dia_seguinte or turno.hora_fim < turno.hora_inicio))
                    start = datetime.combine(dia, turno.hora_inicio, tzinfo=zona)
                    end = datetime.combine(dia_fim, turno.hora_fim, tzinfo=zona)
                    if any(v.utcoffset() != v.replace(fold=1).utcoffset() for v in (start, end)):
                        raise ValueError("Turno em horário local ambíguo ou inexistente.")
                    par = (start.astimezone(timezone.utc), end.astimezone(timezone.utc))
                    intervalos.append(par)
                    metadados[par] = turno
        intervalos.sort()
        if any(a >= b for a, b in intervalos):
            raise ValueError("Turno com duração inválida.")
        if any(b > c for (_, b), (c, _) in zip(intervalos, intervalos[1:])):
            raise ValueError("Turnos da própria escala se sobrepõem.")
        if detalhar:
            return [{"inicio": a, "fim": b, "turno_id": str(metadados[(a, b)].id),
                "tempo_intervalo": metadados[(a, b)].tempo_intervalo} for a, b in intervalos]
        return intervalos

    @staticmethod
    def validar_alocacao(empresa_id, usuario_id, escala_id, data_inicio, data_fim, *, session=None):
        """Retorna (JSON, status), sem inserir, encerrar alocações ou fazer commit.

        Exige período finito; datas de vigência são inclusivas. Em sucesso, mantém
        lock do funcionário até o caller inserir a alocação e confirmar a MESMA
        transação. Todo futuro cadastro deve usar esse protocolo para evitar
        duas validações simultâneas aprovarem escalas conflitantes. O caller deve
        encerrar a transação também em erros de validação.
        """
        session = session if session is not None else db.session
        try:
            empresa_id, usuario_id, escala_id = map(_uuid, (empresa_id, usuario_id, escala_id))
            if data_fim is None:
                raise ScheduleValidationError("PERIODO_FINITO_OBRIGATORIO", "A validação exige data_fim explícita.")
            inicio, fim = _data(data_inicio), _data(data_fim)
            if fim < inicio or (fim - inicio).days + 1 > CheckScheduleConflictService.MAX_DIAS_PROJECAO:
                raise ScheduleValidationError("PERIODO_INVALIDO", "Período deve conter entre 1 e 3660 dias.")
            if inicio < date.min + timedelta(days=2) or fim > date.max - timedelta(days=2):
                raise ScheduleValidationError("PERIODO_INVALIDO", "Período fora dos limites de projeção.")
            empresa = session.scalar(select(Empresas).where(Empresas.id == empresa_id, Empresas.ativo.is_(True)))
            usuario = session.scalar(select(Usuarios).where(
                Usuarios.id == usuario_id, Usuarios.empresa_id == empresa_id, Usuarios.ativo.is_(True),
            ).with_for_update())
            funcionario = session.scalar(select(Funcionarios).where(
                Funcionarios.usuario_id == usuario_id, Funcionarios.empresa_id == empresa_id,
                Funcionarios.ativo.is_(True),
            ).with_for_update())
            escala = session.scalar(select(Escalas).where(
                Escalas.id == escala_id, Escalas.empresa_id == empresa_id, Escalas.ativo.is_(True),
            ))
            if empresa is None or usuario is None or funcionario is None or escala is None:
                raise ScheduleValidationError("VINCULO_NAO_ENCONTRADO", "Usuário, funcionário ou escala indisponível nesta empresa.", 404)
            zona = ZoneInfo(empresa.fuso_horario)
            novos = CheckScheduleConflictService._projetar(session, empresa_id, escala, inicio, fim, zona)
            # Não filtra por data_fim NULL nem por setor/ativo da escala: histórico
            # ainda vigente e plantões que atravessam os limites também ocupam.
            margem_inicio, margem_fim = inicio - timedelta(days=2), fim + timedelta(days=2)
            alocacoes = session.scalars(select(Alocacoes).where(
                Alocacoes.empresa_id == empresa_id, Alocacoes.funcionario_id == funcionario.id,
                Alocacoes.data_inicio <= margem_fim,
                or_(Alocacoes.data_fim.is_(None), Alocacoes.data_fim >= margem_inicio),
            ).order_by(Alocacoes.data_inicio, Alocacoes.id)).all()
            for alocacao in alocacoes:
                existente = session.scalar(select(Escalas).where(
                    Escalas.id == alocacao.escala_id, Escalas.empresa_id == empresa_id,
                ))
                if existente is None:
                    raise ScheduleValidationError("ALOCACAO_SEM_ESCALA", "Alocação existente sem escala projetável.",
                        detalhes={"alocacao_id": str(alocacao.id)})
                ocupados = CheckScheduleConflictService._projetar(session, empresa_id, existente,
                    max(margem_inicio, alocacao.data_inicio),
                    min(margem_fim, alocacao.data_fim or margem_fim), zona)
                # Duas listas ordenadas: O(n+m), em vez de cruzar todos os pares.
                i = j = 0
                while i < len(novos) and j < len(ocupados):
                    a, b = novos[i]
                    c, d = ocupados[j]
                    if CheckScheduleConflictService.intervalos_sobrepostos(a, b, c, d):
                        start, end = max(a, c).astimezone(zona), min(b, d).astimezone(zona)
                        raise ScheduleValidationError("CONFLITO_ESCALA",
                            f"Conflito com a escala {existente.nome} em {start.date().isoformat()}.", 409,
                            {"escala_id": str(existente.id), "escala_nome": existente.nome,
                             "alocacao_id": str(alocacao.id), "setor_id": str(alocacao.setor_id),
                             "data": start.date().isoformat(), "inicio": start.isoformat(), "fim": end.isoformat()})
                    if b <= d:
                        i += 1
                    else:
                        j += 1
            return {"valida": True, "usuario_id": str(usuario_id), "escala_id": str(escala_id),
                    "intervalos": [{"inicio": a.astimezone(zona).isoformat(), "fim": b.astimezone(zona).isoformat()}
                                   for a, b in novos]}, 200
        except ScheduleValidationError as error:
            return error.response()
        except (ValueError, ZoneInfoNotFoundError, OverflowError):
            return ScheduleValidationError("ESCALA_INVALIDA", "Configuração de turnos, referência ou fuso inválida.").response()
        except SQLAlchemyError:
            session.rollback()
            return {"erro": {"codigo": "AGENDA_INDISPONIVEL", "mensagem": "Não foi possível validar a agenda."}}, 503
