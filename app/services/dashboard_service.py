"""Indicadores agregados: uma consulta de contagens após validar a sessão."""
import uuid

from flask import current_app
from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError

from app import db
from app.models import Empresas, Funcionarios, Setores, Escalas, JustificativasAjustes, StatusAjuste
from .auth_service import AuthService


class DashboardService:
    @staticmethod
    def consultar(usuario_id, empresa_id, session=None):
        session = session if session is not None else db.session
        try:
            payload, status = AuthService.me(usuario_id, {"empresa_id": empresa_id}, session=session)
            if status != 200:
                return payload, status
            perfil = payload["usuario"]
            papel = perfil["papel"]

            def contar(modelo, *filtros):
                return select(func.count()).select_from(modelo).where(*filtros).scalar_subquery()

            if papel == "SUPERADMIN" and perfil["empresa_id"] is None:
                consulta = select(contar(Empresas).label("empresas"))
                empresa = None
            elif papel in {"RH", "GESTOR"} and perfil["empresa_id"] is not None:
                empresa = uuid.UUID(perfil["empresa_id"])
                # O tenant validado no servidor é obrigatório em cada subconsulta.
                consulta = select(
                    contar(Funcionarios, Funcionarios.empresa_id == empresa,
                           Funcionarios.ativo.is_(True)).label("funcionarios"),
                    contar(Setores, Setores.empresa_id == empresa,
                           Setores.ativo.is_(True)).label("setores"),
                    contar(Escalas, Escalas.empresa_id == empresa,
                           Escalas.ativo.is_(True)).label("escalas_ativas"),
                    contar(JustificativasAjustes, JustificativasAjustes.empresa_id == empresa,
                           JustificativasAjustes.status == StatusAjuste.PENDENTE).label("justificativas_pendentes"),
                )
            else:
                return {"erro": {"codigo": "ACESSO_NEGADO",
                                 "mensagem": "Seu perfil não permite consultar os indicadores."}}, 403

            indicadores = dict(session.execute(consulta).mappings().one())
            return {"empresa_id": str(empresa) if empresa else None,
                    "indicadores": indicadores}, 200
        except SQLAlchemyError:
            session.rollback()
            current_app.logger.error("Falha ao consultar indicadores do painel.")
            return {"erro": {"codigo": "PERSISTENCIA_INDISPONIVEL",
                             "mensagem": "Indicadores indisponíveis. Tente novamente."}}, 503
