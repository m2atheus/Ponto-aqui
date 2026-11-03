"""Reanálise do RH preserva todo o histórico e a imutabilidade das batidas."""
import uuid
from datetime import timedelta

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import event, select

from app.models import JustificativasAjustes, PapelUsuario, RegistrosPonto, Usuarios
from app.services.ajuste_ponto_service import AjustePontoService
from test_ajustes_rh import contexto, headers, snapshot
from test_w06_services import contexto as contexto_espelho, dia, espelho
from test_aprovacao_ponto import jornada


def path(registro):
    return f"/api/v1/admin/pontos/{registro}/reaprovar"


def invalidar(ctx, registro=None):
    r = ctx.client.post(f"/api/v1/admin/pontos/{registro or ctx.original.id}/invalidar",
        headers=headers(ctx.rh), json={"motivo_texto": "Revisão inicial da foto"})
    assert r.status_code == 201, r.json
    return r.json["ajuste"]


@pytest.mark.parametrize("modo", ["ausente", "vencido", "invalido"])
def test_reaprovacao_exige_jwt(app, modo):
    h = {}
    if modo != "ausente":
        with app.app_context():
            token = create_access_token(identity=str(uuid.uuid4()), expires_delta=timedelta(seconds=-1))
        h["Authorization"] = "Bearer " + (token if modo == "vencido" else "invalido")
    assert app.test_client().post(path(uuid.uuid4()), headers=h, json={}).status_code == 401


@pytest.mark.postgres
@pytest.mark.parametrize("papel", [PapelUsuario.RH, PapelUsuario.GESTOR])
@pytest.mark.parametrize("situacao", ["Aceita", "Recusada", "PendenteAnalise"])
def test_rh_reaprova_invalidacao_e_permite_novos_ciclos_sem_reescrever(contexto, session, point_values, papel, situacao):
    ctx = contexto
    registro = RegistrosPonto(**{**point_values, "evento_cliente_id": uuid.uuid4(), "situacao": situacao,
        "motivos": [] if situacao == "Aceita" else ["FORA_DO_PERIMETRO"]})
    session.add(registro)
    ctx.rh.papel = papel
    session.commit()
    antes = snapshot(session)
    primeira = invalidar(ctx, registro.id)
    anterior = dict(session.execute(select(JustificativasAjustes.__table__).where(
        JustificativasAjustes.id == uuid.UUID(primeira["id"]))).mappings().one())
    ctx.rh.papel = PapelUsuario.RH
    session.commit()
    writes = []
    def capturar(conn, cursor, statement, parameters, context, many):
        if statement.lstrip().upper().startswith(("INSERT", "UPDATE", "DELETE")):
            writes.append(statement)
    connection = session.connection()
    event.listen(connection, "before_cursor_execute", capturar)
    try:
        resposta = ctx.client.post(path(registro.id), headers=headers(ctx.rh),
            json={"motivo_texto": "  Evidência conferida com o funcionário  ", "invalidacao_id": primeira["id"]})
    finally:
        event.remove(connection, "before_cursor_execute", capturar)
    assert resposta.status_code == 201, resposta.json
    ajuste = resposta.json["ajuste"]
    assert ajuste["tipo_ocorrencia"] == "REAPROVACAO_RH" and ajuste["status_analise"] == "APROVADO"
    assert ajuste["gestor_aprovador_id"] == str(ctx.rh.id) and ajuste["sequencia_decisao"] == 2
    assert ajuste["motivo_texto"] == "Evidência conferida com o funcionário"
    assert writes and all("INSERT INTO justificativas_ajustes" in w for w in writes)
    assert dict(session.execute(select(JustificativasAjustes.__table__).where(
        JustificativasAjustes.id == uuid.UUID(primeira["id"]))).mappings().one()) == anterior
    segunda = invalidar(ctx, registro.id)
    assert segunda["sequencia_decisao"] == 3
    obsoleta = ctx.client.post(path(registro.id), headers=headers(ctx.rh),
        json={"motivo_texto": "Não deve atingir a nova invalidação", "invalidacao_id": primeira["id"]})
    assert obsoleta.status_code == 409 and obsoleta.json["erro"]["codigo"] == "DECISAO_DESATUALIZADA"
    nova = ctx.client.post(path(registro.id), headers=headers(ctx.rh),
        json={"motivo_texto": "Segunda revisão confirmada", "invalidacao_id": segunda["id"]})
    assert nova.status_code == 201 and nova.json["ajuste"]["sequencia_decisao"] == 4
    repetida = ctx.client.post(path(registro.id), headers=headers(ctx.rh),
        json={"motivo_texto": "Reenvio", "invalidacao_id": segunda["id"]})
    assert repetida.status_code == 409
    assert snapshot(session) == antes


@pytest.mark.postgres
@pytest.mark.parametrize("papel", [PapelUsuario.GESTOR, PapelUsuario.FUNCIONARIO, PapelUsuario.USUARIO_SETOR, PapelUsuario.SUPERADMIN])
def test_somente_rh_reaprova_mesmo_com_claim_forjada(contexto, session, papel):
    ctx = contexto
    decisao = invalidar(ctx)
    actor = Usuarios(nome="Sem permissão", email="no-reapproval@example.com", senha_hash="hash", papel=papel,
        empresa_id=None if papel == PapelUsuario.SUPERADMIN else ctx.own.company.id)
    session.add(actor)
    session.commit()
    r = ctx.client.post(path(ctx.original.id), headers=headers(actor, role="RH"),
        json={"motivo_texto": "Teste", "invalidacao_id": decisao["id"]})
    assert r.status_code == 403
    assert len(session.scalars(select(JustificativasAjustes)).all()) == 1


@pytest.mark.postgres
@pytest.mark.parametrize("dados", [None, {}, {"motivo_texto": "Teste"}, {"motivo_texto": " ", "invalidacao_id": str(uuid.uuid4())},
    {"motivo_texto": "Teste", "invalidacao_id": "invalido"},
    {"motivo_texto": "Teste", "invalidacao_id": str(uuid.uuid4()), "gestor_aprovador_id": "forjado"}])
def test_reaprovacao_valida_justificativa_e_referencia(contexto, session, dados):
    ctx = contexto
    invalidar(ctx)
    assert ctx.client.post(path(ctx.original.id), headers=headers(ctx.rh), json=dados).status_code == 400
    assert len(session.scalars(select(JustificativasAjustes)).all()) == 1


@pytest.mark.postgres
def test_reaprovacao_nao_revela_outra_empresa_e_exige_estado_invalidado(contexto, session):
    ctx = contexto
    dados = {"motivo_texto": "Teste", "invalidacao_id": str(uuid.uuid4())}
    for registro in [ctx.other_point.id, uuid.uuid4()]:
        assert ctx.client.post(path(registro), headers=headers(ctx.rh), json=dados).status_code == 404
    assert ctx.client.post(path(ctx.original.id), headers=headers(ctx.rh), json=dados).status_code == 409
    ctx.rh.ativo = False
    session.commit()
    assert ctx.client.post(path(ctx.original.id), headers=headers(ctx.rh), json=dados).status_code == 401


@pytest.mark.postgres
def test_reaprovacao_restaura_horas_extras_e_auditoria_aponta_decisao_vigente(contexto_espelho, session, point_values):
    ctx = contexto_espelho
    rows = jornada(ctx, session, point_values, saida_situacao="Aceita")
    assert session.scalars(select(JustificativasAjustes)).all() == []
    assert dia(espelho(ctx, session), "2026-10-01")["minutos_extras"] == 120
    payload, status = AjustePontoService.invalidar_marcacao(ctx.rh.id, ctx.own.company.id, rows[-1].id,
        {"motivo_texto": "Foto duvidosa"}, session=session)
    assert status == 201
    invalidacao = payload["ajuste"]
    assert dia(espelho(ctx, session), "2026-10-01")["minutos_extras"] == 0
    r, status = AjustePontoService.reaprovar_marcacao(ctx.rh.id, ctx.own.company.id, rows[-1].id,
        {"motivo_texto": "Identidade conferida", "invalidacao_id": invalidacao["id"]}, session=session)
    assert status == 201, r
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["minutos_trabalhados"] == 600 and row["minutos_extras"] == 120
    saida = next(p for p in row["marcacoes"] if p["id"] == str(rows[-1].id))
    assert saida["invalidado"] is False and saida["invalidacao"] is None
    assert saida["reaprovado_rh"] is True and saida["aprovado_gestor"] is True
    assert [d["tipo_ocorrencia"] for d in saida["historico_decisoes"]] == ["INVALIDACAO_GESTOR", "REAPROVACAO_RH"]
    assert row["pendencias"] == []


def preparar_isolado():
    from datetime import datetime, date, timezone
    from app import db
    from app.models import Empresas, Setores, Escalas, Funcionarios, Alocacoes
    empresa = Empresas(razao_social="Reanálise", cnpj="49254098000110")
    db.session.add(empresa)
    db.session.flush()
    rh = Usuarios(empresa_id=empresa.id, nome="RH", email="rh@reanalysis.example", senha_hash="hash", papel=PapelUsuario.RH)
    usuario = Usuarios(empresa_id=empresa.id, nome="Pessoa", email="user@reanalysis.example", senha_hash="hash")
    setor = Setores(empresa_id=empresa.id, nome="Sede", latitude_centro=-8, longitude_centro=-35, raio_metros=100)
    escala = Escalas(empresa_id=empresa.id, nome="Comercial", tipo="Semanal", carga_semanal_minutos=2400, regras={})
    db.session.add_all([rh, usuario, setor, escala])
    db.session.flush()
    funcionario = Funcionarios(empresa_id=empresa.id, usuario_id=usuario.id, nome=usuario.nome, matricula="001")
    db.session.add(funcionario)
    db.session.flush()
    alocacao = Alocacoes(empresa_id=empresa.id, funcionario_id=funcionario.id, usuario_id=usuario.id,
        setor_id=setor.id, escala_id=escala.id, data_inicio=date(2020, 1, 1))
    db.session.add(alocacao)
    db.session.flush()
    ponto = RegistrosPonto(empresa_id=empresa.id, usuario_id=usuario.id, enviado_por_id=usuario.id,
        setor_id=setor.id, alocacao_id=alocacao.id, tipo="Entrada", origem="Mobile", evento_cliente_id=uuid.uuid4(),
        payload_hash="a" * 64, ocorrido_em=datetime(2026, 10, 1, 11, tzinfo=timezone.utc), offset_original_minutos=-180,
        latitude=-8, longitude=-35, precisao_metros=5, latitude_centro_validada=-8, longitude_centro_validada=-35,
        raio_validado_metros=100, distancia_centro_metros=0)
    db.session.add(ponto)
    db.session.commit()
    return empresa.id, rh.id, usuario.id, ponto.id


@pytest.mark.postgres
def test_reaprovar_simultaneamente_nao_duplica_decisao():
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    from app import db
    from test_mobile_w09 import concurrent_app
    with concurrent_app() as application:
        with application.app_context():
            empresa, rh, _, ponto = preparar_isolado()
            resultado, status = AjustePontoService.invalidar_marcacao(rh, empresa, ponto, {"motivo_texto": "Conferência"})
            assert status == 201
            invalidacao = resultado["ajuste"]["id"]
            db.session.remove()
        inicio = Barrier(2)
        def worker(_):
            with application.app_context():
                inicio.wait(timeout=10)
                return AjustePontoService.reaprovar_marcacao(rh, empresa, ponto,
                    {"motivo_texto": "Revisão RH", "invalidacao_id": invalidacao})[1]
        with ThreadPoolExecutor(max_workers=2) as pool:
            assert sorted(pool.map(worker, range(2))) == [201, 409]
        with application.app_context():
            decisoes = db.session.scalars(select(JustificativasAjustes).order_by(JustificativasAjustes.sequencia_decisao)).all()
            assert [d.tipo_ocorrencia for d in decisoes] == ["INVALIDACAO_GESTOR", "REAPROVACAO_RH"]
            assert [d.sequencia_decisao for d in decisoes] == [1, 2]


@pytest.mark.postgres
def test_migration_preserva_decisoes_legadas_e_impede_downgrade_com_reaprovacao():
    from app import db
    from flask_migrate import upgrade, downgrade
    from sqlalchemy import text
    from sqlalchemy.exc import DBAPIError
    from conftest import MIGRATIONS
    from test_mobile_w09 import concurrent_app
    with concurrent_app(revision="0011") as application, application.app_context():
        empresa, rh, usuario, ponto = preparar_isolado()
        aprovacao, invalidacao = uuid.uuid4(), uuid.uuid4()
        for id_, tipo, instante in [(aprovacao, "APROVACAO_GESTOR", "2026-10-01T12:00:00Z"),
                                   (invalidacao, "INVALIDACAO_GESTOR", "2026-10-01T13:00:00Z")]:
            db.session.execute(text("""INSERT INTO justificativas_ajustes
                (id,empresa_id,usuario_id,registro_ponto_id,solicitado_por_id,justificativa,tipo_ocorrencia,
                 tipo_proposto,ocorrido_em_proposto,status,decidido_por_id,decidido_em)
                VALUES (:id,:empresa,:usuario,:ponto,:rh,'Decisao legada',:tipo,
                    'Entrada','2026-10-01T11:00:00Z','Aprovado',:rh,:instante)"""),
                {"id":id_,"empresa":empresa,"usuario":usuario,"ponto":ponto,"rh":rh,"tipo":tipo,"instante":instante})
        antes = [dict(r) for r in db.session.execute(text("SELECT * FROM justificativas_ajustes ORDER BY decidido_em")).mappings()]
        pontos_antes = [dict(r) for r in db.session.execute(select(RegistrosPonto.__table__)).mappings()]
        db.session.commit()
        upgrade(directory=MIGRATIONS, revision="0012")
        depois = [dict(r) for r in db.session.execute(text("SELECT * FROM justificativas_ajustes ORDER BY sequencia_decisao")).mappings()]
        assert [{k:v for k,v in r.items() if k != "sequencia_decisao"} for r in depois] == antes
        assert [r["sequencia_decisao"] for r in depois] == [1, 2]
        assert [dict(r) for r in db.session.execute(select(RegistrosPonto.__table__)).mappings()] == pontos_antes
        resposta, status = AjustePontoService.reaprovar_marcacao(rh, empresa, ponto,
            {"motivo_texto": "Revisão do legado", "invalidacao_id": str(invalidacao)})
        assert status == 201 and resposta["ajuste"]["sequencia_decisao"] == 3
        db.session.commit()
        with pytest.raises(DBAPIError):
            downgrade(directory=MIGRATIONS, revision="0011")
