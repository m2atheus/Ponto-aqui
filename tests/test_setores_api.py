"""W02: contrato do mapa, isolamento de empresa e preservação do histórico."""

import uuid
from datetime import date, timedelta
from decimal import Decimal

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import func, select

from app.models import Alocacoes, Feriados, PapelUsuario, Setores, Usuarios
from app.services.setor_service import SetorService


@pytest.fixture
def setores_api(session, pg_app, tenants, monkeypatch):
    rh = Usuarios(nome="RH", email="rh@setores.example", senha_hash="hash",
        empresa_id=tenants[0].company.id, papel=PapelUsuario.RH)
    session.add(rh)
    session.commit()
    listar = SetorService.listar
    criar = SetorService.criar_setor
    atualizar = SetorService.atualizar_setor
    deletar = SetorService.deletar_setor
    monkeypatch.setattr(SetorService, "listar", staticmethod(
        lambda uid, eid: listar(uid, eid, session=session)))
    monkeypatch.setattr(SetorService, "criar_setor", staticmethod(
        lambda uid, eid, data: criar(uid, eid, data, session=session)))
    monkeypatch.setattr(SetorService, "atualizar_setor", staticmethod(
        lambda uid, eid, target, data: atualizar(uid, eid, target, data, session=session)))
    monkeypatch.setattr(SetorService, "deletar_setor", staticmethod(
        lambda uid, eid, target: deletar(uid, eid, target, session=session)))
    token = create_access_token(identity=str(rh.id), additional_claims={
        "empresa_id": str(rh.empresa_id), "role": "RH",
    })
    return pg_app.test_client(), {"Authorization": "Bearer " + token}, rh


def cadastro(**changes):
    return {"nome": " Filial ", "endereco": " Rua do Trabalho, 100 ",
        "latitude": -8.0476, "longitude": -34.877, "raio_metros": 100,
        "exige_selfie": True, "acao_fora_perimetro": "PENDENTE",
        "ignorar_localizacao": False, **changes}


@pytest.mark.parametrize(("path", "method"), [
    ("/api/web/setores", "GET"), ("/api/web/setores", "POST"),
    ("/api/web/setores/" + str(uuid.uuid4()), "PUT"),
    ("/api/web/setores/" + str(uuid.uuid4()), "DELETE"),
])
def test_setores_require_jwt_and_support_cors_preflight(app, path, method):
    client = app.test_client()
    assert client.open(path, method=method, json=cadastro()).status_code == 401
    response = client.options(path, headers={
        "Origin": "https://painel.example", "Access-Control-Request-Method": method,
        "Access-Control-Request-Headers": "authorization,content-type",
    })
    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == "https://painel.example"
    assert method in response.headers["Access-Control-Allow-Methods"]


@pytest.mark.postgres
def test_create_list_update_delete_complete_dto_and_persistence(setores_api, session, tenants):
    client, headers, rh = setores_api
    response = client.post("/api/web/setores", headers=headers, json=cadastro())
    assert response.status_code == 201
    dto = response.json["setor"]
    assert dto == {
        **cadastro(), "id": dto["id"], "empresa_id": str(rh.empresa_id),
        "nome": "Filial", "endereco": "Rua do Trabalho, 100", "ativo": True,
        "limite_desvio_relogio_segundos": 120,
    }
    target = "/api/web/setores/" + dto["id"]
    rows = client.get("/api/web/setores", headers=headers).json["setores"]
    assert {row["id"] for row in rows} == {dto["id"], str(tenants[0].sector.id)}
    assert all(row["empresa_id"] == str(rh.empresa_id) for row in rows)
    assert all("latitude" in row and "raio_metros" in row for row in rows)
    response = client.put(target, headers=headers, json={
        "nome": "Filial Central", "raio_metros": 350.5,
        "latitude": -7.9, "longitude": -34.8, "endereco": None,
        "exige_selfie": False, "acao_fora_perimetro": "BLOQUEAR",
        "ignorar_localizacao": True,
    })
    assert response.status_code == 200
    assert response.json["setor"]["raio_metros"] == 350.5
    assert response.json["setor"]["ignorar_localizacao"] is True
    assert response.json["setor"]["limite_desvio_relogio_segundos"] == 120
    session.expire_all()
    stored = session.get(Setores, uuid.UUID(dto["id"]))
    assert stored.nome == "Filial Central" and stored.raio_metros == Decimal("350.50")
    assert stored.latitude_centro == Decimal("-7.9000000")
    assert client.delete(target, headers=headers).json == {"id": dto["id"], "removido": True}
    assert session.get(Setores, uuid.UUID(dto["id"])) is None
    assert client.delete(target, headers=headers).status_code == 404


@pytest.mark.postgres
@pytest.mark.parametrize("raio", [0, -1, 0.001, "0", "-100", "0.001"])
def test_radius_must_be_positive_after_database_precision(setores_api, session, raio):
    client, headers, _ = setores_api
    before = session.scalar(select(func.count()).select_from(Setores))
    response = client.post("/api/web/setores", headers=headers, json=cadastro(raio_metros=raio))
    assert response.status_code == 400
    assert response.json["erro"]["codigo"] == "RAIO_INVALIDO"
    assert session.scalar(select(func.count()).select_from(Setores)) == before


@pytest.mark.postgres
@pytest.mark.parametrize("dados", [
    {}, [], None, {"nome": "Local"}, cadastro(nome="  "), cadastro(nome="A" * 121),
    cadastro(endereco=123), cadastro(endereco="A" * 256), cadastro(latitude=91),
    cadastro(longitude=-181), cadastro(latitude="NaN"), cadastro(longitude="Infinity"),
    cadastro(latitude=None), cadastro(raio_metros=True), cadastro(raio_metros="a"),
    cadastro(raio_metros=10000000000), cadastro(exige_selfie="true"),
    cadastro(ignorar_localizacao=None), cadastro(acao_fora_perimetro="ACEITAR"),
    cadastro(acao_fora_perimetro=[]), cadastro(ativo="false"),
    cadastro(limite_desvio_relogio_segundos=-1), cadastro(limite_desvio_relogio_segundos=True),
    cadastro(empresa_id=str(uuid.uuid4())), cadastro(id=str(uuid.uuid4())),
])
def test_invalid_json_does_not_persist(setores_api, session, dados):
    client, headers, _ = setores_api
    before = session.scalar(select(func.count()).select_from(Setores))
    assert client.post("/api/web/setores", headers=headers, json=dados).status_code == 400
    assert session.scalar(select(func.count()).select_from(Setores)) == before


@pytest.mark.postgres
def test_invalid_update_rolls_back_all_fields(setores_api, session, tenants):
    client, headers, _ = setores_api
    row = tenants[0].sector
    target = "/api/web/setores/" + str(row.id)
    assert client.put(target, headers=headers, json={"nome": "Não salvar", "raio_metros": 0}).status_code == 400
    assert session.get(Setores, row.id).nome == "Sede"
    assert session.get(Setores, row.id).raio_metros == 100


@pytest.mark.postgres
def test_duplicate_name_is_scoped_and_update_preserves_original(setores_api, session, tenants):
    client, headers, _ = setores_api
    assert client.post("/api/web/setores", headers=headers, json=cadastro(nome="Sede")).status_code == 409
    # O mesmo nome existe na outra empresa, mas não interfere com um nome novo aqui.
    tenants[1].sector.nome = "Filial"
    session.commit()
    created = client.post("/api/web/setores", headers=headers, json=cadastro()).json["setor"]
    target = "/api/web/setores/" + created["id"]
    assert client.put(target, headers=headers, json={"nome": "Sede"}).status_code == 409
    assert session.get(Setores, uuid.UUID(created["id"])).nome == "Filial"


@pytest.mark.postgres
def test_foreign_sector_cannot_be_updated_or_removed(setores_api, session, tenants):
    client, headers, _ = setores_api
    target = "/api/web/setores/" + str(tenants[1].sector.id)
    assert client.put(target, headers=headers, json={"nome": "Invasão"}).status_code == 404
    assert client.delete(target, headers=headers).status_code == 404
    assert session.get(Setores, tenants[1].sector.id).nome == "Sede"


@pytest.mark.postgres
@pytest.mark.parametrize("encerrada", [False, True])
def test_any_assignment_blocks_delete_including_historical(setores_api, session, tenants, encerrada):
    client, headers, _ = setores_api
    assignment = tenants[0].assignment
    if encerrada:
        assignment.data_fim = date(2020, 12, 31)
        session.commit()
    response = client.delete("/api/web/setores/" + str(tenants[0].sector.id), headers=headers)
    assert response.status_code == 409
    assert response.json["erro"]["codigo"] == "SETOR_ALOCADO"
    assert "funcionários alocados" in response.json["erro"]["mensagem"]
    assert session.get(Setores, tenants[0].sector.id) is not None
    assert session.get(Alocacoes, assignment.id) is not None


@pytest.mark.postgres
def test_fk_blocks_delete_with_other_links_and_returns_clean_error(setores_api, session):
    client, headers, rh = setores_api
    created = client.post("/api/web/setores", headers=headers, json=cadastro()).json["setor"]
    target = uuid.UUID(created["id"])
    holiday = Feriados(empresa_id=rh.empresa_id, setor_id=target,
        data=date(2026, 12, 25), descricao="Natal")
    session.add(holiday)
    session.commit()
    response = client.delete("/api/web/setores/" + created["id"], headers=headers)
    assert response.status_code == 409
    assert response.json["erro"]["codigo"] == "SETOR_VINCULADO"
    assert "SQL" not in str(response.json)
    assert session.get(Setores, target) is not None
    assert session.get(Feriados, holiday.id) is not None


@pytest.mark.postgres
@pytest.mark.parametrize("role", [PapelUsuario.GESTOR, PapelUsuario.FUNCIONARIO, PapelUsuario.RELOGIO])
def test_rbac_uses_real_database_role_not_jwt_role(setores_api, session, tenants, role):
    client, headers, rh = setores_api
    rh.papel = role
    session.commit()
    for method, path in [
        ("GET", "/api/web/setores"), ("POST", "/api/web/setores"),
        ("PUT", "/api/web/setores/" + str(tenants[0].sector.id)),
        ("DELETE", "/api/web/setores/" + str(tenants[0].sector.id)),
    ]:
        assert client.open(path, method=method, headers=headers, json=cadastro()).status_code == 403


@pytest.mark.postgres
def test_superadmin_mismatched_tenant_inactive_company_and_expired_token(setores_api, session, tenants):
    client, headers, rh = setores_api
    superadmin = Usuarios(nome="Global", email="global@w02.example", senha_hash="hash",
        papel=PapelUsuario.SUPERADMIN, empresa_id=None)
    session.add(superadmin)
    session.commit()
    global_token = create_access_token(identity=str(superadmin.id), additional_claims={"empresa_id": None})
    assert client.get("/api/web/setores", headers={"Authorization": "Bearer " + global_token}).status_code == 403
    mismatch = create_access_token(identity=str(rh.id), additional_claims={"empresa_id": str(tenants[1].company.id)})
    assert client.post("/api/web/setores", headers={"Authorization": "Bearer " + mismatch}, json=cadastro()).status_code == 401
    expired = create_access_token(identity=str(rh.id), expires_delta=timedelta(seconds=-1),
        additional_claims={"empresa_id": str(rh.empresa_id)})
    assert client.get("/api/web/setores", headers={"Authorization": "Bearer " + expired}).status_code == 401
    tenants[0].company.ativo = False
    session.commit()
    assert client.get("/api/web/setores", headers=headers).status_code == 401


@pytest.mark.postgres
def test_coordinates_edges_and_database_precision_are_returned_consistently(setores_api):
    client, headers, _ = setores_api
    response = client.post("/api/web/setores", headers=headers, json=cadastro(
        latitude="-90", longitude="180", raio_metros="0.01"))
    assert response.status_code == 201
    dto = response.json["setor"]
    assert dto["latitude"] == -90 and dto["longitude"] == 180
    assert dto["raio_metros"] == 0.01
    response = client.put("/api/web/setores/" + dto["id"], headers=headers,
        json={"latitude": "-8.123456789", "raio_metros": "100.126"})
    assert response.json["setor"]["latitude"] == -8.1234568
    assert response.json["setor"]["raio_metros"] == 100.13
