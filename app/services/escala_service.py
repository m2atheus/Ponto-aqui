"""Escalas estruturadas; vínculos existentes impedem reescrever o histórico."""
import re
from datetime import date, time, timedelta
from zoneinfo import ZoneInfo
from sqlalchemy import delete, func, select

from app.models import Alocacoes, Empresas, Escalas, ModeloEscala, TipoEscala, Turnos
from app.utils.time_calculator import TimeCalculator
from .check_schedule_conflict_service import CheckScheduleConflictService
from .rh_access import GestaoError, executar_rh
from .w06_validation import data_civil, identificador


class EscalaService:
    @staticmethod
    def _json(session, row):
        turnos = session.scalars(select(Turnos).where(Turnos.empresa_id == row.empresa_id,
            Turnos.escala_id == row.id).order_by(Turnos.ordem)).all()
        return {"id": str(row.id), "empresa_id": str(row.empresa_id), "nome": row.nome,
            "ativo": row.ativo, "modelo": row.modelo.value,
            "data_referencia": row.data_referencia.isoformat() if row.data_referencia else None,
            "turnos": [{"hora_inicio": t.hora_inicio.strftime("%H:%M"), "hora_fim": t.hora_fim.strftime("%H:%M"),
                "tempo_intervalo": t.tempo_intervalo, "dias_semana": t.dias_semana,
                "fim_dia_seguinte": t.fim_dia_seguinte} for t in turnos]}

    @staticmethod
    def _validar(dados):
        if not isinstance(dados, dict) or dados.keys() - {"nome", "ativo", "modelo", "data_referencia", "turnos"}:
            raise GestaoError("Informe os dados da escala, sem campos desconhecidos.")
        nome = dados.get("nome")
        if not isinstance(nome, str) or not 1 <= len(nome.strip()) <= 120:
            raise GestaoError("Informe um nome de até 120 caracteres.")
        ativo = dados.get("ativo", True)
        if type(ativo) is not bool:
            raise GestaoError("ativo deve ser booleano.")
        try:
            modelo = ModeloEscala(dados.get("modelo"))
            if modelo == ModeloEscala.LEGADO:
                raise ValueError()
        except (ValueError, TypeError):
            raise GestaoError("Selecione 24x72, 12x36, Diurno ou 5x2.") from None
        ciclo = modelo in (ModeloEscala.PLANTAO_12X36, ModeloEscala.PLANTAO_24X72)
        referencia = data_civil(dados.get("data_referencia"), "data_referencia") if ciclo else None
        if referencia is not None and not 1900 <= referencia.year <= 2100:
            raise GestaoError("A referência deve usar um ano entre 1900 e 2100.")
        turnos = dados.get("turnos")
        if not isinstance(turnos, list) or not 1 <= len(turnos) <= 16:
            raise GestaoError("Informe entre 1 e 16 turnos para a escala.")
        componentes = []
        carga = 0
        for ordem, turno in enumerate(turnos):
            if not isinstance(turno, dict) or turno.keys() - {"hora_inicio", "hora_fim", "tempo_intervalo", "dias_semana", "fim_dia_seguinte"}:
                raise GestaoError("Dados do turno inválidos.")
            horas = []
            for key in ("hora_inicio", "hora_fim"):
                valor = turno.get(key)
                if not isinstance(valor, str) or not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", valor):
                    raise GestaoError("Horários devem usar HH:mm, entre 00:00 e 23:59.")
                horas.append(time.fromisoformat(valor))
            dias = turno.get("dias_semana", [1, 2, 3, 4, 5])
            if not isinstance(dias, list) or not dias or any(type(d) is not int or d not in range(1, 8) for d in dias) or len(set(dias)) != len(dias):
                raise GestaoError("Informe dias da semana únicos, de 1 a 7.")
            intervalo, virada = turno.get("tempo_intervalo", 0), turno.get("fim_dia_seguinte", False)
            try:
                duracao = TimeCalculator.calcular_duracao_turno(*horas, intervalo, fim_dia_seguinte=virada)
            except ValueError as error:
                raise GestaoError(str(error)) from None
            if modelo == ModeloEscala.COMERCIAL_5X2 and set(dias) != {1, 2, 3, 4, 5}:
                raise GestaoError("Escala 5x2 deve usar segunda a sexta-feira.")
            if modelo == ModeloEscala.DIURNO and (horas[1] <= horas[0] or virada):
                raise GestaoError("Turno diurno deve começar e terminar no mesmo dia.")
            componentes.append({"ordem": ordem, "hora_inicio": horas[0], "hora_fim": horas[1],
                "tempo_intervalo": intervalo, "fim_dia_seguinte": virada, "dias_semana": sorted(dias)})
            carga += duracao * len(dias) if not ciclo else 0
        if carga > 10080:
            raise GestaoError("Carga semanal acima do limite permitido.")
        return {"nome": nome.strip(), "ativo": ativo, "modelo": modelo,
            "tipo": TipoEscala.CICLICA if ciclo else TipoEscala.SEMANAL,
            "data_referencia": referencia, "carga_semanal_minutos": carga}, componentes

    @staticmethod
    def _salvar(usuario_id, empresa_id, dados, alvo_id=None, session=None):
        def operacao(session, empresa):
            company = session.scalar(select(Empresas).where(Empresas.id == empresa).with_for_update())
            row = None
            if alvo_id is not None:
                aid = identificador(alvo_id, "escala_id")
                row = session.scalar(select(Escalas).where(Escalas.id == aid, Escalas.empresa_id == empresa).with_for_update())
                if row is None:
                    raise GestaoError("Escala não encontrada nesta empresa.", 404, "ESCALA_NAO_ENCONTRADA")
                if not isinstance(dados, dict) or not dados:
                    raise GestaoError("Informe os campos para editar a escala.")
                merged = {k: v for k, v in EscalaService._json(session, row).items() if k not in {"id", "empresa_id"}}
                merged.update(dados)
                usada = session.scalar(select(Alocacoes.id).where(Alocacoes.empresa_id == empresa, Alocacoes.escala_id == row.id).limit(1))
                if usada and any(merged.get(k) != EscalaService._json(session, row).get(k) for k in ("modelo", "turnos", "data_referencia")):
                    raise GestaoError("Esta escala possui histórico de alocações. Crie outra escala para alterar os turnos.", 409, "ESCALA_COM_HISTORICO")
                if usada or (row.modelo == ModeloEscala.LEGADO and not set(dados).intersection({"modelo", "turnos", "data_referencia"})):
                    if set(dados) - {"nome", "ativo", "modelo", "turnos", "data_referencia"}:
                        raise GestaoError("Campos da escala inválidos.")
                    nome, ativo = merged["nome"], merged["ativo"]
                    if not isinstance(nome, str) or not 1 <= len(nome.strip()) <= 120 or type(ativo) is not bool:
                        raise GestaoError("Confira o nome e o status da escala.")
                    valores, componentes = {"nome": nome.strip(), "ativo": ativo}, None
                else:
                    valores, componentes = EscalaService._validar(merged)
            else:
                valores, componentes = EscalaService._validar(dados)
            query = select(Escalas.id).where(Escalas.empresa_id == empresa, func.lower(Escalas.nome) == valores["nome"].lower())
            if row is not None:
                query = query.where(Escalas.id != row.id)
            if session.scalar(query.limit(1)):
                raise GestaoError("Nome de escala já cadastrado nesta empresa.", 409, "ESCALA_DUPLICADA")
            if row is None:
                row = Escalas(empresa_id=empresa, regras={"versao": 1}, **valores)
                session.add(row)
            else:
                for key, value in valores.items():
                    setattr(row, key, value)
            session.flush()
            if componentes is not None:
                session.execute(delete(Turnos).where(Turnos.empresa_id == empresa, Turnos.escala_id == row.id))
                session.add_all([Turnos(empresa_id=empresa, escala_id=row.id, **t) for t in componentes])
                session.flush()
                referencia = row.data_referencia or date(2026, 1, 5)
                try:
                    intervalos = CheckScheduleConflictService._projetar(session, empresa, row,
                        referencia, referencia + timedelta(days=15), ZoneInfo(company.fuso_horario))
                    if any(b > c for (_, b), (c, _) in zip(intervalos, intervalos[1:])):
                        raise ValueError("Os turnos da própria escala se sobrepõem.")
                except ValueError as error:
                    raise GestaoError(str(error)) from None
            payload = EscalaService._json(session, row)
            session.commit()
            return {"escala": payload}, 201 if alvo_id is None else 200
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def listar(usuario_id, empresa_id, session=None):
        def operacao(session, empresa):
            rows = session.scalars(select(Escalas).where(Escalas.empresa_id == empresa).order_by(Escalas.nome)).all()
            return {"escalas": [EscalaService._json(session, row) for row in rows]}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def criar(usuario_id, empresa_id, dados, session=None):
        return EscalaService._salvar(usuario_id, empresa_id, dados, session=session)

    @staticmethod
    def atualizar(usuario_id, empresa_id, alvo_id, dados, session=None):
        return EscalaService._salvar(usuario_id, empresa_id, dados, alvo_id, session)

    @staticmethod
    def remover(usuario_id, empresa_id, alvo_id, session=None):
        def operacao(session, empresa):
            aid = identificador(alvo_id, "escala_id")
            row = session.scalar(select(Escalas).where(Escalas.id == aid, Escalas.empresa_id == empresa).with_for_update())
            if row is None:
                raise GestaoError("Escala não encontrada nesta empresa.", 404, "ESCALA_NAO_ENCONTRADA")
            if session.scalar(select(Alocacoes.id).where(Alocacoes.empresa_id == empresa, Alocacoes.escala_id == aid).limit(1)):
                raise GestaoError("Não é possível remover uma escala com histórico de alocações. Desative-a para impedir novos vínculos.", 409, "ESCALA_COM_HISTORICO")
            session.execute(delete(Turnos).where(Turnos.empresa_id == empresa, Turnos.escala_id == aid))
            session.delete(row)
            session.commit()
            return {"id": str(aid), "removido": True}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)
