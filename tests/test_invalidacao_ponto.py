"""Invalidação auditável, isolamento e exclusão da apuração sem mutar originais."""
import uuid
from datetime import timedelta

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import event, select
from sqlalchemy.exc import IntegrityError

from app.models import JustificativasAjustes, PapelUsuario, RegistrosPonto, Usuarios
from app.services.espelho_service import EspelhoService
from test_ajustes_rh import contexto, headers, snapshot


def path(registro_id):
    return f"/api/v1/admin/pontos/{registro_id}/invalidar"


@pytest.mark.parametrize("modo", ["ausente", "vencido", "invalido"])
def test_jwt_obrigatorio(app, modo):
    cabecalhos = {}
    if modo != "ausente":
        with app.app_context():
            token = create_access_token(identity=str(uuid.uuid4()), expires_delta=timedelta(seconds=-1))
        cabecalhos = {"Authorization": "Bearer " + (token if modo == "vencido" else "invalido")}
    assert app.test_client().post(path(uuid.uuid4()), headers=cabecalhos,
        json={"motivo_texto": "Foto incorreta"}).status_code == 401


@pytest.mark.postgres
@pytest.mark.parametrize("papel", [PapelUsuario.RH, PapelUsuario.GESTOR])
def test_contra_registro_aprovado_sem_escrever_em_pontos(contexto, session, papel):
    ctx = contexto
    ctx.rh.papel = papel
    session.commit()
    antes = snapshot(session)
    escritas = []
    def capturar(conn, cursor, statement, parameters, context, many):
        if statement.lstrip().upper().startswith(("INSERT", "UPDATE", "DELETE")):
            escritas.append(statement)
    conexao = session.connection()
    event.listen(conexao, "before_cursor_execute", capturar)
    try:
        resposta = ctx.client.post(path(ctx.original.id), headers=headers(ctx.rh),
            json={"motivo_texto": "  Foto não corresponde ao funcionário  "})
    finally:
        event.remove(conexao, "before_cursor_execute", capturar)
    assert resposta.status_code == 201, resposta.json
    dto = resposta.json["ajuste"]
    assert dto["tipo_ocorrencia"] == "INVALIDACAO_GESTOR"
    assert dto["status_analise"] == "APROVADO"
    assert dto["registro_original_id"] == str(ctx.original.id)
    assert dto["solicitado_por_id"] == dto["gestor_aprovador_id"] == str(ctx.rh.id)
    assert dto["motivo_texto"] == "Foto não corresponde ao funcionário"
    assert escritas and all("INSERT INTO justificativas_ajustes" in s for s in escritas)
    session.expire_all()
    assert snapshot(session) == antes


@pytest.mark.postgres
def test_reenvio_e_correcao_posterior_nao_duplicam_ou_restauram(contexto, session):
    ctx = contexto
    alvo = path(ctx.original.id)
    dados = {"motivo_texto": "Foto incorreta"}
    assert ctx.client.post(alvo, headers=headers(ctx.rh), json=dados).status_code == 201
    repetido = ctx.client.post(alvo, headers=headers(ctx.rh), json=dados)
    assert repetido.status_code == 409
    assert repetido.json["erro"]["codigo"] == "PONTO_JA_INVALIDADO"
    correcao = ctx.client.post("/api/v1/admin/ponto-correcao", headers=headers(ctx.rh),
        json={"registro_original_id": str(ctx.original.id), "motivo_texto": "Novo horário",
              "nova_data_hora": "2020-01-02T08:15:00-03:00"})
    assert correcao.status_code == 409
    assert len(session.scalars(select(JustificativasAjustes)).all()) == 1


@pytest.mark.postgres
def test_banco_tambem_impede_duplicacao_de_invalidacao_aprovada(contexto, session):
    ctx = contexto
    assert ctx.client.post(path(ctx.original.id), headers=headers(ctx.rh),
        json={"motivo_texto": "Foto incorreta"}).status_code == 201
    existente = session.scalar(select(JustificativasAjustes))
    with pytest.raises(IntegrityError):
        with session.begin_nested():
            session.add(JustificativasAjustes(
                empresa_id=existente.empresa_id, usuario_id=existente.usuario_id,
                registro_ponto_id=existente.registro_ponto_id,
                solicitado_por_id=existente.solicitado_por_id, justificativa="Outra tentativa",
                tipo_ocorrencia=existente.tipo_ocorrencia, tipo_proposto=existente.tipo_proposto,
                ocorrido_em_proposto=existente.ocorrido_em_proposto, status=existente.status,
                decidido_por_id=existente.decidido_por_id, decidido_em=existente.decidido_em,
                sequencia_decisao=existente.sequencia_decisao,
            ))
            session.flush()
    assert len(session.scalars(select(JustificativasAjustes)).all()) == 1


@pytest.mark.postgres
@pytest.mark.parametrize("dados", [None, {}, [], {"motivo_texto": " "}, {"motivo_texto": 1},
    {"motivo_texto": "a" * 5001}, {"motivo_texto": "Teste", "gestor_aprovador_id": "forjado"}])
def test_motivo_obrigatorio_e_autor_nao_pode_ser_injetado(contexto, session, dados):
    ctx = contexto
    assert ctx.client.post(path(ctx.original.id), headers=headers(ctx.rh), json=dados).status_code == 400
    assert session.scalars(select(JustificativasAjustes)).all() == []


@pytest.mark.postgres
@pytest.mark.parametrize("papel", [PapelUsuario.FUNCIONARIO, PapelUsuario.USUARIO_SETOR, PapelUsuario.SUPERADMIN])
def test_papel_do_banco_prevalece_sobre_claim_forjada(contexto, session, papel):
    ctx = contexto
    autor = Usuarios(nome="Sem permissão", email="no-invalidation@example.com", senha_hash="hash",
        papel=papel, empresa_id=None if papel == PapelUsuario.SUPERADMIN else ctx.own.company.id)
    session.add(autor)
    session.commit()
    assert ctx.client.post(path(ctx.original.id), headers=headers(autor, role="RH"),
        json={"motivo_texto": "Teste"}).status_code == 403
    assert session.scalars(select(JustificativasAjustes)).all() == []


@pytest.mark.postgres
def test_nao_revela_ponto_de_outra_empresa(contexto, session):
    ctx = contexto
    for registro_id in [ctx.other_point.id, uuid.uuid4()]:
        resposta = ctx.client.post(path(registro_id), headers=headers(ctx.rh), json={"motivo_texto": "Teste"})
        assert resposta.status_code == 404
    assert session.scalars(select(JustificativasAjustes)).all() == []


@pytest.mark.postgres
@pytest.mark.parametrize("caso", ["conta_inativa", "empresa_inativa", "empresa_forjada"])
def test_sessao_e_empresa_revalidadas(contexto, session, caso):
    ctx = contexto
    cabecalhos = headers(ctx.rh, empresa=ctx.foreign.company.id if caso == "empresa_forjada" else None)
    if caso == "conta_inativa":
        ctx.rh.ativo = False
    if caso == "empresa_inativa":
        ctx.own.company.ativo = False
    session.commit()
    assert ctx.client.post(path(ctx.original.id), headers=cabecalhos,
        json={"motivo_texto": "Teste"}).status_code == 401


@pytest.mark.postgres
def test_espelho_mantem_original_e_exclui_invalidacao_das_horas(contexto, session, point_values):
    ctx = contexto
    ctx.rh.papel = PapelUsuario.GESTOR
    saida = RegistrosPonto(**{**point_values, "tipo": "Saida", "evento_cliente_id": uuid.uuid4(),
        "ocorrido_em": ctx.original.ocorrido_em + timedelta(hours=8)})
    session.add(saida)
    session.commit()
    def consultar():
        dto, status = EspelhoService.gerar_mensal(ctx.rh.id, ctx.own.company.id,
            ctx.own.user.id, 2020, 1, session=session)
        assert status == 200, dto
        return next(d for d in dto["espelho"]["dias"] if d["data"] == "2020-01-02")
    assert consultar()["minutos_trabalhados"] == 480
    assert ctx.client.post(path(ctx.original.id), headers=headers(ctx.rh),
        json={"motivo_texto": "Foto incorreta"}).status_code == 201
    dia = consultar()
    assert dia["minutos_trabalhados"] == 0
    original = next(p for p in dia["marcacoes"] if p["id"] == str(ctx.original.id))
    assert original["situacao"] == "Aceita" and original["invalidado"] is True
    assert original["invalidacao"]["motivo_texto"] == "Foto incorreta"
    assert len(dia["marcacoes"]) == 2
    assert "SEQUENCIA_INCOMPLETA_OU_INVALIDA" in dia["pendencias"]
    # Gestor também alcança o espelho HTTP e a busca limitada do funcionário.
    assert ctx.client.get("/api/web/relatorios/espelho", headers=headers(ctx.rh), query_string={
        "funcionario_id": str(ctx.own.employee.id), "ano": 2020, "mes": 1}).status_code == 200
    assert ctx.client.get("/api/web/funcionarios/busca", headers=headers(ctx.rh)).status_code == 200
    assert ctx.client.post("/api/web/funcionarios", headers=headers(ctx.rh),
        json={"nome": "Não pode cadastrar", "matricula": "999"}).status_code == 403
