"""Atestados privados, persistidos atomicamente com o afastamento."""
from urllib.parse import urlsplit
from sqlalchemy import delete, select
from werkzeug.utils import secure_filename

from app.models import AnexosAfastamento, Afastamentos
from .rh_access import GestaoError, executar_empresa
from .w06_validation import identificador
from .selfie_service import SelfieService
from .ponto_payload import PontoError


class AnexoAfastamentoService:
    MAX_BYTES = 10 * 1024 * 1024

    @staticmethod
    def anexar(session, empresa, row, arquivo, base_url):
        content = arquivo.stream.read(AnexoAfastamentoService.MAX_BYTES + 1)
        if not content or len(content) > AnexoAfastamentoService.MAX_BYTES:
            raise GestaoError("O anexo deve ter entre 1 byte e 10 MB.", 413, "ANEXO_TAMANHO")
        if content.startswith(b"%PDF-") and b"%%EOF" in content[-1024:]:
            mime, extensao = "application/pdf", "pdf"
        else:
            try:
                mime = SelfieService._verificar_imagem(content)
            except PontoError:
                raise GestaoError("Envie um arquivo PDF, PNG ou JPEG válido.", 400, "ANEXO_INVALIDO") from None
            extensao = "png" if mime == "image/png" else "jpg"
        if not base_url or urlsplit(base_url).scheme not in {"http", "https"}:
            raise GestaoError("Endereço de download indisponível.", 503, "ANEXO_INDISPONIVEL")
        nome = secure_filename(arquivo.filename or "")[:240] or f"atestado.{extensao}"
        # Extensão é derivada do conteúdo, nunca somente do nome enviado.
        nome = nome.rsplit(".", 1)[0] + "." + extensao
        anexo = session.scalar(select(AnexosAfastamento).where(
            AnexosAfastamento.empresa_id == empresa, AnexosAfastamento.afastamento_id == row.id))
        if anexo is None:
            anexo = AnexosAfastamento(empresa_id=empresa, afastamento_id=row.id)
            session.add(anexo)
        anexo.nome, anexo.content_type, anexo.conteudo = nome, mime, content
        row.anexo_url = base_url.rstrip("/") + f"/api/web/afastamentos/{row.id}/anexo"

    @staticmethod
    def remover_anexo(session, empresa, afastamento_id):
        session.execute(delete(AnexosAfastamento).where(
            AnexosAfastamento.empresa_id == empresa, AnexosAfastamento.afastamento_id == afastamento_id))

    @staticmethod
    def baixar(usuario_id, empresa_id, alvo_id, session=None):
        def operacao(session, empresa):
            aid = identificador(alvo_id, "afastamento_id")
            row = session.scalar(select(AnexosAfastamento).join(Afastamentos,
                (Afastamentos.id == AnexosAfastamento.afastamento_id) &
                (Afastamentos.empresa_id == empresa)).where(
                    AnexosAfastamento.empresa_id == empresa, AnexosAfastamento.afastamento_id == aid))
            if row is None:
                raise GestaoError("Anexo não encontrado nesta empresa.", 404, "ANEXO_NAO_ENCONTRADO")
            return {"conteudo": row.conteudo, "nome": row.nome, "content_type": row.content_type}, 200
        return executar_empresa(usuario_id, empresa_id, operacao, session)
