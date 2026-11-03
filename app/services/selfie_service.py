"""Selfie privada e imutável: upload separado, vinculado à marcação pelo UUID."""
import hashlib
import io
import uuid
import warnings

from PIL import Image, UnidentifiedImageError
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import SQLAlchemyError
from flask import current_app

from app import db
from app.models import RegistrosPonto, SelfiesPonto
from .ponto_payload import PontoError, parse_uuid
from .registro_ponto_service import contexto_funcionario, dispositivo_autorizado
from .rh_access import GestaoError, executar_empresa
from .w06_validation import identificador


class SelfieService:
    MAX_BYTES = 2 * 1024 * 1024
    MAX_PIXELS = 16_000_000

    @staticmethod
    def baixar_admin(usuario_id, empresa_id, registro_id, session=None):
        def operacao(session, empresa):
            alvo = identificador(registro_id, "registro_id")
            foto = session.execute(select(SelfiesPonto.conteudo, SelfiesPonto.content_type).join(
                RegistrosPonto,
                (SelfiesPonto.empresa_id == RegistrosPonto.empresa_id)
                & (SelfiesPonto.usuario_id == RegistrosPonto.usuario_id)
                & (SelfiesPonto.evento_cliente_id == RegistrosPonto.evento_cliente_id),
            ).where(RegistrosPonto.id == alvo, RegistrosPonto.empresa_id == empresa,
                SelfiesPonto.empresa_id == empresa)).first()
            if foto is None:
                raise GestaoError("Foto não encontrada nesta empresa.", 404, "SELFIE_NAO_ENCONTRADA")
            return {"conteudo": foto.conteudo, "content_type": foto.content_type}, 200
        return executar_empresa(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def enviar(empresa_id, usuario_id, dispositivo_token, evento_id, arquivo, session=None):
        session = session if session is not None else db.session
        try:
            empresa_id, usuario_id = contexto_funcionario(session, empresa_id, usuario_id)
            evento_id = parse_uuid(evento_id, "evento_cliente_id")
            point = session.scalar(select(RegistrosPonto).where(
                RegistrosPonto.empresa_id == empresa_id, RegistrosPonto.usuario_id == usuario_id,
                RegistrosPonto.evento_cliente_id == evento_id))
            if point is None:
                raise PontoError("MARCACAO_NAO_ENCONTRADA", "Envie a marcação antes da selfie.", 404)
            if not dispositivo_autorizado(session, empresa_id, usuario_id, point.dispositivo_cliente_id, dispositivo_token, point.setor_id):
                raise PontoError("APARELHO_NAO_AUTORIZADO", "Aparelho não autorizado para esta marcação.", 403)
            if arquivo is None:
                raise PontoError("SELFIE_AUSENTE", "Envie o campo multipart selfie.")
            conteudo = arquivo.stream.read(SelfieService.MAX_BYTES + 1)
            if not conteudo or len(conteudo) > SelfieService.MAX_BYTES:
                raise PontoError("SELFIE_TAMANHO", "Selfie exige entre 1 byte e 2 MiB.", 413)
            content_type = SelfieService._verificar_imagem(conteudo)
            digest = hashlib.sha256(conteudo).hexdigest()
            selfie_id = session.scalar(insert(SelfiesPonto).values(
                id=uuid.uuid4(), empresa_id=empresa_id, usuario_id=usuario_id,
                evento_cliente_id=evento_id, conteudo=conteudo, content_type=content_type, sha256=digest,
            ).on_conflict_do_nothing(constraint="uq_selfies_evento_empresa").returning(SelfiesPonto.id))
            selfie = session.scalar(select(SelfiesPonto).where(
                SelfiesPonto.empresa_id == empresa_id, SelfiesPonto.usuario_id == usuario_id,
                SelfiesPonto.evento_cliente_id == evento_id))
            if selfie.sha256 != digest:
                raise PontoError("SELFIE_CONFLITANTE", "Este UUID já possui outra selfie.", 409)
            resultado = {"evento_cliente_id": str(evento_id), "selfie_id": str(selfie.id),
                         "sha256": digest, "content_type": selfie.content_type, "duplicada": selfie_id is None}
            session.commit()
            return resultado, 200 if selfie_id is None else 201
        except PontoError as error:
            session.rollback()
            return error.response()
        except SQLAlchemyError:
            session.rollback()
            current_app.logger.error("Falha de banco ao persistir selfie W09.")
            return {"erro": {"codigo": "PERSISTENCIA_INDISPONIVEL", "mensagem": "Selfie não confirmada; tente novamente."}}, 503

    @staticmethod
    def _verificar_imagem(conteudo):
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(conteudo)) as imagem:
                    formato = imagem.format
                    if formato not in {"JPEG", "PNG"} or imagem.width * imagem.height > SelfieService.MAX_PIXELS or getattr(imagem, "n_frames", 1) != 1:
                        raise PontoError("SELFIE_INVALIDA", "Envie JPEG/PNG estático de até 16 megapixels.")
                    imagem.verify()
                with Image.open(io.BytesIO(conteudo)) as imagem:
                    imagem.load()
            return {"JPEG": "image/jpeg", "PNG": "image/png"}[formato]
        except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
            raise PontoError("SELFIE_INVALIDA", "O arquivo não é uma imagem JPEG/PNG válida.") from None
