"""Contexto de empresa e erros comuns para operações administrativas do RH."""

import uuid

from flask import current_app
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from app import db
from .auth_service import AuthService


class GestaoError(Exception):
    def __init__(self, mensagem, status=400, codigo="DADOS_INVALIDOS", detalhes=None):
        self.mensagem, self.status, self.codigo = mensagem, status, codigo
        self.detalhes = detalhes


def executar_rh(usuario_id, empresa_id, operacao, session=None):
    return executar_empresa(usuario_id, empresa_id, operacao, session, papeis=("RH",))


def executar_empresa(usuario_id, empresa_id, operacao, session=None, *, papeis=("RH", "GESTOR")):
    session = session if session is not None else db.session
    try:
        payload, status = AuthService.me(usuario_id, {"empresa_id": empresa_id}, session=session)
        if status != 200:
            return payload, status
        perfil = payload["usuario"]
        if perfil["papel"] not in papeis or perfil["empresa_id"] is None:
            raise GestaoError("Seu perfil não permite esta operação na empresa.", 403, "ACESSO_NEGADO")
        return operacao(session, uuid.UUID(perfil["empresa_id"]))
    except GestaoError as error:
        session.rollback()
        detalhe = {"codigo": error.codigo, "mensagem": error.mensagem}
        if error.detalhes is not None:
            detalhe["detalhes"] = error.detalhes
        return {"erro": detalhe}, error.status
    except IntegrityError as error:
        session.rollback()
        if getattr(error.orig, "pgcode", None) == "23P01":
            return {"erro": {
                "codigo": "ALOCACAO_SOBREPOSTA",
                "mensagem": "Este funcionário já possui alocação nesse setor no período informado.",
            }}, 409
        current_app.logger.error("Falha de integridade em operação do RH.")
        return {"erro": {"codigo": "PERSISTENCIA_INDISPONIVEL",
                         "mensagem": "Não foi possível salvar. Tente novamente."}}, 503
    except SQLAlchemyError:
        session.rollback()
        current_app.logger.error("Falha de banco em operação do RH.")
        return {"erro": {"codigo": "PERSISTENCIA_INDISPONIVEL",
                         "mensagem": "Banco indisponível. Tente novamente."}}, 503
