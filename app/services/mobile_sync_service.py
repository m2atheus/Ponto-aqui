"""W08: carga offline por empresa e aparelho, sem alteração de pontos ou login."""

from datetime import datetime, timedelta, timezone
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from flask import current_app
from sqlalchemy import or_, select
from sqlalchemy.exc import SQLAlchemyError

from app import db
from app.models import (
    Alocacoes, Empresas, Escalas, Funcionarios, RegistrosPonto, Setores,
    TipoDispositivo, Turnos,
)
from app.services.device_service import DeviceError, DeviceService


def _agora_utc():
    return datetime.now(timezone.utc)


def _timestamp(valor):
    return valor.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def _funcionario_dto(funcionario):
    return {
        "id": str(funcionario.id), "usuario_id": str(funcionario.usuario_id) if funcionario.usuario_id else None,
        "nome": funcionario.nome, "matricula": funcionario.matricula, "cargo": funcionario.cargo,
    }


def _setor_dto(setor):
    return {
        "id": str(setor.id), "nome": setor.nome,
        "latitude": float(setor.latitude_centro), "longitude": float(setor.longitude_centro),
        "raio_metros": float(setor.raio_metros),
        "politicas": {
            "exige_selfie": setor.exige_selfie,
            "acao_fora_perimetro": setor.acao_fora_perimetro.value,
            "ignorar_localizacao": setor.ignorar_localizacao,
            "limite_desvio_relogio_segundos": setor.limite_desvio_relogio_segundos,
        },
    }


def _alocacao_dto(alocacao):
    return {
        "id": str(alocacao.id), "data_inicio": alocacao.data_inicio.isoformat(),
        "data_fim": alocacao.data_fim.isoformat() if alocacao.data_fim else None,
    }


class MobileSyncService:
    MAX_MARCACOES_RECENTES = 20
    DIAS_MARCACOES_RECENTES = 7

    @staticmethod
    def _alocacoes(session, empresa_id, hoje, *, funcionario_id=None, setor_id=None):
        # Outer join preserva a alocação mesmo quando ainda não há escala.
        consulta = select(Funcionarios, Alocacoes, Setores, Escalas).join(Alocacoes,
            (Alocacoes.funcionario_id == Funcionarios.id) & (Alocacoes.empresa_id == Funcionarios.empresa_id)
        ).join(Setores,
            (Setores.id == Alocacoes.setor_id) & (Setores.empresa_id == Alocacoes.empresa_id)
        ).outerjoin(Escalas,
            (Escalas.id == Alocacoes.escala_id) & (Escalas.empresa_id == Alocacoes.empresa_id)
        ).where(
            Funcionarios.empresa_id == empresa_id, Funcionarios.ativo.is_(True),
            Alocacoes.empresa_id == empresa_id, Setores.empresa_id == empresa_id, Setores.ativo.is_(True),
            Alocacoes.data_inicio <= hoje,
            or_(Alocacoes.data_fim.is_(None), Alocacoes.data_fim >= hoje),
            or_(Escalas.id.is_(None), Escalas.empresa_id == empresa_id),
        )
        if funcionario_id is not None:
            consulta = consulta.where(Funcionarios.id == funcionario_id)
        if setor_id is not None:
            consulta = consulta.where(Setores.id == setor_id)
        return session.execute(consulta.order_by(Funcionarios.nome, Funcionarios.id,
            Alocacoes.data_inicio, Alocacoes.id)).all()

    @staticmethod
    def _escalas_dto(session, empresa_id, linhas):
        escalas = {escala.id: escala for _, _, _, escala in linhas if escala is not None}
        turnos = {id_: [] for id_ in escalas}
        if escalas:
            for turno in session.scalars(select(Turnos).where(
                Turnos.empresa_id == empresa_id, Turnos.escala_id.in_(escalas),
            ).order_by(Turnos.escala_id, Turnos.ordem)):
                turnos[turno.escala_id].append({
                    "hora_inicio": turno.hora_inicio.isoformat(timespec="minutes"),
                    "hora_fim": turno.hora_fim.isoformat(timespec="minutes"),
                    "tempo_intervalo": turno.tempo_intervalo,
                    "fim_dia_seguinte": turno.fim_dia_seguinte,
                    "dias_semana": turno.dias_semana,
                })
        return {id_: {
            "id": str(id_), "nome": escala.nome, "modelo": escala.modelo.value,
            "data_referencia": escala.data_referencia.isoformat() if escala.data_referencia else None,
            "tolerancia_minutos": escala.tolerancia_minutos, "turnos": turnos[id_],
        } for id_, escala in escalas.items()}

    @staticmethod
    def _marcacoes(session, empresa_id, usuario_id, agora):
        # Recebimento é confiável; hora do celular pode conter desvio até futuro.
        # Projeção de colunas evita carregar selfie, GPS, snapshot e JSON bruto.
        consulta = select(RegistrosPonto.id, RegistrosPonto.evento_cliente_id,
            RegistrosPonto.tipo, RegistrosPonto.situacao, RegistrosPonto.ocorrido_em,
            RegistrosPonto.recebido_em, RegistrosPonto.motivos).where(
                RegistrosPonto.empresa_id == empresa_id, RegistrosPonto.usuario_id == usuario_id,
                RegistrosPonto.recebido_em >= agora - timedelta(days=MobileSyncService.DIAS_MARCACOES_RECENTES),
                RegistrosPonto.recebido_em <= agora,
            ).order_by(RegistrosPonto.recebido_em.desc(), RegistrosPonto.id.desc()
            ).limit(MobileSyncService.MAX_MARCACOES_RECENTES)
        return [{"id": str(p.id), "evento_cliente_id": str(p.evento_cliente_id),
                 "tipo": p.tipo.value, "situacao": p.situacao.value,
                 "ocorrido_em": _timestamp(p.ocorrido_em), "recebido_em": _timestamp(p.recebido_em),
                 "motivos": p.motivos} for p in session.execute(consulta)]

    @staticmethod
    def _pessoal(session, empresa_id, usuario_id, hoje, agora):
        funcionario = session.scalar(select(Funcionarios).where(
            Funcionarios.empresa_id == empresa_id, Funcionarios.usuario_id == usuario_id,
            Funcionarios.ativo.is_(True),
        ))
        linhas = MobileSyncService._alocacoes(session, empresa_id, hoje,
            funcionario_id=funcionario.id) if funcionario else []
        escalas = MobileSyncService._escalas_dto(session, empresa_id, linhas)
        alocacoes = [{**_alocacao_dto(alocacao), "setor": _setor_dto(setor),
                      "escala": escalas.get(escala.id) if escala else None}
                     for _, alocacao, setor, escala in linhas]
        status, mensagem = "OK", "Dados sincronizados."
        if funcionario is None:
            status, mensagem = "SEM_FUNCIONARIO", "Cadastro de funcionário indisponível."
        elif not alocacoes:
            status, mensagem = "SEM_ALOCACAO", "Sem alocação vigente para hoje."
        elif len(alocacoes) > 1:
            status, mensagem = "MULTIPLAS_ALOCACOES", "Consulte todas as alocações vigentes para hoje."
        elif alocacoes[0]["escala"] is None:
            status, mensagem = "SEM_ESCALA", "Alocação vigente ainda sem escala."
        elif not alocacoes[0]["escala"]["turnos"]:
            status, mensagem = "ESCALA_SEM_TURNOS", "Escala vigente ainda sem turnos estruturados."
        unica = alocacoes[0] if len(alocacoes) == 1 else None
        return {
            "modo_operacao": "PESSOAL", "status": status, "mensagem_status": mensagem,
            "funcionario": _funcionario_dto(funcionario) if funcionario else None,
            "setor": unica["setor"] if unica else None,
            "escala": unica["escala"] if unica else None,
            "alocacoes": alocacoes,
            "marcacoes_recentes": MobileSyncService._marcacoes(session, empresa_id, usuario_id, agora),
        }

    @staticmethod
    def _relogio(session, empresa_id, setor_id, hoje):
        setor = session.scalar(select(Setores).where(
            Setores.empresa_id == empresa_id, Setores.id == setor_id, Setores.ativo.is_(True),
        ))
        if setor is None:
            raise DeviceError("SETOR_INDISPONIVEL", "Setor do dispositivo indisponível.")
        linhas = MobileSyncService._alocacoes(session, empresa_id, hoje, setor_id=setor.id)
        escalas = MobileSyncService._escalas_dto(session, empresa_id, linhas)
        funcionarios = {}
        for funcionario, alocacao, _, escala in linhas:
            item = funcionarios.setdefault(funcionario.id, {**_funcionario_dto(funcionario), "alocacoes": []})
            item["alocacoes"].append({**_alocacao_dto(alocacao),
                "escala_id": str(escala.id) if escala else None})
        return {
            "modo_operacao": "RELOGIO", "status": "OK" if funcionarios else "SEM_FUNCIONARIOS",
            "mensagem_status": "Dados sincronizados." if funcionarios else "Sem funcionários alocados neste setor hoje.",
            "setor": _setor_dto(setor), "escalas": list(escalas.values()),
            "funcionarios": list(funcionarios.values()),
        }

    @staticmethod
    def sincronizar(empresa_id, usuario_id, device_uuid, claims, *, session=None):
        """Retorna (DTO, HTTP status); data de vigência usa o fuso da empresa.

        Revalida autorização mesmo quando chamado diretamente, sem decorator.
        server_timestamp é capturado na montagem da carga; não corrige o relógio
        do celular. A vigência é de alocação: folgas do ciclo não removem a escala.
        """
        session = session if session is not None else db.session
        try:
            dispositivo = DeviceService.validar_dispositivo(
                empresa_id, usuario_id, device_uuid, claims, session=session,
            )
            empresa_id = dispositivo.empresa_id
            # ID da conta foi validado pelo Service de dispositivo.
            usuario_id = UUID(str(usuario_id))
            empresa = session.scalar(select(Empresas).where(
                Empresas.id == empresa_id, Empresas.ativo.is_(True),
            ))
            if empresa is None:
                raise DeviceError()
            agora = _agora_utc()
            hoje = agora.astimezone(ZoneInfo(empresa.fuso_horario)).date()
            if dispositivo.tipo == TipoDispositivo.PESSOAL:
                payload = MobileSyncService._pessoal(session, empresa_id, usuario_id, hoje, agora)
            else:
                payload = MobileSyncService._relogio(session, empresa_id, dispositivo.setor_id, hoje)
            return {"server_timestamp": _timestamp(agora), "data_referencia": hoje.isoformat(),
                    "fuso_horario": empresa.fuso_horario, **payload}, 200
        except DeviceError as error:
            return error.response()
        except (ZoneInfoNotFoundError, ValueError):
            current_app.logger.error("Fuso de empresa inválido durante sync W08.")
            return {"erro": {"codigo": "FUSO_INVALIDO", "mensagem": "Fuso da empresa indisponível."}}, 503
        except SQLAlchemyError:
            session.rollback()
            current_app.logger.error("Falha de banco na sincronização W08.")
            return {"erro": {"codigo": "SYNC_INDISPONIVEL", "mensagem": "Sincronização indisponível. Tente novamente."}}, 503
