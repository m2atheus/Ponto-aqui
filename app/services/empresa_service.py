"""Cadastro global exclusivo do Superadmin; empresa e RH na mesma transação."""
import re
import uuid

from flask import current_app
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from app import db
from app.models import Empresas, PapelUsuario, Usuarios
from .auth_service import AuthService


class EmpresaError(Exception):
    def __init__(self, mensagem, status=422, codigo="DADOS_INVALIDOS"):
        self.mensagem, self.status, self.codigo = mensagem, status, codigo


class EmpresaService:
    @staticmethod
    def _executar(usuario_id, empresa_id, operacao, session):
        session = session if session is not None else db.session
        try:
            perfil, status = AuthService.me(usuario_id, {"empresa_id": empresa_id}, session=session)
            if status != 200:
                return perfil, status
            if perfil["usuario"]["papel"] != "SUPERADMIN" or empresa_id is not None:
                raise EmpresaError("Acesso exclusivo do Superadmin.", 403, "ACESSO_NEGADO")
            return operacao(session)
        except EmpresaError as error:
            session.rollback()
            return {"erro": {"codigo": error.codigo, "mensagem": error.mensagem}}, error.status
        except IntegrityError as error:
            session.rollback()
            if getattr(error.orig, "pgcode", None) == "23505":
                return {"erro": {"codigo": "CADASTRO_DUPLICADO", "mensagem": "CNPJ ou e-mail do RH já cadastrado."}}, 409
            current_app.logger.error("Falha de integridade ao salvar empresa.")
            return {"erro": {"codigo": "PERSISTENCIA_INDISPONIVEL", "mensagem": "Não foi possível salvar a empresa."}}, 503
        except SQLAlchemyError:
            session.rollback()
            current_app.logger.error("Falha de banco no cadastro de empresas.")
            return {"erro": {"codigo": "PERSISTENCIA_INDISPONIVEL", "mensagem": "Banco indisponível. Tente novamente."}}, 503

    @staticmethod
    def _json(empresa, administrador=None):
        return {"id": str(empresa.id), "razao_social": empresa.razao_social,
                "cnpj": empresa.cnpj, "ativo": empresa.ativo,
                "admin_email": empresa.admin_email,
                "admin_nome": administrador.nome if administrador else None}

    @staticmethod
    def _validar(dados, criacao):
        campos = {"razao_social", "cnpj", "ativo", "admin_email", "admin_nome", "admin_senha"}
        if not isinstance(dados, dict) or not dados or dados.keys() - campos:
            raise EmpresaError("Campos ausentes ou desconhecidos no cadastro.")
        if criacao and not {"razao_social", "cnpj", "admin_email", "admin_nome", "admin_senha"} <= dados.keys():
            raise EmpresaError("Informe a empresa, o nome, e-mail e senha inicial do RH.")
        normalizado = dict(dados)
        for campo, limite in (("razao_social", 200), ("admin_nome", 150)):
            if campo in dados:
                if not isinstance(dados[campo], str) or not 1 <= len(dados[campo].strip()) <= limite:
                    raise EmpresaError(f"{campo} deve conter entre 1 e {limite} caracteres.")
                normalizado[campo] = dados[campo].strip()
        if "cnpj" in dados:
            if not isinstance(dados["cnpj"], str) or not re.fullmatch(r"[0-9./\-\s]+", dados["cnpj"]):
                raise EmpresaError("Informe os 14 dígitos do CNPJ.")
            normalizado["cnpj"] = re.sub(r"\D", "", dados["cnpj"])
            if len(normalizado["cnpj"]) != 14:
                raise EmpresaError("Informe os 14 dígitos do CNPJ.")
        if "admin_email" in dados:
            email = dados["admin_email"]
            if not isinstance(email, str) or len(email.strip()) > 254 or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email.strip()):
                raise EmpresaError("Informe um e-mail válido para o RH.")
            normalizado["admin_email"] = email.strip().lower()
        if "ativo" in dados and type(dados["ativo"]) is not bool:
            raise EmpresaError("ativo deve ser booleano.")
        if "admin_senha" in dados:
            senha = dados["admin_senha"]
            if not isinstance(senha, str) or not 8 <= len(senha) <= 1024:
                raise EmpresaError("A senha do RH deve conter entre 8 e 1024 caracteres.")
        return normalizado

    @staticmethod
    def listar(usuario_id, empresa_id, session=None):
        def operacao(session):
            rows = session.execute(select(Empresas, Usuarios).outerjoin(Usuarios,
                (Usuarios.empresa_id == Empresas.id) & (Usuarios.email == Empresas.admin_email)
                & (Usuarios.papel == PapelUsuario.RH)).order_by(Empresas.criado_em, Empresas.id)).all()
            return {"empresas": [EmpresaService._json(company, admin) for company, admin in rows]}, 200
        return EmpresaService._executar(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def criar(usuario_id, empresa_id, dados, session=None):
        def operacao(session):
            values = EmpresaService._validar(dados, True)
            company = Empresas(razao_social=values["razao_social"], cnpj=values["cnpj"],
                admin_email=values["admin_email"], ativo=values.get("ativo", True))
            session.add(company)
            session.flush()
            admin = Usuarios(empresa_id=company.id, nome=values["admin_nome"], email=values["admin_email"],
                senha_hash=AuthService.hash_senha(values["admin_senha"]), papel=PapelUsuario.RH)
            session.add(admin)
            session.flush()
            result = EmpresaService._json(company, admin)
            session.commit()
            return {"empresa": result}, 201
        return EmpresaService._executar(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def atualizar(usuario_id, empresa_id, alvo_id, dados, session=None):
        def operacao(session):
            values = EmpresaService._validar(dados, False)
            try:
                company_id = uuid.UUID(str(alvo_id))
            except (ValueError, TypeError):
                raise EmpresaError("Empresa não encontrada.", 404, "EMPRESA_NAO_ENCONTRADA") from None
            company = session.scalar(select(Empresas).where(Empresas.id == company_id).with_for_update())
            if company is None:
                raise EmpresaError("Empresa não encontrada.", 404, "EMPRESA_NAO_ENCONTRADA")
            admin = session.scalar(select(Usuarios).where(Usuarios.empresa_id == company.id,
                Usuarios.email == company.admin_email, Usuarios.papel == PapelUsuario.RH).with_for_update())
            admin_fields = {"admin_email", "admin_nome", "admin_senha"} & values.keys()
            if admin_fields:
                if admin is None:
                    if not {"admin_email", "admin_nome", "admin_senha"} <= values.keys():
                        raise EmpresaError("Para vincular o RH, informe nome, e-mail e senha inicial.")
                    admin = Usuarios(empresa_id=company.id, nome=values["admin_nome"], email=values["admin_email"],
                        senha_hash=AuthService.hash_senha(values["admin_senha"]), papel=PapelUsuario.RH)
                    session.add(admin)
                else:
                    if "admin_email" in values:
                        admin.email = values["admin_email"]
                    if "admin_nome" in values:
                        admin.nome = values["admin_nome"]
                    if "admin_senha" in values:
                        admin.senha_hash = AuthService.hash_senha(values["admin_senha"])
                company.admin_email = admin.email
            for campo in ("razao_social", "cnpj", "ativo"):
                if campo in values:
                    setattr(company, campo, values[campo])
            session.flush()
            result = EmpresaService._json(company, admin)
            session.commit()
            return {"empresa": result}, 200
        return EmpresaService._executar(usuario_id, empresa_id, operacao, session)
