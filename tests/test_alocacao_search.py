import pytest
from flask_jwt_extended import create_access_token

from app import db
from app.models import Funcionarios, PapelUsuario, Setores, Usuarios
from app.services.alocacao_service import AlocacaoService
from app.services.funcionario_service import FuncionarioService
from app.services.setor_service import SetorService


@pytest.fixture
def search_context(session, tenants):
    own, foreign = tenants
    rh = Usuarios(empresa_id=own.company.id, nome="RH", email="rh-busca-alocacao@example.com",
                  papel=PapelUsuario.RH, senha_hash="teste")
    session.add(rh)
    for i in range(25):
        session.add(Funcionarios(empresa_id=own.company.id, nome=f"A Inativo {i:02}", matricula=f"INATIVO-{i}", ativo=False))
        session.add(Funcionarios(empresa_id=own.company.id, nome=f"Pessoa {i:02}", matricula=f"ATIVO-{i:02}"))
        session.add(Setores(empresa_id=own.company.id, nome=f"Filial {i:02}", latitude_centro=0, longitude_centro=0, raio_metros=100))
    session.add(Setores(empresa_id=own.company.id, nome="Filial Desativada", ativo=False, latitude_centro=0, longitude_centro=0, raio_metros=100))
    session.add(Setores(empresa_id=foreign.company.id, nome="Filial Outra Empresa", latitude_centro=0, longitude_centro=0, raio_metros=100))
    session.commit()
    return rh, own, foreign


def test_initial_and_filtered_sectors_are_limited_active_and_tenant_scoped(session, search_context):
    rh, own, foreign = search_context
    result, status = SetorService.buscar(rh.id, own.company.id, session=session)
    rows = result["setores"]
    assert status == 200 and len(rows) == 20
    assert all(row["empresa_id"] == str(own.company.id) and row["ativo"] for row in rows)
    assert [row["nome"] for row in rows] == sorted(row["nome"] for row in rows)
    result, status = SetorService.buscar(rh.id, own.company.id, "fILiAl 24", session=session)
    assert status == 200 and [r["nome"] for r in result["setores"]] == ["Filial 24"]
    assert SetorService.buscar(rh.id, own.company.id, "%", session=session)[0]["setores"] == []
    assert SetorService.buscar(rh.id, foreign.company.id, session=session)[1] == 401


def test_employee_active_filter_happens_before_limit(session, search_context):
    rh, own, _ = search_context
    result, status = FuncionarioService.buscar(rh.id, own.company.id, ativo="true", session=session)
    assert status == 200 and len(result["funcionarios"]) == 20
    assert all(row["ativo"] for row in result["funcionarios"])
    result, status = FuncionarioService.buscar(rh.id, own.company.id, q="ATIVO-24", ativo="true", session=session)
    assert status == 200 and len(result["funcionarios"]) == 1
    assert FuncionarioService.buscar(rh.id, own.company.id, ativo="invalid", session=session)[1] == 400


def test_allocation_list_returns_only_referenced_people_and_sectors(session, search_context):
    rh, own, _ = search_context
    payload, status = AlocacaoService.listar(rh.id, own.company.id, session=session)
    assert status == 200 and len(payload["alocacoes"]) == 1
    assert [row["id"] for row in payload["funcionarios"]] == [str(own.employee.id)]
    assert [row["id"] for row in payload["setores"]] == [str(own.sector.id)]


def test_sector_search_route_requires_auth_and_ignores_caller_tenant(pg_app, session, search_context, monkeypatch):
    rh, own, foreign = search_context
    monkeypatch.setattr(session, "remove", lambda: None, raising=False)
    monkeypatch.setattr(db, "session", session)
    token = create_access_token(identity=str(rh.id), additional_claims={"empresa_id": str(own.company.id)})
    client = pg_app.test_client()
    assert client.get("/api/web/setores/busca").status_code == 401
    response = client.get("/api/web/setores/busca", query_string={"q": "", "empresa_id": str(foreign.company.id)},
                          headers={"Authorization": "Bearer " + token})
    assert response.status_code == 200 and len(response.json["setores"]) == 20
    assert all(row["empresa_id"] == str(own.company.id) for row in response.json["setores"])
