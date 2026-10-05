"""W01: autenticação e contexto de empresa derivados exclusivamente do banco."""

import uuid

from flask import current_app
from flask_jwt_extended import create_access_token
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from werkzeug.security import check_password_hash, generate_password_hash

from app import db
from app.models import Dispositivos, Empresas, PapelUsuario, Usuarios


# Executa uma verificação de senha também quando o identificador não existe.
_HASH_AUSENTE = generate_password_hash(uuid.uuid4().hex, method="scrypt")
_LOGIN_INVALIDO = {
    "erro": {"codigo": "LOGIN_INVALIDO", "mensagem": "Usuário ou senha inválidos"}
}


class AuthService:
    @staticmethod
    def hash_senha(senha):
        """Usado pelos cadastros/consoles confiáveis antes de persistir senha_hash."""
        if not isinstance(senha, str) or not senha or len(senha) > 1024:
            raise ValueError("A senha deve conter entre 1 e 1024 caracteres.")
        return generate_password_hash(senha, method="scrypt")

    @staticmethod
    def _usuario_json(usuario):
        return {
            "id": str(usuario.id), "nome": usuario.nome, "email": usuario.email,
            "papel": usuario.papel.name,
            "empresa_id": str(usuario.empresa_id) if usuario.empresa_id else None,
        }

    @staticmethod
    def _conta_ativa(session, usuario):
        if usuario is None or not usuario.ativo:
            return False
        if usuario.papel == PapelUsuario.SUPERADMIN:
            return usuario.empresa_id is None
        if usuario.empresa_id is None:
            return False
        return session.scalar(select(Empresas.id).where(
            Empresas.id == usuario.empresa_id, Empresas.ativo.is_(True),
        )) is not None

    @staticmethod
    def login(dados, session=None):
        session = session if session is not None else db.session
        if not isinstance(dados, dict) or dados.keys() - {"email", "senha", "dispositivo_id"}:
            return _LOGIN_INVALIDO, 401
        email, senha = dados.get("email"), dados.get("senha")
        if (not isinstance(email, str) or not email.strip() or len(email.strip()) > 254
                or not isinstance(senha, str) or not senha or len(senha) > 1024):
            return _LOGIN_INVALIDO, 401
        try:
            usuario = session.scalar(select(Usuarios).where(Usuarios.email == email.strip().lower()))
            try:
                senha_valida = check_password_hash(
                    usuario.senha_hash if usuario else _HASH_AUSENTE, senha,
                )
            except (ValueError, TypeError):
                senha_valida = False
            if not senha_valida or not AuthService._conta_ativa(session, usuario):
                return _LOGIN_INVALIDO, 401
            perfil = AuthService._usuario_json(usuario)
            claims = {"empresa_id": perfil["empresa_id"], "role": perfil["papel"]}
            # Claim de aparelho só é emitida depois da conferência no banco.
            if "dispositivo_id" in dados:
                try:
                    dispositivo_id = uuid.UUID(str(dados["dispositivo_id"]))
                except (ValueError, TypeError, AttributeError):
                    return _LOGIN_INVALIDO, 401
                device = session.scalar(select(Dispositivos.id).where(
                    Dispositivos.id == dispositivo_id,
                    Dispositivos.empresa_id == usuario.empresa_id,
                    Dispositivos.usuario_id == usuario.id, Dispositivos.ativo.is_(True),
                ))
                if device is None:
                    return _LOGIN_INVALIDO, 401
                claims["dispositivo_id"] = str(device)
            token = create_access_token(identity=str(usuario.id), additional_claims=claims)
            return {"access_token": token, "token_type": "Bearer", "usuario": perfil}, 200
        except SQLAlchemyError:
            session.rollback()
            current_app.logger.error("Falha de banco na autenticação.")
            return {"erro": {"codigo": "AUTH_INDISPONIVEL", "mensagem": "Autenticação indisponível."}}, 503

    @staticmethod
    def me(usuario_id, claims, session=None):
        """Reconstrói o perfil no servidor ao restaurar uma sessão Flutter."""
        session = session if session is not None else db.session
        try:
            usuario_id = uuid.UUID(str(usuario_id))
        except (ValueError, TypeError, AttributeError):
            return {"erro": {"codigo": "SESSAO_INVALIDA", "mensagem": "Sessão inválida."}}, 401
        try:
            empresa_claim = claims.get("empresa_id")
            if empresa_claim is not None:
                try:
                    empresa_claim = uuid.UUID(str(empresa_claim))
                except (ValueError, TypeError, AttributeError):
                    return {"erro": {"codigo": "SESSAO_INVALIDA", "mensagem": "Sessão inválida."}}, 401
            usuario = session.scalar(select(Usuarios).where(
                Usuarios.id == usuario_id, Usuarios.empresa_id == empresa_claim,
            ))
            if not AuthService._conta_ativa(session, usuario):
                return {"erro": {"codigo": "SESSAO_INVALIDA", "mensagem": "Sessão inválida."}}, 401
            return {"usuario": AuthService._usuario_json(usuario)}, 200
        except SQLAlchemyError:
            session.rollback()
            current_app.logger.error("Falha de banco ao consultar sessão.")
            return {"erro": {"codigo": "AUTH_INDISPONIVEL", "mensagem": "Autenticação indisponível."}}, 503


def configurar_erros_jwt(jwt):
    def unauthorized(*args):
        return {"erro": {"codigo": "TOKEN_INVALIDO", "mensagem": "Token ausente, inválido ou expirado."}}, 401

    jwt.unauthorized_loader(unauthorized)
    jwt.invalid_token_loader(unauthorized)
    jwt.expired_token_loader(unauthorized)
    jwt.revoked_token_loader(unauthorized)
    jwt.needs_fresh_token_loader(unauthorized)
    jwt.token_verification_failed_loader(unauthorized)
