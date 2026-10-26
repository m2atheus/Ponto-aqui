"""Cadastro W03: funcionários da empresa do RH, com desativação sem exclusão."""

import re
import uuid

from flask import current_app
from sqlalchemy import or_, select, update
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from app import db
from app.models import Afastamentos, Alocacoes, Funcionarios, PapelUsuario, Usuarios
from .auth_service import AuthService


class FuncionarioError(Exception):
    def __init__(self, mensagem, status=400, codigo="DADOS_INVALIDOS"):
        self.mensagem, self.status, self.codigo = mensagem, status, codigo


class FuncionarioService:
    @staticmethod
    def vincular_acesso(usuario_id, empresa_id, funcionario_id, dados, session=None):
        """Cria a credencial e vincula o funcionário na mesma transação."""
        def operacao(session, empresa):
            if not isinstance(dados, dict) or set(dados) != {"email", "senha"}:
                raise FuncionarioError("Informe somente e-mail e senha para gerar o acesso.")
            email, senha = dados["email"], dados["senha"]
            if (not isinstance(email, str) or len(email.strip()) > 254
                    or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email.strip())):
                raise FuncionarioError("Informe um e-mail válido para o funcionário.")
            if not isinstance(senha, str) or not 8 <= len(senha) <= 1024:
                raise FuncionarioError("A senha deve conter entre 8 e 1024 caracteres.")
            try:
                alvo_id = uuid.UUID(str(funcionario_id))
            except (ValueError, TypeError, AttributeError):
                raise FuncionarioError("Funcionário não encontrado nesta empresa.",
                    404, "FUNCIONARIO_NAO_ENCONTRADO") from None

            # Serializa tentativas simultâneas para impedir duas contas por funcionário.
            funcionario = session.scalar(select(Funcionarios).where(
                Funcionarios.id == alvo_id, Funcionarios.empresa_id == empresa,
            ).with_for_update().execution_options(populate_existing=True))
            if funcionario is None:
                raise FuncionarioError("Funcionário não encontrado nesta empresa.",
                    404, "FUNCIONARIO_NAO_ENCONTRADO")
            if funcionario.usuario_id is not None:
                raise FuncionarioError("O funcionário já possui uma conta vinculada.",
                    400, "ACESSO_JA_VINCULADO")
            if not funcionario.ativo:
                raise FuncionarioError("Ative o cadastro do funcionário antes de gerar o acesso.",
                    400, "FUNCIONARIO_INATIVO")

            usuario = Usuarios(
                empresa_id=empresa, nome=funcionario.nome,
                email=email.strip().lower(), matricula=funcionario.matricula,
                senha_hash=AuthService.hash_senha(senha),
                papel=PapelUsuario.FUNCIONARIO, ativo=True,
            )
            try:
                session.add(usuario)
                session.flush()
                funcionario.usuario_id = usuario.id
                session.flush()
                # Só completa referências antes nulas; mantém o histórico de jornada.
                # Alocações prévias precisam deste ID para aceitar batidas no mobile.
                for modelo in (Alocacoes, Afastamentos):
                    session.execute(update(modelo).where(
                        modelo.empresa_id == empresa, modelo.funcionario_id == funcionario.id,
                        modelo.usuario_id.is_(None),
                    ).values(usuario_id=usuario.id).execution_options(synchronize_session="fetch"))
                resultado = {
                    "funcionario": {**FuncionarioService._json(funcionario), "usuario_id": str(usuario.id)},
                    "usuario": AuthService._usuario_json(usuario),
                }
                session.commit()
                return resultado, 201
            except IntegrityError as error:
                constraint = getattr(getattr(error.orig, "diag", None), "constraint_name", None)
                if getattr(error.orig, "pgcode", None) == "23505" and constraint in {
                    "uq_usuarios_email", "uq_usuarios_empresa_email",
                }:
                    raise FuncionarioError("E-mail indisponível para cadastro.",
                        409, "EMAIL_INDISPONIVEL") from None
                raise

        # Revalida o papel RH e a empresa ativa no banco; não confia em role do cliente.
        return FuncionarioService._executar(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def _executar(usuario_id, empresa_id, operacao, session):
        session = session if session is not None else db.session
        try:
            payload, status = AuthService.me(
                usuario_id, {"empresa_id": empresa_id}, session=session,
            )
            if status != 200:
                return payload, status
            perfil = payload["usuario"]
            if perfil["papel"] != "RH" or perfil["empresa_id"] is None:
                raise FuncionarioError(
                    "Cadastro de funcionários exclusivo do RH da empresa.",
                    403, "ACESSO_NEGADO",
                )
            return operacao(session, uuid.UUID(perfil["empresa_id"]))
        except FuncionarioError as error:
            session.rollback()
            return {"erro": {"codigo": error.codigo, "mensagem": error.mensagem}}, error.status
        except IntegrityError as error:
            session.rollback()
            if getattr(error.orig, "pgcode", None) == "23505":
                return {"erro": {
                    "codigo": "MATRICULA_DUPLICADA",
                    "mensagem": "Esta matrícula já está cadastrada na empresa.",
                }}, 409
            current_app.logger.error("Falha de integridade no cadastro de funcionários.")
            return {"erro": {
                "codigo": "PERSISTENCIA_INDISPONIVEL",
                "mensagem": "Não foi possível salvar o funcionário. Tente novamente.",
            }}, 503
        except SQLAlchemyError:
            session.rollback()
            current_app.logger.error("Falha de banco no cadastro de funcionários.")
            return {"erro": {
                "codigo": "PERSISTENCIA_INDISPONIVEL",
                "mensagem": "Banco indisponível. Tente novamente.",
            }}, 503

    @staticmethod
    def _json(funcionario):
        return {
            "id": str(funcionario.id), "nome": funcionario.nome,
            "matricula": funcionario.matricula, "cargo": funcionario.cargo,
            "empresa_id": str(funcionario.empresa_id), "ativo": funcionario.ativo,
            **({"usuario_id": str(funcionario.usuario_id)} if funcionario.usuario_id else {}),
        }

    @staticmethod
    def _validar(dados, criacao):
        campos = {"nome", "matricula", "cargo", "ativo"}
        if not isinstance(dados, dict) or not dados or dados.keys() - campos:
            raise FuncionarioError("Informe os campos válidos do funcionário.")
        if criacao and not {"nome", "matricula"} <= dados.keys():
            raise FuncionarioError("Informe nome e matrícula do funcionário.")
        normalizado = dict(dados)
        for campo, limite in (("nome", 150), ("matricula", 50)):
            if campo in dados:
                valor = dados[campo]
                if not isinstance(valor, str) or not 1 <= len(valor.strip()) <= limite:
                    raise FuncionarioError(f"{campo} deve conter entre 1 e {limite} caracteres.")
                normalizado[campo] = valor.strip()
        if "cargo" in dados:
            cargo = dados["cargo"]
            if cargo is not None and (not isinstance(cargo, str) or len(cargo.strip()) > 120):
                raise FuncionarioError("Cargo deve conter até 120 caracteres ou ser nulo.")
            normalizado["cargo"] = (cargo.strip() or None) if cargo is not None else None
        if "ativo" in dados and type(dados["ativo"]) is not bool:
            raise FuncionarioError("ativo deve ser booleano.")
        return normalizado

    @staticmethod
    def _validar_matricula(session, empresa_id, matricula, alvo_id=None):
        consulta = select(Funcionarios.id).where(
            Funcionarios.empresa_id == empresa_id, Funcionarios.matricula == matricula,
        )
        if alvo_id is not None:
            consulta = consulta.where(Funcionarios.id != alvo_id)
        if session.scalar(consulta) is not None:
            raise FuncionarioError(
                "Esta matrícula já está cadastrada na empresa.", 409, "MATRICULA_DUPLICADA",
            )

    @staticmethod
    def listar(usuario_id, empresa_id, session=None):
        def operacao(session, empresa):
            rows = session.scalars(select(Funcionarios).where(
                Funcionarios.empresa_id == empresa,
            ).order_by(Funcionarios.nome, Funcionarios.id)).all()
            return {"funcionarios": [FuncionarioService._json(row) for row in rows]}, 200
        return FuncionarioService._executar(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def buscar(usuario_id, empresa_id, q=None, matricula=None, session=None):
        """Busca limitada para seletores; inclui inativos para relatórios históricos."""
        def operacao(session, empresa):
            for valor in (q, matricula):
                if valor is not None and (not isinstance(valor, str) or len(valor.strip()) > 150):
                    raise FuncionarioError("A busca deve conter até 150 caracteres.")
            busca = (q or "").strip()
            matricula_busca = (matricula or "").strip()
            if busca and matricula_busca:
                raise FuncionarioError("Informe q ou matricula, não os dois juntos.")

            consulta = select(Funcionarios).where(Funcionarios.empresa_id == empresa)
            texto = busca or matricula_busca
            if texto:
                # Escapa curingas e usa parâmetros vinculados, sem SQL interpolado.
                padrao = "%" + texto.replace("/", "//").replace("%", "/%").replace("_", "/_") + "%"
                filtro = Funcionarios.matricula.ilike(padrao, escape="/")
                if busca:
                    filtro = or_(Funcionarios.nome.ilike(padrao, escape="/"), filtro)
                consulta = consulta.where(filtro)

            # Sem texto, retorna a lista inicial. O tenant e o limite são sempre aplicados.
            rows = session.scalars(consulta.order_by(
                Funcionarios.nome, Funcionarios.id,
            ).limit(20)).all()
            return {"funcionarios": [FuncionarioService._json(row) for row in rows]}, 200

        # Revalidates the logged-in RH and tenant through the existing auth service.
        return FuncionarioService._executar(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def criar(usuario_id, empresa_id, dados, session=None):
        def operacao(session, empresa):
            values = FuncionarioService._validar(dados, True)
            FuncionarioService._validar_matricula(session, empresa, values["matricula"])
            funcionario = Funcionarios(empresa_id=empresa, **values)
            session.add(funcionario)
            session.flush()
            result = FuncionarioService._json(funcionario)
            session.commit()
            return {"funcionario": result}, 201
        return FuncionarioService._executar(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def atualizar(usuario_id, empresa_id, alvo_id, dados, session=None):
        def operacao(session, empresa):
            values = FuncionarioService._validar(dados, False)
            try:
                funcionario_id = uuid.UUID(str(alvo_id))
            except (ValueError, TypeError, AttributeError):
                raise FuncionarioError(
                    "Funcionário não encontrado nesta empresa.", 404, "FUNCIONARIO_NAO_ENCONTRADO",
                ) from None
            funcionario = session.scalar(select(Funcionarios).where(
                Funcionarios.id == funcionario_id, Funcionarios.empresa_id == empresa,
            ).with_for_update())
            if funcionario is None:
                raise FuncionarioError(
                    "Funcionário não encontrado nesta empresa.", 404, "FUNCIONARIO_NAO_ENCONTRADO",
                )
            if "matricula" in values:
                FuncionarioService._validar_matricula(session, empresa, values["matricula"], funcionario.id)
            for campo, valor in values.items():
                setattr(funcionario, campo, valor)
            session.flush()
            result = FuncionarioService._json(funcionario)
            session.commit()
            return {"funcionario": result}, 200
        return FuncionarioService._executar(usuario_id, empresa_id, operacao, session)
