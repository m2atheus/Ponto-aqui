"""Validações compartilhadas da gestão W06; sem dependência das rotas."""

import re
import uuid
from datetime import date
from urllib.parse import urlsplit

from sqlalchemy import select

from app.models import Funcionarios
from .rh_access import GestaoError


def identificador(value, campo):
    if not isinstance(value, (str, uuid.UUID)):
        raise GestaoError(f"{campo} deve ser um UUID válido.")
    try:
        return uuid.UUID(str(value))
    except ValueError:
        raise GestaoError(f"{campo} deve ser um UUID válido.") from None


def data_civil(value, campo):
    if type(value) is date:
        return value
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise GestaoError(f"{campo} deve usar o formato AAAA-MM-DD.")
    try:
        return date.fromisoformat(value)
    except ValueError:
        raise GestaoError(f"{campo} contém uma data inválida.") from None


def periodo(dados):
    inicio = data_civil(dados.get("data_inicio"), "data_inicio")
    fim = data_civil(dados.get("data_fim"), "data_fim")
    if fim < inicio or fim == date.max:
        raise GestaoError("Informe um período válido; a data final não pode anteceder a inicial.")
    return inicio, fim


def funcionario(session, empresa, *, funcionario_id=None, usuario_id=None, lock=False, ativo=False):
    if funcionario_id is None and usuario_id is None:
        raise GestaoError("Informe usuario_id ou funcionario_id.")
    query = select(Funcionarios).where(Funcionarios.empresa_id == empresa)
    if funcionario_id is not None:
        query = query.where(Funcionarios.id == identificador(funcionario_id, "funcionario_id"))
    if usuario_id is not None:
        query = query.where(Funcionarios.usuario_id == identificador(usuario_id, "usuario_id"))
    if ativo:
        query = query.where(Funcionarios.ativo.is_(True))
    if lock:
        query = query.with_for_update().execution_options(populate_existing=True)
    row = session.scalar(query)
    if row is None:
        raise GestaoError("Funcionário não encontrado nesta empresa.", 404, "FUNCIONARIO_NAO_ENCONTRADO")
    return row


def anexo_url(value):
    if value is None or value == "":
        return None
    if not isinstance(value, str) or len(value) > 2048 or any(c.isspace() for c in value):
        raise GestaoError("Informe uma URL de anexo válida, com até 2048 caracteres.")
    try:
        url = urlsplit(value)
        if url.scheme not in {"http", "https"} or not url.hostname or url.username or url.password:
            raise ValueError()
        url.port
    except ValueError:
        raise GestaoError("O anexo deve usar uma URL HTTP ou HTTPS válida.") from None
    return value
