"""W02: setores e políticas de ponto isolados pela empresa do RH."""

import uuid
from decimal import Decimal, InvalidOperation

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.models import AcaoForaPerimetro, Alocacoes, Setores
from .rh_access import GestaoError, executar_rh


class SetorService:
    CAMPOS = {
        "nome", "endereco", "latitude", "longitude", "raio_metros",
        "exige_selfie", "acao_fora_perimetro", "ignorar_localizacao",
        "limite_desvio_relogio_segundos", "ativo",
    }

    @staticmethod
    def _json(row):
        return {
            "id": str(row.id), "empresa_id": str(row.empresa_id),
            "nome": row.nome, "endereco": row.endereco, "ativo": row.ativo,
            "latitude": float(row.latitude_centro),
            "longitude": float(row.longitude_centro),
            "raio_metros": float(row.raio_metros),
            "exige_selfie": row.exige_selfie,
            "acao_fora_perimetro": row.acao_fora_perimetro.value,
            "ignorar_localizacao": row.ignorar_localizacao,
            "limite_desvio_relogio_segundos": row.limite_desvio_relogio_segundos,
        }

    @staticmethod
    def _decimal(value, campo, minimo, maximo, casas):
        if isinstance(value, bool) or not isinstance(value, (int, float, str, Decimal)):
            raise GestaoError(f"{campo} deve ser um número válido.")
        try:
            number = Decimal(str(value))
            if campo == "raio_metros" and number.is_finite() and number <= 0:
                raise GestaoError("O raio em metros deve ser maior que zero.", 400, "RAIO_INVALIDO")
            if not number.is_finite() or not minimo <= number <= maximo:
                raise GestaoError(f"{campo} deve estar entre {minimo} e {maximo}.")
            number = number.quantize(Decimal(1).scaleb(-casas))
        except InvalidOperation:
            raise GestaoError(f"{campo} deve ser um número válido.") from None
        if campo == "raio_metros" and number <= 0:
            raise GestaoError("O raio em metros deve ser maior que zero.", 400, "RAIO_INVALIDO")
        return number

    @staticmethod
    def _dados(dados, criacao=False):
        if not isinstance(dados, dict) or not dados or dados.keys() - SetorService.CAMPOS:
            raise GestaoError("Envie os dados do setor, sem campos desconhecidos.")
        if criacao and not {"nome", "latitude", "longitude", "raio_metros"} <= dados.keys():
            raise GestaoError("Informe nome, latitude, longitude e raio do setor.")
        valores = {}
        if "nome" in dados:
            nome = dados["nome"]
            if not isinstance(nome, str) or not 1 <= len(nome.strip()) <= 120:
                raise GestaoError("O nome deve conter entre 1 e 120 caracteres.")
            valores["nome"] = nome.strip()
        if "endereco" in dados:
            endereco = dados["endereco"]
            if endereco is not None and (not isinstance(endereco, str) or len(endereco.strip()) > 255):
                raise GestaoError("O endereço deve ter até 255 caracteres.")
            valores["endereco"] = (endereco.strip() or None) if endereco is not None else None
        for campo, coluna, minimo, maximo, casas in (
            ("latitude", "latitude_centro", Decimal(-90), Decimal(90), 7),
            ("longitude", "longitude_centro", Decimal(-180), Decimal(180), 7),
            ("raio_metros", "raio_metros", Decimal(0), Decimal("9999999999.99"), 2),
        ):
            if campo in dados:
                valores[coluna] = SetorService._decimal(dados[campo], campo, minimo, maximo, casas)
        for campo in ("exige_selfie", "ignorar_localizacao", "ativo"):
            if campo in dados:
                if type(dados[campo]) is not bool:
                    raise GestaoError(f"{campo} deve ser booleano.")
                valores[campo] = dados[campo]
        if "acao_fora_perimetro" in dados:
            try:
                valores["acao_fora_perimetro"] = AcaoForaPerimetro(dados["acao_fora_perimetro"])
            except (ValueError, TypeError):
                raise GestaoError("A ação fora do perímetro deve ser BLOQUEAR ou PENDENTE.") from None
        if "limite_desvio_relogio_segundos" in dados:
            limite = dados["limite_desvio_relogio_segundos"]
            if type(limite) is not int or not 0 <= limite <= 2147483647:
                raise GestaoError("O limite de desvio deve ser um inteiro não negativo.")
            valores["limite_desvio_relogio_segundos"] = limite
        return valores

    @staticmethod
    def _encontrar(session, empresa, setor_id):
        try:
            target = uuid.UUID(str(setor_id))
        except (ValueError, TypeError, AttributeError):
            raise GestaoError("Setor não encontrado nesta empresa.", 404, "SETOR_NAO_ENCONTRADO") from None
        row = session.scalar(select(Setores).where(
            Setores.id == target, Setores.empresa_id == empresa,
        ).with_for_update())
        if row is None:
            raise GestaoError("Setor não encontrado nesta empresa.", 404, "SETOR_NAO_ENCONTRADO")
        return row

    @staticmethod
    def _nome_disponivel(session, empresa, nome, setor_id=None):
        query = select(Setores.id).where(Setores.empresa_id == empresa, Setores.nome == nome)
        if setor_id is not None:
            query = query.where(Setores.id != setor_id)
        if session.scalar(query.limit(1)) is not None:
            raise GestaoError("Já existe um setor com esse nome nesta empresa.", 409, "NOME_DUPLICADO")

    @staticmethod
    def _persistir(session, commit=False):
        try:
            if commit:
                session.commit()
            else:
                session.flush()
        except IntegrityError as error:
            # As FKs também protegem contra vínculos criados concorrentemente.
            codigo = getattr(error.orig, "pgcode", None)
            if codigo in {"23001", "23503"}:
                raise GestaoError(
                    "Não é possível remover um setor com alocações ou outros vínculos. O histórico deve ser preservado.",
                    409, "SETOR_VINCULADO",
                ) from None
            if codigo == "23505" and getattr(getattr(error.orig, "diag", None), "constraint_name", None) == "uq_setores_empresa_nome":
                raise GestaoError("Já existe um setor com esse nome nesta empresa.", 409, "NOME_DUPLICADO") from None
            raise

    @staticmethod
    def listar(usuario_id, empresa_id, session=None):
        def operacao(session, empresa):
            rows = session.scalars(select(Setores).where(
                Setores.empresa_id == empresa,
            ).order_by(Setores.nome, Setores.id)).all()
            return {"setores": [SetorService._json(row) for row in rows]}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def criar_setor(usuario_id, empresa_id, dados, session=None):
        def operacao(session, empresa):
            valores = SetorService._dados(dados, criacao=True)
            SetorService._nome_disponivel(session, empresa, valores["nome"])
            row = Setores(empresa_id=empresa, **valores)
            session.add(row)
            SetorService._persistir(session)
            dto = SetorService._json(row)
            SetorService._persistir(session, commit=True)
            return {"setor": dto}, 201
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def atualizar_setor(usuario_id, empresa_id, setor_id, dados, session=None):
        def operacao(session, empresa):
            row = SetorService._encontrar(session, empresa, setor_id)
            valores = SetorService._dados(dados)
            if "nome" in valores:
                SetorService._nome_disponivel(session, empresa, valores["nome"], row.id)
            for campo, valor in valores.items():
                setattr(row, campo, valor)
            SetorService._persistir(session)
            dto = SetorService._json(row)
            SetorService._persistir(session, commit=True)
            return {"setor": dto}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def deletar_setor(usuario_id, empresa_id, setor_id, session=None):
        def operacao(session, empresa):
            row = SetorService._encontrar(session, empresa, setor_id)
            # Inclui alocações encerradas: remover o setor quebraria o histórico.
            vinculo = session.scalar(select(Alocacoes.id).where(
                Alocacoes.empresa_id == empresa, Alocacoes.setor_id == row.id,
            ).limit(1))
            if vinculo is not None:
                raise GestaoError(
                    "Não é possível remover um setor com funcionários alocados, mesmo em alocações encerradas.",
                    409, "SETOR_ALOCADO",
                )
            setor_id_str = str(row.id)
            session.delete(row)
            SetorService._persistir(session, commit=True)
            return {"id": setor_id_str, "removido": True}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)
