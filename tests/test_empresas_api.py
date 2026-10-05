"""Persistência de empresas, provisionamento RH e autorização do Superadmin."""
from pathlib import Path
import uuid

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import func, select, text
from werkzeug.security import check_password_hash

from app import db
from app.models import Empresas, PapelUsuario, Usuarios
from app.services.auth_service import AuthService
from app.services.empresa_service import EmpresaService


@pytest.fixture
def empresas_api(session, pg_app, monkeypatch):
    admin = Usuarios(nome="Global", email="global@teste.com", empresa_id=None,
        papel=PapelUsuario.SUPERADMIN, senha_hash="hash-teste")
    session.add(admin)
    session.commit()
    methods = {name: getattr(EmpresaService, name) for name in ("listar", "criar", "atualizar")}
    monkeypatch.setattr(EmpresaService, "listar", staticmethod(lambda uid, eid: methods["listar"](uid, eid, session=session)))
    monkeypatch.setattr(EmpresaService, "criar", staticmethod(lambda uid, eid, data: methods["criar"](uid, eid, data, session=session)))
    monkeypatch.setattr(EmpresaService, "atualizar", staticmethod(lambda uid, eid, target, data: methods["atualizar"](uid, eid, target, data, session=session)))
    token = create_access_token(identity=str(admin.id), additional_claims={"empresa_id": None, "role": "SUPERADMIN"})
    return pg_app.test_client(), {"Authorization": "Bearer " + token}


def cadastro(**changes):
    return {"razao_social": "Empresa persistente", "cnpj": "12.345.678/0001-95", "ativo": True,
        "admin_nome": "RH Responsável", "admin_email": "rh@persistente.com", "admin_senha": "Senha-segura-RH-123", **changes}


@pytest.mark.postgres
def test_create_persists_company_and_hashed_rh_atomically(empresas_api, session):
    client, headers = empresas_api
    response = client.post("/api/web/empresas", headers=headers, json=cadastro())
    assert response.status_code == 201
    company = response.get_json()["empresa"]
    assert company["cnpj"] == "12345678000195" and company["admin_email"] == "rh@persistente.com"
    assert "admin_senha" not in company and "senha_hash" not in company
    account = session.scalar(select(Usuarios).where(Usuarios.email == company["admin_email"]))
    assert account.empresa_id == uuid.UUID(company["id"]) and account.papel == PapelUsuario.RH
    assert check_password_hash(account.senha_hash, cadastro()["admin_senha"])
    assert client.get("/api/web/empresas", headers=headers).get_json()["empresas"] == [company]


@pytest.mark.postgres
def test_update_responsible_and_deactivate_are_saved_without_deletion(empresas_api, session):
    client, headers = empresas_api
    company = client.post("/api/web/empresas", headers=headers, json=cadastro()).get_json()["empresa"]
    account_id = session.scalar(select(Usuarios.id).where(Usuarios.email == company["admin_email"]))
    url = "/api/web/empresas/" + company["id"]
    assert client.put(url, headers=headers, json={"razao_social": "Nome editado",
        "admin_email": "novo@persistente.com", "admin_nome": "Novo nome"}).status_code == 200
    assert session.scalar(select(Usuarios).where(Usuarios.id == account_id)).email == "novo@persistente.com"
    result = client.patch(url, headers=headers, json={"ativo": False})
    assert result.status_code == 200 and result.get_json()["empresa"]["ativo"] is False
    assert session.scalar(select(func.count()).select_from(Empresas)) == 1
    payload, status = AuthService.login({"email": "novo@persistente.com", "senha": cadastro()["admin_senha"]}, session=session)
    assert status == 401
    assert client.patch(url, headers=headers, json={"ativo": True}).status_code == 200
    assert AuthService.login({"email": "novo@persistente.com", "senha": cadastro()["admin_senha"]}, session=session)[1] == 200


@pytest.mark.postgres
@pytest.mark.parametrize("field", ["cnpj", "admin_email"])
def test_duplicate_registration_rolls_back_entire_transaction(empresas_api, session, field):
    client, headers = empresas_api
    assert client.post("/api/web/empresas", headers=headers, json=cadastro()).status_code == 201
    changes = {"cnpj": "11222333000181", "admin_email": "outro@persistente.com"}
    changes[field] = cadastro()[field]
    assert client.post("/api/web/empresas", headers=headers, json=cadastro(**changes)).status_code == 409
    assert session.scalar(select(func.count()).select_from(Empresas)) == 1
    assert session.scalar(select(func.count()).select_from(Usuarios).where(Usuarios.papel == PapelUsuario.RH)) == 1


@pytest.mark.postgres
@pytest.mark.parametrize("changes", [{"admin_senha": "curta"}, {"cnpj": "123"}, {"ativo": "true"}, {"empresa_id": str(uuid.uuid4())}])
def test_invalid_registration_does_not_create_rows(empresas_api, session, changes):
    client, headers = empresas_api
    assert client.post("/api/web/empresas", headers=headers, json=cadastro(**changes)).status_code == 422
    assert session.scalar(select(func.count()).select_from(Empresas)) == 0


@pytest.mark.postgres
def test_role_is_checked_in_database_not_only_token(empresas_api, session, tenants):
    client, _ = empresas_api
    session.commit()
    employee = tenants[0].user
    forged_role = create_access_token(identity=str(employee.id), additional_claims={
        "empresa_id": str(employee.empresa_id), "role": "SUPERADMIN"})
    headers = {"Authorization": "Bearer " + forged_role}
    assert client.get("/api/web/empresas", headers=headers).status_code == 403
    assert client.post("/api/web/empresas", headers=headers, json=cadastro()).status_code == 403
    assert client.patch("/api/web/empresas/" + str(tenants[1].company.id), headers=headers, json={"ativo": False}).status_code == 403


@pytest.mark.postgres
def test_commit_is_visible_from_independent_http_sessions():
    from test_mobile_w09 import concurrent_app
    with concurrent_app() as application, application.app_context():
        admin = Usuarios(nome="Global", email="global@teste.com", empresa_id=None,
            papel=PapelUsuario.SUPERADMIN, senha_hash=AuthService.hash_senha("SenhaGlobalForte"))
        db.session.add(admin)
        db.session.commit()
        auth = application.test_client().post("/api/web/auth/login", json={"email": admin.email, "senha": "SenhaGlobalForte"})
        headers = {"Authorization": "Bearer " + auth.get_json()["access_token"]}
        first = application.test_client().post("/api/web/empresas", headers=headers, json=cadastro())
        assert first.status_code == 201
        db.session.remove()
        second = application.test_client().get("/api/web/empresas", headers=headers)
        assert second.get_json()["empresas"] == [first.get_json()["empresa"]]
        target = "/api/web/empresas/" + first.get_json()["empresa"]["id"]
        assert application.test_client().patch(target, headers=headers, json={"admin_email": "novo@persistente.com"}).status_code == 200
        db.session.remove()
        assert application.test_client().get("/api/web/empresas", headers=headers).get_json()["empresas"][0]["admin_email"] == "novo@persistente.com"


@pytest.mark.postgres
def test_bootstrap_command_creates_private_credentials_without_overwriting(session, pg_app, tmp_path, monkeypatch):
    with monkeypatch.context() as patch:
        patch.setattr(pg_app, "instance_path", str(tmp_path))
        patch.setattr(db, "session", session)
        runner = pg_app.test_cli_runner()
        result = runner.invoke(args=["criar-superadmin", "--email", "admin@teste.com", "--gerar-senha"])
        assert result.exit_code == 0
        files = list(Path(tmp_path).glob("primeiro-acesso-superadmin-*.txt"))
        assert len(files) == 1
        senha = files[0].read_text(encoding="utf-8").split("Senha: ")[1].strip()
        assert senha not in result.output
        admin = session.scalar(select(Usuarios).where(Usuarios.email == "admin@teste.com"))
        assert admin.papel == PapelUsuario.SUPERADMIN and admin.empresa_id is None
        assert check_password_hash(admin.senha_hash, senha)
        original = admin.senha_hash
        assert runner.invoke(args=["criar-superadmin", "--email", "admin@teste.com", "--gerar-senha"]).exit_code != 0
        assert admin.senha_hash == original and len(list(Path(tmp_path).glob("*.txt"))) == 1
