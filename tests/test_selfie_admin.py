"""Leitura privada de evidência, sem carregar fotos no espelho mensal."""
import hashlib
import io
import uuid

import pytest
from PIL import Image
from sqlalchemy import event

from app.models import PapelUsuario, SelfiesPonto
from app.services.espelho_service import EspelhoService
from test_ajustes_rh import contexto, headers, snapshot


def caminho(registro_id):
    return f"/api/v1/admin/pontos/{registro_id}/selfie"


@pytest.fixture
def foto(contexto, session):
    buffer = io.BytesIO()
    Image.new("RGB", (2, 2), "teal").save(buffer, format="PNG")
    conteudo = buffer.getvalue()
    for original in (contexto.original, contexto.other_point):
        session.add(SelfiesPonto(empresa_id=original.empresa_id, usuario_id=original.usuario_id,
            evento_cliente_id=original.evento_cliente_id, conteudo=conteudo,
            content_type="image/png", sha256=hashlib.sha256(conteudo).hexdigest()))
    session.commit()
    return conteudo


def test_foto_exige_jwt(app):
    assert app.test_client().get(caminho(uuid.uuid4())).status_code == 401


@pytest.mark.postgres
@pytest.mark.parametrize("papel", [PapelUsuario.RH, PapelUsuario.GESTOR])
def test_foto_privada_somente_da_empresa_e_sem_cache_publico(contexto, session, foto, papel):
    ctx = contexto
    ctx.rh.papel = papel
    session.commit()
    antes = snapshot(session)
    resposta = ctx.client.get(caminho(ctx.original.id), headers=headers(ctx.rh))
    assert resposta.status_code == 200
    assert resposta.data == foto
    assert resposta.mimetype == "image/png"
    assert resposta.headers["Cache-Control"] == "private, no-store"
    assert resposta.headers["X-Content-Type-Options"] == "nosniff"
    for registro_id in [ctx.other_point.id, uuid.uuid4()]:
        assert ctx.client.get(caminho(registro_id), headers=headers(ctx.rh)).status_code == 404
    assert snapshot(session) == antes


@pytest.mark.postgres
@pytest.mark.parametrize("papel", [PapelUsuario.FUNCIONARIO, PapelUsuario.USUARIO_SETOR])
def test_foto_nao_disponivel_a_funcionario_mesmo_com_claim_rh(contexto, session, foto, papel):
    ctx = contexto
    ctx.rh.papel = papel
    session.commit()
    assert ctx.client.get(caminho(ctx.original.id), headers=headers(ctx.rh)).status_code == 403


@pytest.mark.postgres
def test_espelho_publica_metadados_sem_buscar_conteudo_da_foto(contexto, session, foto):
    ctx = contexto
    consultas = []
    def capturar(conn, cursor, statement, parameters, context, many):
        if statement.lstrip().upper().startswith("SELECT"):
            consultas.append(statement)
    conexao = session.connection()
    event.listen(conexao, "before_cursor_execute", capturar)
    try:
        payload, status = EspelhoService.gerar_mensal(ctx.rh.id, ctx.own.company.id,
            ctx.own.user.id, 2020, 1, session=session)
    finally:
        event.remove(conexao, "before_cursor_execute", capturar)
    assert status == 200, payload
    ponto = next(p for d in payload["espelho"]["dias"] for p in d["marcacoes"]
        if p["id"] == str(ctx.original.id))
    assert ponto["foto_url"] == caminho(ctx.original.id)
    assert ponto["foto_recebida_em"] is not None
    assert ponto["geofence"]["raio_metros"] == 100
    assert all("selfies_ponto.conteudo" not in q for q in consultas)


@pytest.mark.postgres
def test_sem_selfie_retorna_url_nula_e_404_na_leitura(contexto, session):
    ctx = contexto
    payload, status = EspelhoService.gerar_mensal(ctx.rh.id, ctx.own.company.id,
        ctx.own.user.id, 2020, 1, session=session)
    assert status == 200
    ponto = next(p for d in payload["espelho"]["dias"] for p in d["marcacoes"])
    assert ponto["foto_url"] is ponto["foto_recebida_em"] is None
    assert ctx.client.get(caminho(ctx.original.id), headers=headers(ctx.rh)).status_code == 404
