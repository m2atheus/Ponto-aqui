"""W03: consulta de setores, alocação real e encerramento com histórico."""

from datetime import date, time
from concurrent.futures import ThreadPoolExecutor
import uuid

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import func, select

from app import db
from app.models import Alocacoes, Empresas, Funcionarios, PapelUsuario, Setores, Turnos, Usuarios
from app.services.alocacao_service import AlocacaoService
from app.services.setor_service import SetorService


@pytest.fixture
def alocacoes_api(session, pg_app, tenants, monkeypatch):
    rh = Usuarios(nome="RH", email="rh@alocacoes.example", senha_hash="hash",
        empresa_id=tenants[0].company.id, papel=PapelUsuario.RH)
    tenants[0].assignment.data_fim = date(2026, 9, 30)
    session.add(rh)
    session.commit()
    listar, criar, encerrar = AlocacaoService.listar, AlocacaoService.criar, AlocacaoService.encerrar
    setores = SetorService.listar
    monkeypatch.setattr(AlocacaoService, "listar", staticmethod(
        lambda uid, eid, fid: listar(uid, eid, fid, session=session)))
    monkeypatch.setattr(AlocacaoService, "criar", staticmethod(
        lambda uid, eid, data: criar(uid, eid, data, session=session)))
    monkeypatch.setattr(AlocacaoService, "encerrar", staticmethod(
        lambda uid, eid, target, data: encerrar(uid, eid, target, data, session=session)))
    monkeypatch.setattr(SetorService, "listar", staticmethod(
        lambda uid, eid: setores(uid, eid, session=session)))
    token = create_access_token(identity=str(rh.id), additional_claims={"empresa_id": str(rh.empresa_id)})
    return pg_app.test_client(), {"Authorization": "Bearer " + token}, rh


def cadastro(tenant, **changes):
    return {"funcionario_id": str(tenant.employee.id), "setor_id": str(tenant.sector.id),
        "data_inicio": "2026-10-01", "data_fim": None, **changes}


@pytest.mark.parametrize(("path", "method"), [
    ("/api/web/setores", "GET"), ("/api/web/alocacoes", "GET"),
    ("/api/web/alocacoes", "POST"), ("/api/web/alocacoes/" + str(uuid.uuid4()), "PUT"),
])
def test_preflight_and_jwt_on_new_endpoints(app, path, method):
    client = app.test_client()
    response = client.options(path, headers={"Origin": "https://painel.example",
        "Access-Control-Request-Method": method, "Access-Control-Request-Headers": "authorization,content-type"})
    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == "https://painel.example"
    assert client.open(path, method=method, json={}).status_code == 401


@pytest.mark.postgres
def test_lists_are_scoped_and_include_inactive_records_for_history(alocacoes_api, session, tenants):
    client, headers, _ = alocacoes_api
    tenants[0].sector.ativo = False
    session.commit()
    setores = client.get("/api/web/setores", headers=headers).json["setores"]
    assert len(setores) == 1 and setores[0]["id"] == str(tenants[0].sector.id)
    assert setores[0]["ativo"] is False
    rows = client.get("/api/web/alocacoes", headers=headers).json["alocacoes"]
    assert [row["id"] for row in rows] == [str(tenants[0].assignment.id)]
    foreign = client.get("/api/web/alocacoes", headers=headers,
        query_string={"funcionario_id": str(tenants[1].employee.id)})
    assert foreign.json == {"alocacoes": []}


@pytest.mark.postgres
def test_create_and_end_preserve_ids_dates_and_history(alocacoes_api, session, tenants):
    client, headers, rh = alocacoes_api
    created = client.post("/api/web/alocacoes", headers=headers, json=cadastro(tenants[0]))
    assert created.status_code == 201
    dto = created.json["alocacao"]
    assert dto["empresa_id"] == str(rh.empresa_id) and dto["data_fim"] is None
    row = session.get(Alocacoes, uuid.UUID(dto["id"]))
    assert row.usuario_id == tenants[0].employee.usuario_id
    target = "/api/web/alocacoes/" + dto["id"]
    ended = client.put(target, headers=headers, json={"data_fim": "2026-10-31"})
    assert ended.status_code == 200
    assert ended.json == {"alocacao": {**dto, "data_fim": "2026-10-31"}}
    assert session.scalar(select(func.count()).select_from(Alocacoes)) == 3
    assert client.delete(target, headers=headers).status_code == 405
    assert client.put(target, headers=headers, json={"data_fim": "2026-10-31"}).status_code == 200
    assert client.put(target, headers=headers, json={"data_fim": "2026-11-30"}).status_code == 409


@pytest.mark.postgres
def test_overlap_dates_are_inclusive_but_next_day_is_allowed(alocacoes_api, tenants):
    client, headers, _ = alocacoes_api
    assert client.post("/api/web/alocacoes", headers=headers,
        json=cadastro(tenants[0], data_fim="2026-10-31")).status_code == 201
    conflict = client.post("/api/web/alocacoes", headers=headers,
        json=cadastro(tenants[0], data_inicio="2026-10-31", data_fim="2026-11-30"))
    assert conflict.status_code == 409 and conflict.json["erro"]["codigo"] == "ALOCACAO_SOBREPOSTA"
    assert client.post("/api/web/alocacoes", headers=headers,
        json=cadastro(tenants[0], data_inicio="2026-11-01")).status_code == 201


@pytest.mark.postgres
def test_open_period_overlaps_later_assignment_and_other_sector_is_allowed(alocacoes_api, session, tenants):
    client, headers, _ = alocacoes_api
    assert client.post("/api/web/alocacoes", headers=headers,
        json=cadastro(tenants[0], data_inicio="2026-12-01", data_fim="2026-12-31")).status_code == 201
    assert client.post("/api/web/alocacoes", headers=headers, json=cadastro(tenants[0])).status_code == 409
    other = Setores(empresa_id=tenants[0].company.id, nome="Filial", latitude_centro=0,
        longitude_centro=0, raio_metros=100)
    session.add(other)
    session.commit()
    assert client.post("/api/web/alocacoes", headers=headers,
        json=cadastro(tenants[0], setor_id=str(other.id))).status_code == 201


@pytest.mark.postgres
@pytest.mark.parametrize("field", ["funcionario_id", "setor_id"])
def test_cross_tenant_links_are_rejected(alocacoes_api, tenants, field):
    client, headers, _ = alocacoes_api
    foreign_id = tenants[1].employee.id if field == "funcionario_id" else tenants[1].sector.id
    assert client.post("/api/web/alocacoes", headers=headers,
        json=cadastro(tenants[0], **{field: str(foreign_id)})).status_code == 404
    target = "/api/web/alocacoes/" + str(tenants[1].assignment.id)
    assert client.put(target, headers=headers, json={"data_fim": "2026-10-31"}).status_code == 404


@pytest.mark.postgres
@pytest.mark.parametrize("entity", ["employee", "sector"])
def test_inactive_links_cannot_receive_new_assignment(alocacoes_api, session, tenants, entity):
    client, headers, _ = alocacoes_api
    getattr(tenants[0], entity).ativo = False
    session.commit()
    assert client.post("/api/web/alocacoes", headers=headers, json=cadastro(tenants[0])).status_code == 404


@pytest.mark.postgres
@pytest.mark.parametrize("changes", [
    {"data_inicio": "2026-02-30"}, {"data_fim": "2026-09-30"}, {"data_inicio": "01/10/2026"},
    {"data_fim": ""}, {"funcionario_id": 123}, {"setor_id": "errado"},
    {"empresa_id": str(uuid.uuid4())}, {"usuario_id": str(uuid.uuid4())},
])
def test_invalid_creation_does_not_save(alocacoes_api, session, tenants, changes):
    client, headers, _ = alocacoes_api
    assert client.post("/api/web/alocacoes", headers=headers,
        json=cadastro(tenants[0], **changes)).status_code == 400
    assert session.scalar(select(func.count()).select_from(Alocacoes)) == 2


@pytest.mark.postgres
@pytest.mark.parametrize("body", [
    {"data_fim": None}, {"data_fim": "2019-12-31"},
    {"data_fim": "2026-10-31", "setor_id": str(uuid.uuid4())},
    {"data_fim": "2026-10-31", "data_inicio": "2025-01-01"},
])
def test_ending_rejects_history_rewrite_or_reopening(alocacoes_api, session, tenants, body):
    client, headers, _ = alocacoes_api
    target = "/api/web/alocacoes/" + str(tenants[0].assignment.id)
    assert client.put(target, headers=headers, json=body).status_code == 400
    assert session.get(Alocacoes, tenants[0].assignment.id).data_fim == date(2026, 9, 30)


@pytest.mark.postgres
def test_rbac_is_checked_from_current_user(alocacoes_api, session):
    client, headers, rh = alocacoes_api
    rh.papel = PapelUsuario.GESTOR
    session.commit()
    assert client.get("/api/web/setores", headers=headers).status_code == 403
    assert client.get("/api/web/alocacoes", headers=headers).status_code == 403
    assert client.post("/api/web/alocacoes", headers=headers, json={}).status_code == 403


@pytest.mark.postgres
def test_optional_schedule_checks_other_sectors_and_allows_touching_shifts(alocacoes_api, session, tenants):
    from test_schedule_conflicts_w05 import existing, schedule
    client, headers, _ = alocacoes_api
    tenant = tenants[0]
    existing(session, tenant, start=8, end=19, days=[1])
    tenant.assignment.data_fim = date(2026, 10, 5)
    new_schedule = schedule(session, tenant, start=18, end=23, days=[1])
    other = Setores(empresa_id=tenant.company.id, nome="Segundo setor", latitude_centro=0,
        longitude_centro=0, raio_metros=100)
    session.add(other)
    session.commit()
    payload = cadastro(tenant, setor_id=str(other.id), data_inicio="2026-10-05",
        data_fim="2026-10-05", escala_id=str(new_schedule.id))
    conflict = client.post("/api/web/alocacoes", headers=headers, json=payload)
    assert conflict.status_code == 409
    assert conflict.json["erro"]["codigo"] == "CONFLITO_ESCALA"
    assert conflict.json["erro"]["detalhes"]["setor_id"] == str(tenant.sector.id)
    turno = session.scalar(select(Turnos).where(Turnos.escala_id == new_schedule.id))
    turno.hora_inicio = time(19)
    session.commit()
    accepted = client.post("/api/web/alocacoes", headers=headers, json=payload)
    assert accepted.status_code == 201
    assert accepted.json["alocacao"]["escala_id"] == str(new_schedule.id)


@pytest.mark.postgres
def test_concurrent_creation_commits_only_one_and_remains_visible():
    from test_mobile_w09 import concurrent_app
    with concurrent_app() as application, application.app_context():
        company = Empresas(razao_social="W03 corrida", cnpj="88664422000100")
        db.session.add(company)
        db.session.flush()
        rh = Usuarios(empresa_id=company.id, nome="RH", email="rh@race-w03.example",
            senha_hash="hash", papel=PapelUsuario.RH)
        employee = Funcionarios(empresa_id=company.id, nome="Ana", matricula="001")
        sector = Setores(empresa_id=company.id, nome="Sede", latitude_centro=0,
            longitude_centro=0, raio_metros=100)
        db.session.add_all([rh, employee, sector])
        db.session.commit()
        payload = {"funcionario_id": str(employee.id), "setor_id": str(sector.id),
            "data_inicio": "2026-10-01", "data_fim": None}
        token = create_access_token(identity=str(rh.id), additional_claims={"empresa_id": str(company.id)})
        headers = {"Authorization": "Bearer " + token}
        db.session.remove()
        def cadastrar(_):
            return application.test_client().post("/api/web/alocacoes", headers=headers, json=payload).status_code
        with ThreadPoolExecutor(max_workers=2) as pool:
            assert sorted(pool.map(cadastrar, range(2))) == [201, 409]
        rows = application.test_client().get("/api/web/alocacoes", headers=headers).json["alocacoes"]
        assert len(rows) == 1 and rows[0]["data_fim"] is None
        assert application.test_client().put("/api/web/alocacoes/" + rows[0]["id"],
            headers=headers, json={"data_fim": "2026-10-31"}).status_code == 200
        db.session.remove()
        assert application.test_client().get("/api/web/alocacoes", headers=headers).json["alocacoes"][0]["data_fim"] == "2026-10-31"
