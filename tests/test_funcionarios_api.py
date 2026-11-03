"""W03: contrato consumido pelo painel e preflight do navegador."""

from datetime import timedelta
import uuid

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import func, select
from sqlalchemy.exc import OperationalError

from app import db
from app.models import Alocacoes, Empresas, Funcionarios, PapelUsuario, Usuarios
from app.services.funcionario_service import FuncionarioService


@pytest.fixture
def funcionarios_api(session, pg_app, tenants, monkeypatch):
    rh = Usuarios(
        nome="RH", email="rh@funcionarios.example", senha_hash="hash-teste",
        empresa_id=tenants[0].company.id, papel=PapelUsuario.RH,
    )
    session.add(rh)
    session.commit()
    methods = {name: getattr(FuncionarioService, name) for name in ("listar", "criar", "atualizar", "buscar")}
    monkeypatch.setattr(FuncionarioService, "buscar", staticmethod(
        lambda uid, eid, **kwargs: methods["buscar"](uid, eid, session=session, **kwargs)))
    monkeypatch.setattr(FuncionarioService, "listar", staticmethod(
        lambda uid, eid: methods["listar"](uid, eid, session=session)))
    monkeypatch.setattr(FuncionarioService, "criar", staticmethod(
        lambda uid, eid, data: methods["criar"](uid, eid, data, session=session)))
    monkeypatch.setattr(FuncionarioService, "atualizar", staticmethod(
        lambda uid, eid, target, data: methods["atualizar"](uid, eid, target, data, session=session)))
    token = create_access_token(identity=str(rh.id), additional_claims={
        "empresa_id": str(rh.empresa_id), "role": "RH",
    })
    return pg_app.test_client(), {"Authorization": "Bearer " + token}, rh


def cadastro(**changes):
    return {"nome": "  Ana Silva  ", "matricula": " 002 ", "cargo": None, **changes}


def test_search_requires_jwt(app):
    assert app.test_client().get("/api/web/funcionarios/busca?q=ana").status_code == 401


@pytest.mark.postgres
def test_search_is_case_insensitive_limited_and_tenant_scoped(funcionarios_api, session, tenants):
    client, headers, rh = funcionarios_api
    session.add_all([
        Funcionarios(empresa_id=rh.empresa_id, nome=f"Chico {n:02}", matricula=f"CH-{n:03}")
        for n in range(25)
    ])
    session.add(Funcionarios(empresa_id=tenants[1].company.id, nome="Chico Externo", matricula="CH-999"))
    session.commit()
    response = client.get("/api/web/funcionarios/busca?q=cHiCo&limit=1000", headers=headers)
    assert response.status_code == 200
    rows = response.json["funcionarios"]
    assert len(rows) == 20
    assert {row["empresa_id"] for row in rows} == {str(rh.empresa_id)}
    assert [r["nome"] for r in rows] == [f"Chico {n:02}" for n in range(20)]
    assert client.get("/api/web/funcionarios/busca?q=ch-024", headers=headers).json["funcionarios"][0]["nome"] == "Chico 24"
    assert client.get("/api/web/funcionarios/busca?matricula=CH-024", headers=headers).json["funcionarios"][0]["nome"] == "Chico 24"


@pytest.mark.postgres
def test_search_prioritizes_name_or_registration_prefix_before_limit(funcionarios_api, session, tenants):
    client, headers, rh = funcionarios_api
    session.add_all([
        Funcionarios(empresa_id=rh.empresa_id, nome=f"Ana Lima {n:02}", matricula=f"MID-{n:03}")
        for n in range(25)
    ] + [
        Funcionarios(empresa_id=rh.empresa_id, nome="Maria Silva", matricula="PR-001"),
        Funcionarios(empresa_id=rh.empresa_id, nome="Marcelo Santos", matricula="PR-002"),
        Funcionarios(empresa_id=rh.empresa_id, nome="Carla Souza", matricula="MA-003"),
        Funcionarios(empresa_id=tenants[1].company.id, nome="Marcela Externa", matricula="MA-004"),
    ])
    session.commit()
    response = client.get("/api/web/funcionarios/busca", headers=headers, query_string={"q": "mA"})
    assert response.status_code == 200
    rows = response.json["funcionarios"]
    assert len(rows) == 20
    assert [r["nome"] for r in rows[:3]] == ["Carla Souza", "Marcelo Santos", "Maria Silva"]
    assert [r["nome"] for r in rows[3:]] == [f"Ana Lima {n:02}" for n in range(17)]
    assert {r["empresa_id"] for r in rows} == {str(rh.empresa_id)}


@pytest.mark.postgres
def test_registration_prefix_priority_and_literal_wildcards(funcionarios_api, session):
    client, headers, rh = funcionarios_api
    session.add_all([
        Funcionarios(empresa_id=rh.empresa_id, nome="Ana", matricula="X-123"),
        Funcionarios(empresa_id=rh.empresa_id, nome="Zelia", matricula="123-A"),
        Funcionarios(empresa_id=rh.empresa_id, nome="Ana % Pessoa", matricula="W-001"),
        Funcionarios(empresa_id=rh.empresa_id, nome="% Pessoa", matricula="W-002"),
    ])
    session.commit()
    response = client.get("/api/web/funcionarios/busca", headers=headers, query_string={"matricula": "123"})
    assert [r["nome"] for r in response.json["funcionarios"]] == ["Zelia", "Ana"]
    response = client.get("/api/web/funcionarios/busca", headers=headers, query_string={"q": "%"})
    assert [r["nome"] for r in response.json["funcionarios"]] == ["% Pessoa", "Ana % Pessoa"]


@pytest.mark.postgres
def test_search_handles_empty_wildcards_history_and_invalid_query(funcionarios_api, session):
    client, headers, rh = funcionarios_api
    session.add(Funcionarios(empresa_id=rh.empresa_id, nome="Pessoa Histórica", matricula="ID_10%", ativo=False))
    session.commit()
    for q in ("inexistente", "%%", "__"):
        assert client.get("/api/web/funcionarios/busca", query_string={"q": q}, headers=headers).json == {"funcionarios": []}
    found = client.get("/api/web/funcionarios/busca", query_string={"q": "_10%"}, headers=headers).json["funcionarios"]
    assert len(found) == 1 and found[0]["ativo"] is False
    assert client.get("/api/web/funcionarios/busca?q=P", headers=headers).json["funcionarios"][0]["nome"] == "Pessoa Histórica"
    for query in ({"q": "x" * 151}, {"q": "ana", "matricula": "001"}):
        assert client.get("/api/web/funcionarios/busca", query_string=query, headers=headers).status_code == 400


@pytest.mark.postgres
def test_empty_search_returns_only_first_twenty_of_current_tenant(funcionarios_api, session, tenants):
    client, headers, rh = funcionarios_api
    session.add_all([
        Funcionarios(empresa_id=rh.empresa_id, nome=f"Ana {n:02}", matricula=f"INI-{n:03}")
        for n in range(25)
    ])
    session.add(Funcionarios(empresa_id=tenants[1].company.id, nome="AAA outra empresa", matricula="INI-999"))
    session.commit()
    for query in ({}, {"q": ""}, {"q": "  "}, {"matricula": ""}, {"q": "", "matricula": ""}):
        response = client.get("/api/web/funcionarios/busca", query_string=query, headers=headers)
        assert response.status_code == 200
        rows = response.json["funcionarios"]
        assert len(rows) == 20
        assert [row["nome"] for row in rows] == [f"Ana {n:02}" for n in range(20)]
        assert {row["empresa_id"] for row in rows} == {str(rh.empresa_id)}


@pytest.mark.postgres
def test_search_revalidates_role_and_tenant_claim(funcionarios_api, session, tenants):
    client, headers, rh = funcionarios_api
    forged = create_access_token(identity=str(rh.id), additional_claims={"empresa_id": str(tenants[1].company.id), "role": "RH"})
    assert client.get("/api/web/funcionarios/busca?q=ana", headers={"Authorization": "Bearer " + forged}).status_code == 401
    rh.papel = PapelUsuario.GESTOR
    session.commit()
    assert client.get("/api/web/funcionarios/busca?q=ana", headers=headers).status_code == 200


@pytest.mark.parametrize(("path", "method"), [
    ("/api/web/funcionarios", "GET"),
    ("/api/web/funcionarios/busca", "GET"),
    ("/api/web/funcionarios", "POST"),
    ("/api/web/funcionarios/" + str(uuid.uuid4()), "PUT"),
])
def test_preflight_exists_and_accepts_authorization_without_jwt(app, path, method):
    response = app.test_client().options(path, headers={
        "Origin": "https://painel.example", "Access-Control-Request-Method": method,
        "Access-Control-Request-Headers": "authorization,content-type",
    })
    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == "https://painel.example"
    assert "authorization" in response.headers["Access-Control-Allow-Headers"].lower()
    assert method in response.headers["Access-Control-Allow-Methods"]


@pytest.mark.parametrize("method", ["GET", "POST", "PUT"])
def test_endpoints_require_jwt(app, method):
    path = "/api/web/funcionarios" + ("/" + str(uuid.uuid4()) if method == "PUT" else "")
    assert app.test_client().open(path, method=method, json=cadastro()).status_code == 401


@pytest.mark.postgres
def test_create_and_update_return_complete_dto_and_list_is_tenant_scoped(funcionarios_api, session, tenants):
    client, headers, rh = funcionarios_api
    response = client.post("/api/web/funcionarios", headers=headers, json=cadastro())
    assert response.status_code == 201
    dto = response.json["funcionario"]
    assert dto == {
        "id": dto["id"], "nome": "Ana Silva", "matricula": "002", "cargo": None,
        "empresa_id": str(rh.empresa_id), "ativo": True,
    }
    target = "/api/web/funcionarios/" + dto["id"]
    updated = client.put(target, headers=headers, json=cadastro(nome="Ana Souza", cargo="Motorista"))
    assert updated.status_code == 200 and updated.json["funcionario"]["cargo"] == "Motorista"
    rows = client.get("/api/web/funcionarios", headers=headers).json["funcionarios"]
    assert {row["id"] for row in rows} == {str(tenants[0].employee.id), dto["id"]}
    assert all(row["empresa_id"] == str(rh.empresa_id) for row in rows)
    assert str(tenants[1].employee.id) not in {row["id"] for row in rows}


@pytest.mark.postgres
def test_deactivate_preserves_employee_and_assignment_history(funcionarios_api, session, tenants):
    client, headers, _ = funcionarios_api
    employee = tenants[0].employee
    target = "/api/web/funcionarios/" + str(employee.id)
    response = client.put(target, headers=headers, json={"ativo": False})
    assert response.status_code == 200 and response.json["funcionario"]["ativo"] is False
    assert session.get(Funcionarios, employee.id) is not None
    assert session.get(Alocacoes, tenants[0].assignment.id).funcionario_id == employee.id
    rows = client.get("/api/web/funcionarios", headers=headers).json["funcionarios"]
    assert rows[0]["ativo"] is False
    assert client.delete(target, headers=headers).status_code == 405


@pytest.mark.postgres
def test_duplicate_matricula_fails_on_create_and_update_without_changes(funcionarios_api, session, tenants):
    client, headers, _ = funcionarios_api
    duplicate = client.post("/api/web/funcionarios", headers=headers, json=cadastro(matricula="001"))
    assert duplicate.status_code == 409
    assert duplicate.json["erro"]["codigo"] == "MATRICULA_DUPLICADA"
    assert "matrícula" in duplicate.json["erro"]["mensagem"]
    created = client.post("/api/web/funcionarios", headers=headers, json=cadastro()).json["funcionario"]
    response = client.put("/api/web/funcionarios/" + created["id"], headers=headers,
        json={"nome": "Não salvar", "matricula": "001"})
    assert response.status_code == 409
    stored = session.get(Funcionarios, uuid.UUID(created["id"]))
    assert stored.nome == "Ana Silva" and stored.matricula == "002"


@pytest.mark.postgres
def test_same_matricula_is_allowed_in_distinct_companies(funcionarios_api, session, tenants):
    client, headers, _ = funcionarios_api
    other = Funcionarios(empresa_id=tenants[1].company.id, nome="Outra empresa", matricula="002")
    session.add(other)
    session.commit()
    assert client.post("/api/web/funcionarios", headers=headers, json=cadastro()).status_code == 201


@pytest.mark.postgres
def test_foreign_employee_cannot_be_edited_or_deactivated(funcionarios_api, session, tenants):
    client, headers, _ = funcionarios_api
    foreign = tenants[1].employee
    target = "/api/web/funcionarios/" + str(foreign.id)
    for payload in ({"ativo": False}, {"nome": "Invasão"}):
        assert client.put(target, headers=headers, json=payload).status_code == 404
    assert session.get(Funcionarios, foreign.id).ativo is True


@pytest.mark.postgres
@pytest.mark.parametrize("dados", [
    {}, [], None, {"nome": "Ana"}, cadastro(nome="  "), cadastro(matricula=""),
    cadastro(cargo=123), cadastro(nome="A" * 151), cadastro(matricula="1" * 51),
    cadastro(cargo="C" * 121), cadastro(ativo="false"), cadastro(empresa_id=str(uuid.uuid4())),
])
def test_invalid_body_is_rejected_without_persistence(funcionarios_api, session, dados):
    client, headers, _ = funcionarios_api
    before = session.scalar(select(func.count()).select_from(Funcionarios))
    response = client.post("/api/web/funcionarios", headers=headers, json=dados)
    assert response.status_code == 400
    assert session.scalar(select(func.count()).select_from(Funcionarios)) == before


@pytest.mark.postgres
@pytest.mark.parametrize("role", [PapelUsuario.GESTOR, PapelUsuario.FUNCIONARIO, PapelUsuario.RELOGIO])
def test_permission_is_read_from_database_not_forged_role(funcionarios_api, session, role):
    client, headers, rh = funcionarios_api
    rh.papel = role
    session.commit()
    assert client.get("/api/web/funcionarios", headers=headers).status_code == 403
    assert client.post("/api/web/funcionarios", headers=headers, json=cadastro()).status_code == 403


@pytest.mark.postgres
def test_inactive_company_or_expired_jwt_is_blocked(funcionarios_api, session, tenants):
    client, headers, rh = funcionarios_api
    expired = create_access_token(identity=str(rh.id), expires_delta=timedelta(seconds=-1),
        additional_claims={"empresa_id": str(rh.empresa_id)})
    assert client.get("/api/web/funcionarios", headers={"Authorization": "Bearer " + expired}).status_code == 401
    tenants[0].company.ativo = False
    session.commit()
    assert client.get("/api/web/funcionarios", headers=headers).status_code == 401


@pytest.mark.postgres
def test_superadmin_and_mismatched_tenant_claim_cannot_access(funcionarios_api, session, tenants):
    client, _, rh = funcionarios_api
    global_admin = Usuarios(nome="Global", email="global@w03.example", senha_hash="hash",
        papel=PapelUsuario.SUPERADMIN, empresa_id=None)
    session.add(global_admin)
    session.commit()
    token = create_access_token(identity=str(global_admin.id), additional_claims={"empresa_id": None})
    assert client.get("/api/web/funcionarios", headers={"Authorization": "Bearer " + token}).status_code == 403
    mismatch = create_access_token(identity=str(rh.id), additional_claims={
        "empresa_id": str(tenants[1].company.id), "role": "RH"})
    assert client.get("/api/web/funcionarios", headers={"Authorization": "Bearer " + mismatch}).status_code == 401


@pytest.mark.postgres
def test_failed_commit_rolls_back_and_returns_safe_json(funcionarios_api, session, monkeypatch):
    client, headers, _ = funcionarios_api
    def falhar():
        raise OperationalError("SQL privado", {}, Exception("senha privada"))
    with monkeypatch.context() as patch:
        patch.setattr(session, "commit", falhar)
        response = client.post("/api/web/funcionarios", headers=headers, json=cadastro())
    assert response.status_code == 503
    assert "privad" not in response.get_data(as_text=True)
    assert session.scalar(select(Funcionarios.id).where(Funcionarios.matricula == "002")) is None


@pytest.mark.postgres
def test_persistence_is_visible_to_new_http_sessions():
    from test_mobile_w09 import concurrent_app
    with concurrent_app() as application, application.app_context():
        company = Empresas(razao_social="Teste W03", cnpj="99887766000100")
        db.session.add(company)
        db.session.flush()
        rh = Usuarios(empresa_id=company.id, nome="RH", email="rh@w03.example",
            senha_hash="hash-teste", papel=PapelUsuario.RH)
        db.session.add(rh)
        db.session.commit()
        token = create_access_token(identity=str(rh.id), additional_claims={"empresa_id": str(company.id)})
        headers = {"Authorization": "Bearer " + token}
        created = application.test_client().post("/api/web/funcionarios", headers=headers, json=cadastro())
        assert created.status_code == 201
        dto = created.json["funcionario"]
        db.session.remove()
        assert application.test_client().get("/api/web/funcionarios", headers=headers).json == {"funcionarios": [dto]}
        assert application.test_client().put("/api/web/funcionarios/" + dto["id"],
            headers=headers, json={"ativo": False}).status_code == 200
        db.session.remove()
        assert application.test_client().get("/api/web/funcionarios", headers=headers).json["funcionarios"][0]["ativo"] is False
