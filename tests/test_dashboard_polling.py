from types import SimpleNamespace
from uuid import uuid4

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import event
from sqlalchemy.dialects import postgresql

from app import db
from app.models import Funcionarios, PapelUsuario, Usuarios
from app.services.auth_service import AuthService
from app.services.dashboard_service import DashboardService


def test_counts_are_one_scalar_select_with_tenant_on_every_count(app, monkeypatch):
    empresa = uuid4()
    captured = []
    monkeypatch.setattr(AuthService, "me", lambda *args, **kwargs: (
        {"usuario": {"papel": "RH", "empresa_id": str(empresa)}}, 200,
    ))

    class FakeSession:
        def execute(self, statement):
            captured.append(statement)
            return SimpleNamespace(mappings=lambda: SimpleNamespace(one=lambda: {
                "funcionarios": 40, "setores": 2, "escalas_ativas": 1,
                "justificativas_pendentes": 0,
            }))

    with app.app_context():
        payload, status = DashboardService.consultar(uuid4(), empresa, FakeSession())
    assert status == 200 and payload["indicadores"]["funcionarios"] == 40
    assert len(captured) == 1
    compiled = captured[0].compile(dialect=postgresql.dialect())
    assert str(compiled).lower().count("count(") == 4
    assert sum(value == empresa for value in compiled.params.values()) == 4


@pytest.mark.parametrize("papel", ["FUNCIONARIO", "RELOGIO"])
def test_dashboard_rejects_non_administrative_accounts(app, monkeypatch, papel):
    monkeypatch.setattr(AuthService, "me", lambda *args, **kwargs: (
        {"usuario": {"papel": papel, "empresa_id": str(uuid4())}}, 200,
    ))
    with app.app_context():
        assert DashboardService.consultar(uuid4(), uuid4(), object())[1] == 403


def test_http_dashboard_passes_only_jwt_tenant_and_disables_shared_caching(app, monkeypatch):
    usuario, empresa = uuid4(), uuid4()
    captured = []
    def consultar(uid, eid):
        captured.append((uid, eid))
        return {"empresa_id": eid, "indicadores": {"funcionarios": 40}}, 200
    monkeypatch.setattr(DashboardService, "consultar", consultar)
    with app.app_context():
        token = create_access_token(identity=str(usuario), additional_claims={"empresa_id": str(empresa)})
    client = app.test_client()
    assert client.get("/api/web/dashboard").status_code == 401
    response = client.get("/api/web/dashboard?empresa_id=" + str(uuid4()),
        headers={"Authorization": "Bearer " + token})
    assert response.status_code == 200
    assert captured == [(str(usuario), str(empresa))]
    assert response.headers["Cache-Control"] == "private, no-store"


def test_real_counts_are_isolated_and_superadmin_does_not_load_companies(session, tenants):
    own, foreign = tenants
    rh = Usuarios(empresa_id=own.company.id, nome="RH polling", email="rh-polling@example.com",
        papel=PapelUsuario.RH, senha_hash="teste")
    admin = Usuarios(empresa_id=None, nome="Superadmin polling", email="admin-polling@example.com",
        papel=PapelUsuario.SUPERADMIN, senha_hash="teste")
    session.add_all([rh, admin,
        Funcionarios(empresa_id=own.company.id, nome="Inativo", matricula="INATIVO", ativo=False),
        Funcionarios(empresa_id=foreign.company.id, nome="Outra empresa", matricula="FORA"),
    ])
    session.commit()
    queries = []
    def capture(connection, cursor, statement, parameters, context, many):
        if "count(" in statement.lower():
            queries.append(statement)
    event.listen(session.bind, "before_cursor_execute", capture)
    try:
        payload, status = DashboardService.consultar(rh.id, own.company.id, session)
        assert status == 200 and payload["indicadores"]["funcionarios"] == 1
        assert payload["indicadores"]["setores"] == 1
        assert len(queries) == 1 and queries[0].lower().count("count(") == 4
        assert DashboardService.consultar(rh.id, foreign.company.id, session)[1] == 401
        queries.clear()
        payload, status = DashboardService.consultar(admin.id, None, session)
        assert status == 200 and payload == {"empresa_id": None, "indicadores": {"empresas": 2}}
        assert len(queries) == 1
    finally:
        event.remove(session.bind, "before_cursor_execute", capture)
