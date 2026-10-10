"""Credenciais reais para funcionários, isolamento e vínculo atômico."""

import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from threading import Barrier
from types import SimpleNamespace

import pytest
from flask_jwt_extended import create_access_token, decode_token
from sqlalchemy import func, select
from sqlalchemy.exc import OperationalError
from werkzeug.security import check_password_hash

from app import db
from app.models import Afastamentos, Alocacoes, Empresas, Funcionarios, PapelUsuario, Usuarios
from app.services.device_service import DeviceService
from app.services.funcionario_service import FuncionarioService
from app.services.mobile_sync_service import MobileSyncService
from test_mobile_w09 import concurrent_app


def path(target):
    return f"/api/v1/funcionarios/{target}/vincular-acesso"


def dados(**changes):
    return {"email": "  Ana.Acesso@Example.com  ", "senha": "Senha-teste-123", **changes}


@pytest.mark.parametrize("mode", ["missing", "expired", "invalid"])
def test_route_requires_valid_jwt(app, mode):
    headers = {}
    if mode != "missing":
        with app.app_context():
            token = create_access_token(identity=str(uuid.uuid4()), expires_delta=timedelta(seconds=-1))
        headers["Authorization"] = "Bearer " + (token if mode == "expired" else "invalid")
    assert app.test_client().post(path(uuid.uuid4()), headers=headers, json=dados()).status_code == 401


def test_preflight_accepts_authorization(app):
    response = app.test_client().options(path(uuid.uuid4()), headers={
        "Origin": "https://painel.example", "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "authorization,content-type",
    })
    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == "https://painel.example"


@pytest.fixture
def contexto(pg_app, session, tenants, monkeypatch):
    own, foreign = tenants
    rh = Usuarios(empresa_id=own.company.id, nome="RH", email="rh-acesso@example.com",
        senha_hash="hash", papel=PapelUsuario.RH)
    employee = Funcionarios(empresa_id=own.company.id, nome="Ana Silva", matricula="012", cargo="Analista")
    session.add_all([rh, employee])
    session.commit()
    monkeypatch.setattr(session, "remove", lambda: None, raising=False)
    monkeypatch.setattr(db, "session", session)
    return SimpleNamespace(client=pg_app.test_client(), own=own, foreign=foreign, rh=rh, employee=employee)


def headers(actor, empresa=None):
    token = create_access_token(identity=str(actor.id), additional_claims={
        "empresa_id": str(empresa or actor.empresa_id) if (empresa or actor.empresa_id) else None,
        "role": "RH",  # O papel vem do banco, não deste claim.
    })
    return {"Authorization": "Bearer " + token}


@pytest.mark.postgres
def test_created_account_hash_role_and_login_aliases_are_mobile_compatible(contexto, session):
    c = contexto
    response = c.client.post(path(c.employee.id), headers=headers(c.rh), json=dados())
    assert response.status_code == 201, response.json
    body = response.json
    uid = uuid.UUID(body["usuario"]["id"])
    stored = session.get(Usuarios, uid)
    assert stored.email == "ana.acesso@example.com"
    assert stored.nome == c.employee.nome and stored.matricula == c.employee.matricula
    assert stored.empresa_id == c.own.company.id and stored.papel == PapelUsuario.FUNCIONARIO
    assert stored.senha_hash.startswith("scrypt:")
    assert stored.senha_hash != dados()["senha"] and check_password_hash(stored.senha_hash, dados()["senha"])
    session.expire_all()
    assert session.get(Funcionarios, c.employee.id).usuario_id == uid
    assert body["funcionario"]["usuario_id"] == str(uid)
    assert body["usuario"]["papel"] == "FUNCIONARIO"
    assert "senha" not in response.get_data(as_text=True)
    assert "private, no-store" == response.headers["Cache-Control"]
    # O painel reconhece o vínculo mesmo após F5 ou uma edição posterior.
    rows = c.client.get("/api/web/funcionarios", headers=headers(c.rh)).json["funcionarios"]
    assert next(row for row in rows if row["id"] == str(c.employee.id))["usuario_id"] == str(uid)
    updated = c.client.put(f"/api/web/funcionarios/{c.employee.id}",
        headers=headers(c.rh), json={"cargo": "Analista sênior"})
    assert updated.status_code == 200 and updated.json["funcionario"]["usuario_id"] == str(uid)
    for login_path in ("/auth/login", "/api/mobile/auth/login", "/api/web/auth/login"):
        login = c.client.post(login_path, json={"email": "ANA.ACESSO@EXAMPLE.COM", "senha": dados()["senha"]})
        assert login.status_code == 200, login.json
        claims = decode_token(login.json["access_token"])
        assert claims["sub"] == str(uid) and claims["role"] == "FUNCIONARIO"
        assert claims["empresa_id"] == str(c.own.company.id)
        assert claims["exp"] > claims["iat"]


@pytest.mark.postgres
def test_existing_account_returns_400_without_creating_or_overwriting(contexto, session):
    c = contexto
    assert c.client.post(path(c.employee.id), headers=headers(c.rh), json=dados()).status_code == 201
    before = session.scalar(select(func.count()).select_from(Usuarios))
    uid = c.employee.usuario_id
    response = c.client.post(path(c.employee.id), headers=headers(c.rh), json=dados(email="new@example.com", senha="Outra-senha-123"))
    assert response.status_code == 400 and response.json["erro"]["codigo"] == "ACESSO_JA_VINCULADO"
    assert session.scalar(select(func.count()).select_from(Usuarios)) == before
    assert session.get(Funcionarios, c.employee.id).usuario_id == uid
    assert check_password_hash(session.get(Usuarios, uid).senha_hash, dados()["senha"])


@pytest.mark.postgres
@pytest.mark.parametrize("changes", [
    {"email": None}, {"email": []}, {"email": "sem-email"}, {"email": "x @example.com"},
    {"email": "a" * 255 + "@example.com"}, {"senha": "curta"}, {"senha": None}, {"senha": []},
    {"senha": "x" * 1025}, {"papel": "RH"}, {"role": "SUPERADMIN"},
    {"empresa_id": str(uuid.uuid4())}, {"usuario_id": str(uuid.uuid4())}, {"matricula": "outra"},
])
def test_invalid_input_does_not_create_an_account(contexto, session, changes):
    c = contexto
    before = session.scalar(select(func.count()).select_from(Usuarios))
    response = c.client.post(path(c.employee.id), headers=headers(c.rh), json=dados(**changes))
    assert response.status_code == 400, response.json
    assert session.scalar(select(func.count()).select_from(Usuarios)) == before
    assert session.get(Funcionarios, c.employee.id).usuario_id is None


@pytest.mark.postgres
@pytest.mark.parametrize("body", [None, [], {}, {"email": "ana@example.com"}])
def test_incomplete_payload_returns_400(contexto, body):
    c = contexto
    assert c.client.post(path(c.employee.id), headers=headers(c.rh), json=body).status_code == 400


@pytest.mark.postgres
def test_foreign_employee_and_missing_id_return_404(contexto, session):
    c = contexto
    for target in (c.foreign.employee.id, uuid.uuid4()):
        assert c.client.post(path(target), headers=headers(c.rh), json=dados()).status_code == 404
    assert session.get(Funcionarios, c.employee.id).usuario_id is None


@pytest.mark.postgres
@pytest.mark.parametrize("papel", [PapelUsuario.GESTOR, PapelUsuario.FUNCIONARIO, PapelUsuario.USUARIO_SETOR, PapelUsuario.SUPERADMIN])
def test_non_rh_cannot_create_credentials_even_with_rh_claim(contexto, session, papel):
    c = contexto
    actor = Usuarios(nome="Outro papel", email="other-role@example.com", senha_hash="hash", papel=papel,
        empresa_id=None if papel == PapelUsuario.SUPERADMIN else c.own.company.id)
    session.add(actor)
    session.commit()
    assert c.client.post(path(c.employee.id), headers=headers(actor), json=dados()).status_code == 403
    assert session.get(Funcionarios, c.employee.id).usuario_id is None


@pytest.mark.postgres
@pytest.mark.parametrize("case", ["company", "rh", "claim", "employee"])
def test_inactive_account_company_employee_and_forged_tenant(contexto, session, case):
    c = contexto
    auth = headers(c.rh, c.foreign.company.id if case == "claim" else None)
    if case == "company": c.own.company.ativo = False
    elif case == "rh": c.rh.ativo = False
    elif case == "employee": c.employee.ativo = False
    session.commit()
    response = c.client.post(path(c.employee.id), headers=auth, json=dados())
    assert response.status_code == (400 if case == "employee" else 401)
    assert session.get(Funcionarios, c.employee.id).usuario_id is None


@pytest.mark.postgres
@pytest.mark.parametrize("same_company", [True, False])
def test_unique_email_conflict_rolls_back_without_exposing_other_tenant(contexto, session, same_company):
    c = contexto
    before = session.scalar(select(func.count()).select_from(Usuarios))
    existing = c.own.user if same_company else c.foreign.user
    response = c.client.post(path(c.employee.id), headers=headers(c.rh), json=dados(email=existing.email))
    assert response.status_code == 409 and response.json["erro"]["codigo"] == "EMAIL_INDISPONIVEL"
    assert str(c.foreign.company.id) not in response.get_data(as_text=True)
    assert session.scalar(select(func.count()).select_from(Usuarios)) == before
    assert session.get(Funcionarios, c.employee.id).usuario_id is None


@pytest.mark.postgres
def test_fill_initial_identity_keeps_assignment_and_leave_history_and_supports_mobile(contexto, session):
    c = contexto
    histories = [Alocacoes(empresa_id=c.own.company.id, funcionario_id=c.employee.id,
        setor_id=c.own.sector.id, data_inicio=date(2019, 1, 1), data_fim=date(2019, 12, 31)),
        Alocacoes(empresa_id=c.own.company.id, funcionario_id=c.employee.id,
        setor_id=c.own.sector.id, data_inicio=date(2020, 1, 1))]
    leave = Afastamentos(empresa_id=c.own.company.id, funcionario_id=c.employee.id,
        tipo="FERIAS", data_inicio=date(2026, 10, 1), data_fim=date(2026, 10, 3))
    session.add_all([*histories, leave])
    session.commit()
    before = [(row.id, row.setor_id, row.escala_id, row.data_inicio, row.data_fim) for row in histories]
    response = c.client.post(path(c.employee.id), headers=headers(c.rh), json=dados())
    assert response.status_code == 201, response.json
    uid = uuid.UUID(response.json["usuario"]["id"])
    session.expire_all()
    assert all(row.usuario_id == uid for row in histories) and leave.usuario_id == uid
    assert before == [(row.id, row.setor_id, row.escala_id, row.data_inicio, row.data_fim) for row in histories]
    assert session.get(Alocacoes, c.foreign.assignment.id).usuario_id == c.foreign.user.id
    device, status = DeviceService.registrar_login_pessoal(c.own.company.id, uid, uuid.uuid4(), "Celular", session=session)
    assert status == 200
    login = c.client.post("/api/mobile/auth/login", json={"email": "ana.acesso@example.com", "senha": dados()["senha"],
        "dispositivo_id": device["dispositivo"]["id"]})
    assert login.status_code == 200
    claims = decode_token(login.json["access_token"])
    payload, status = MobileSyncService.sincronizar(c.own.company.id, uid, device["dispositivo"]["device_uuid"], claims, session=session)
    assert status == 200
    assert payload["funcionario"]["id"] == str(c.employee.id)
    assert payload["setor"]["id"] == str(c.own.sector.id)
    assert payload["alocacoes"][0]["id"] == str(histories[1].id)


@pytest.mark.postgres
def test_transaction_failure_leaves_no_orphan_user_or_link(contexto, session, monkeypatch):
    c = contexto
    before = session.scalar(select(func.count()).select_from(Usuarios))
    def fail():
        raise OperationalError("commit", {}, Exception("internal-details"))
    monkeypatch.setattr(session, "commit", fail)
    response = c.client.post(path(c.employee.id), headers=headers(c.rh), json=dados())
    assert response.status_code == 503 and "internal-details" not in response.get_data(as_text=True)
    assert session.scalar(select(func.count()).select_from(Usuarios)) == before
    assert session.get(Funcionarios, c.employee.id).usuario_id is None


@pytest.mark.postgres
def test_two_concurrent_requests_create_exactly_one_employee_account():
    with concurrent_app() as application:
        with application.app_context():
            company = Empresas(razao_social="Concorrência Acesso", cnpj="88888888888888")
            db.session.add(company)
            db.session.flush()
            actor = Usuarios(empresa_id=company.id, nome="RH", email="rh-race@example.com", papel=PapelUsuario.RH, senha_hash="hash")
            employee = Funcionarios(empresa_id=company.id, nome="Funcionário", matricula="01")
            db.session.add_all([actor, employee])
            db.session.flush()
            eid, rid, fid = company.id, actor.id, employee.id
            db.session.commit()
        barrier = Barrier(2)
        def call(index):
            with application.app_context():
                barrier.wait(timeout=10)
                return FuncionarioService.vincular_acesso(rid, eid, fid, dados(email=f"race-{index}@example.com"))
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(call, [1, 2]))
        assert sorted(status for _, status in results) == [201, 400]
        with application.app_context():
            assert db.session.scalar(select(func.count()).select_from(Usuarios).where(Usuarios.empresa_id == eid, Usuarios.papel == PapelUsuario.FUNCIONARIO)) == 1
            assert db.session.get(Funcionarios, fid).usuario_id is not None
