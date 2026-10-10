"""Ajustes RH: contrato HTTP, autorização e persistência sem alterar batidas."""

import uuid
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import event, select
from sqlalchemy.exc import OperationalError

from app import db
from app.models import Funcionarios, JustificativasAjustes, PapelUsuario, RegistrosPonto, StatusAjuste, Usuarios


PATHS = ["/api/v1/admin/ponto-manual", "/api/v1/admin/ponto-correcao"]


@pytest.mark.parametrize("path", PATHS)
@pytest.mark.parametrize("mode", ["missing", "expired", "invalid"])
def test_routes_require_valid_jwt(app, path, mode):
    headers = {}
    if mode != "missing":
        with app.app_context():
            token = create_access_token(identity=str(uuid.uuid4()), expires_delta=timedelta(seconds=-1))
        headers["Authorization"] = "Bearer " + (token if mode == "expired" else "invalid")
    assert app.test_client().post(path, headers=headers, json={}).status_code == 401


@pytest.mark.parametrize("path", PATHS)
def test_cors_preflight_allows_admin_calls(app, path):
    response = app.test_client().options(path, headers={
        "Origin": "https://painel.example", "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "authorization,content-type",
    })
    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == "https://painel.example"


@pytest.fixture
def contexto(pg_app, session, tenants, point_values, monkeypatch):
    own, foreign = tenants
    rh = Usuarios(empresa_id=own.company.id, nome="RH Ajustes", email="rh-ajustes@example.com",
        senha_hash="hash-teste", papel=PapelUsuario.RH)
    original = RegistrosPonto(**point_values)
    other_point = RegistrosPonto(**{**point_values, "empresa_id": foreign.company.id,
        "usuario_id": foreign.user.id, "enviado_por_id": foreign.user.id,
        "setor_id": foreign.sector.id, "alocacao_id": foreign.assignment.id,
        "evento_cliente_id": uuid.uuid4()})
    session.add_all([rh, original, other_point])
    session.commit()
    monkeypatch.setattr(session, "remove", lambda: None, raising=False)
    monkeypatch.setattr(db, "session", session)
    return SimpleNamespace(client=pg_app.test_client(), own=own, foreign=foreign, rh=rh,
        original=original, other_point=other_point)


def headers(actor, *, empresa=None, role="RH"):
    token = create_access_token(identity=str(actor.id), additional_claims={
        "empresa_id": str(empresa or actor.empresa_id) if (empresa or actor.empresa_id) else None,
        "role": role,
    })
    return {"Authorization": "Bearer " + token}


def manual(ctx, **changes):
    return {"funcionario_id": str(ctx.own.employee.id), "tipo": "ENTRADA",
        "nova_data_hora": "2026-10-10T08:00:00-03:00", "motivo_texto": "  Esqueceu o celular  ", **changes}


def correcao(ctx, **changes):
    return {"registro_original_id": str(ctx.original.id),
        "nova_data_hora": "2020-01-02T08:15:00-03:00", "motivo_texto": "Horário incorreto", **changes}


def snapshot(session):
    return [dict(row) for row in session.execute(
        select(RegistrosPonto.__table__).order_by(RegistrosPonto.id)).mappings()]


@pytest.mark.postgres
def test_manual_insert_is_approved_audited_and_does_not_write_original_table(contexto, session):
    ctx = contexto
    before = snapshot(session)
    writes = []
    def capture(connection, cursor, statement, parameters, context, many):
        if statement.lstrip().upper().startswith(("INSERT", "UPDATE", "DELETE")):
            writes.append(statement)
    connection = session.connection()
    event.listen(connection, "before_cursor_execute", capture)
    try:
        response = ctx.client.post(PATHS[0], headers=headers(ctx.rh), json=manual(ctx))
    finally:
        event.remove(connection, "before_cursor_execute", capture)
    assert response.status_code == 201, response.json
    dto = response.json["ajuste"]
    assert dto["empresa_id"] == str(ctx.own.company.id)
    assert dto["usuario_id"] == str(ctx.own.user.id)
    assert dto["registro_original_id"] is None
    assert dto["nova_data_hora"] == "2026-10-10T11:00:00+00:00"
    assert dto["tipo"] == "ENTRADA" and dto["status_analise"] == "APROVADO"
    assert dto["motivo_texto"] == "Esqueceu o celular"
    assert dto["solicitado_por_id"] == dto["gestor_aprovador_id"] == str(ctx.rh.id)
    stored = session.get(JustificativasAjustes, uuid.UUID(dto["id"]))
    assert stored.status == StatusAjuste.APROVADO and stored.decidido_em is not None
    assert writes and all("INSERT INTO justificativas_ajustes" in statement for statement in writes)
    session.expire_all()
    assert snapshot(session) == before
    assert session.get(JustificativasAjustes, uuid.UUID(dto["id"])).justificativa == "Esqueceu o celular"


@pytest.mark.postgres
@pytest.mark.parametrize("tipo", [None, "SAIDA", "Entrada"])
def test_correction_references_original_but_keeps_every_original_field(contexto, session, tipo):
    ctx = contexto
    before = snapshot(session)
    data = correcao(ctx, **({"tipo": tipo} if tipo else {}))
    response = ctx.client.post(PATHS[1], headers=headers(ctx.rh), json=data)
    assert response.status_code == 201, response.json
    dto = response.json["ajuste"]
    assert dto["registro_original_id"] == str(ctx.original.id)
    assert dto["tipo"] == ("SAIDA" if tipo == "SAIDA" else "ENTRADA")
    assert dto["status_analise"] == "APROVADO"
    stored = session.get(JustificativasAjustes, uuid.UUID(dto["id"]))
    assert stored.ocorrido_em_proposto == datetime(2020, 1, 2, 11, 15, tzinfo=timezone.utc)
    session.expire_all()
    assert snapshot(session) == before


@pytest.mark.postgres
@pytest.mark.parametrize("changes", [
    {"motivo_texto": " "}, {"motivo_texto": None}, {"motivo_texto": 12}, {"motivo_texto": "a" * 5001},
    {"nova_data_hora": "2026-10-10T08:00:00"}, {"nova_data_hora": "2026-02-30T08:00:00Z"},
    {"nova_data_hora": "2026-10-10T08:00:00+00:99"}, {"nova_data_hora": None},
    {"tipo": "INVALIDO"}, {"tipo": []}, {"tipo": None}, {"funcionario_id": "invalid"},
    {"funcionario_id": None}, {"empresa_id": str(uuid.uuid4())},
    {"status_analise": "APROVADO"}, {"gestor_aprovador_id": str(uuid.uuid4())},
    {"registro_original_id": str(uuid.uuid4())},
])
def test_manual_validation_rolls_back_without_saving(contexto, session, changes):
    ctx = contexto
    response = ctx.client.post(PATHS[0], headers=headers(ctx.rh), json=manual(ctx, **changes))
    assert response.status_code == 400, response.json
    assert session.scalars(select(JustificativasAjustes)).all() == []


@pytest.mark.postgres
@pytest.mark.parametrize("data", [None, [], {}, "not-a-dict"])
def test_invalid_body_returns_clean_400(contexto, session, data):
    response = contexto.client.post(PATHS[0], headers=headers(contexto.rh), json=data)
    assert response.status_code == 400
    assert "mensagem" in response.json["erro"]
    assert session.scalars(select(JustificativasAjustes)).all() == []


@pytest.mark.postgres
@pytest.mark.parametrize("case", ["foreign_employee", "foreign_point", "mismatched_employee", "missing_point"])
def test_tenant_and_employee_ownership_are_enforced(contexto, session, case):
    ctx = contexto
    data, path = correcao(ctx), PATHS[1]
    if case == "foreign_employee":
        path, data = PATHS[0], manual(ctx, funcionario_id=str(ctx.foreign.employee.id))
    elif case == "foreign_point":
        data["registro_original_id"] = str(ctx.other_point.id)
    elif case == "missing_point":
        data["registro_original_id"] = str(uuid.uuid4())
    else:
        other = Funcionarios(empresa_id=ctx.own.company.id, nome="Outra pessoa", matricula="002")
        session.add(other)
        session.commit()
        data["funcionario_id"] = str(other.id)
    response = ctx.client.post(path, headers=headers(ctx.rh), json=data)
    assert response.status_code == 404, response.json
    assert session.scalars(select(JustificativasAjustes)).all() == []


@pytest.mark.postgres
@pytest.mark.parametrize("papel", [PapelUsuario.GESTOR, PapelUsuario.FUNCIONARIO, PapelUsuario.USUARIO_SETOR, PapelUsuario.SUPERADMIN])
def test_only_database_rh_role_is_authorized_despite_forged_role_claim(contexto, session, papel):
    ctx = contexto
    actor = Usuarios(nome="Sem acesso", email="no-access@example.com", senha_hash="hash", papel=papel,
        empresa_id=None if papel == PapelUsuario.SUPERADMIN else ctx.own.company.id)
    session.add(actor)
    session.commit()
    for path, data in zip(PATHS, [manual(ctx), correcao(ctx)]):
        response = ctx.client.post(path, headers=headers(actor, role="RH"), json=data)
        assert response.status_code == 403
    assert session.scalars(select(JustificativasAjustes)).all() == []


@pytest.mark.postgres
@pytest.mark.parametrize("case", ["inactive_rh", "inactive_company", "wrong_company_claim"])
def test_account_and_company_revalidated_on_each_call(contexto, session, case):
    ctx = contexto
    auth = headers(ctx.rh, empresa=ctx.foreign.company.id if case == "wrong_company_claim" else None)
    if case == "inactive_rh":
        ctx.rh.ativo = False
    elif case == "inactive_company":
        ctx.own.company.ativo = False
    session.commit()
    assert ctx.client.post(PATHS[0], headers=auth, json=manual(ctx)).status_code == 401
    assert session.scalars(select(JustificativasAjustes)).all() == []


@pytest.mark.postgres
def test_employee_without_account_returns_actionable_error(contexto, session):
    ctx = contexto
    employee = Funcionarios(empresa_id=ctx.own.company.id, nome="Sem conta", matricula="003")
    session.add(employee)
    session.commit()
    response = ctx.client.post(PATHS[0], headers=headers(ctx.rh),
        json=manual(ctx, funcionario_id=str(employee.id)))
    assert response.status_code == 400
    assert response.json["erro"]["codigo"] == "FUNCIONARIO_SEM_USUARIO"


@pytest.mark.postgres
def test_commit_failure_rolls_back_insert_and_returns_503(contexto, session, monkeypatch):
    def fail():
        raise OperationalError("commit", {}, Exception("internal database details"))
    monkeypatch.setattr(session, "commit", fail)
    response = contexto.client.post(PATHS[0], headers=headers(contexto.rh), json=manual(contexto))
    assert response.status_code == 503
    assert "internal database details" not in response.get_data(as_text=True)
    assert session.scalars(select(JustificativasAjustes)).all() == []
