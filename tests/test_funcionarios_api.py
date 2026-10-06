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
    methods = {name: getattr(FuncionarioService, name) for name in ("listar", "criar", "atualizar")}
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


@pytest.mark.parametrize(("path", "method"), [
    ("/api/web/funcionarios", "GET"),
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
