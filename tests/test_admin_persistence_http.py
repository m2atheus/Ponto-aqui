import io
from datetime import date
from types import SimpleNamespace

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import select

from app import db
from app.models import AnexosAfastamento, Afastamentos, Escalas, Feriados, PapelUsuario, Usuarios


@pytest.fixture
def admin_http(pg_app, session, tenants, monkeypatch):
    own, foreign = tenants
    rh = Usuarios(empresa_id=own.company.id, nome="RH", email="rh-http@example.com",
        papel=PapelUsuario.RH, senha_hash="hash")
    session.add(rh)
    session.commit()
    # Usa a transação isolada da fixture também dentro do transporte Flask.
    monkeypatch.setattr(session, "remove", lambda: None, raising=False)
    monkeypatch.setattr(db, "session", session)
    token = create_access_token(identity=str(rh.id), additional_claims={"empresa_id": str(own.company.id)})
    return SimpleNamespace(client=pg_app.test_client(), headers={"Authorization": "Bearer " + token},
        own=own, foreign=foreign, rh=rh)


@pytest.mark.parametrize("path", ["/feriados", "/afastamentos", "/equipe", "/escalas", "/relatorios/espelho", "/dashboard"])
def test_new_routes_require_jwt(app, path):
    assert app.test_client().get("/api/web" + path).status_code == 401


def test_holiday_http_crud_survives_reload_and_stays_in_company(admin_http, session):
    c = admin_http
    created = c.client.post("/api/web/feriados", headers=c.headers,
        json={"data": "2026-10-12", "descricao": "Feriado real", "setor_id": None})
    assert created.status_code == 201, created.json
    fid = created.json["feriado"]["id"]
    assert session.scalar(select(Feriados).where(Feriados.descricao == "Feriado real")).data == date(2026, 10, 12)
    assert c.client.get("/api/web/feriados", headers=c.headers).json["feriados"][0]["id"] == fid
    edited = c.client.put(f"/api/web/feriados/{fid}", headers=c.headers,
        json={"descricao": "Alterado", "setor_id": str(c.own.sector.id)})
    assert edited.status_code == 200 and edited.json["feriado"]["descricao"] == "Alterado"
    assert c.client.post("/api/web/feriados", headers=c.headers, json={"data": "2026-10-13",
        "descricao": "Inválido", "setor_id": str(c.foreign.sector.id)}).status_code == 404
    assert c.client.delete(f"/api/web/feriados/{fid}", headers=c.headers).status_code == 200
    assert c.client.get("/api/web/feriados", headers=c.headers).json == {"feriados": []}


def leave_payload(ctx):
    return {"funcionario_id": str(ctx.own.employee.id), "tipo": "ATESTADO", "data_inicio": "2026-10-05", "data_fim": "2026-10-07"}


def test_leave_and_private_upload_are_atomic_and_removable(admin_http, session):
    c = admin_http
    pdf = b"%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n"
    created = c.client.post("/api/web/afastamentos", headers=c.headers,
        data={**leave_payload(c), "anexo": (io.BytesIO(pdf), "atestado.pdf")})
    assert created.status_code == 201, created.json
    aid = created.json["afastamento"]["id"]
    assert created.json["afastamento"]["anexo_url"].endswith(f"/{aid}/anexo")
    assert session.scalar(select(AnexosAfastamento)).conteudo == pdf
    download = c.client.get(f"/api/web/afastamentos/{aid}/anexo", headers=c.headers)
    assert download.status_code == 200 and download.data == pdf
    assert download.headers["Cache-Control"] == "private, no-store"
    assert "attachment" in download.headers["Content-Disposition"]
    assert c.client.get(f"/api/web/afastamentos/{aid}/anexo").status_code == 401
    other_token = create_access_token(identity=str(c.foreign.user.id), additional_claims={"empresa_id": str(c.foreign.company.id)})
    c.foreign.user.papel = PapelUsuario.RH
    session.commit()
    assert c.client.get(f"/api/web/afastamentos/{aid}/anexo", headers={"Authorization": "Bearer " + other_token}).status_code == 404
    overlap = c.client.post("/api/web/afastamentos", headers=c.headers, json=leave_payload(c))
    assert overlap.status_code == 400 and overlap.json["erro"]["codigo"] == "AFASTAMENTO_SOBREPOSTO"
    assert c.client.put(f"/api/web/afastamentos/{aid}", headers=c.headers, json={"anexo_url": None}).status_code == 200
    assert session.scalar(select(AnexosAfastamento)) is None
    assert c.client.delete(f"/api/web/afastamentos/{aid}", headers=c.headers).status_code == 200
    assert session.scalar(select(Afastamentos)) is None


def test_invalid_upload_rolls_back_leave(admin_http, session):
    c = admin_http
    response = c.client.post("/api/web/afastamentos", headers=c.headers,
        data={**leave_payload(c), "anexo": (io.BytesIO(b"<script>bad</script>"), "fake.pdf")})
    assert response.status_code == 400, response.json
    assert session.scalar(select(Afastamentos)) is None
    assert session.scalar(select(AnexosAfastamento)) is None


def test_oversized_upload_returns_413_without_partial_leave(admin_http, session):
    c = admin_http
    response = c.client.post("/api/web/afastamentos", headers=c.headers,
        data={**leave_payload(c), "anexo": (io.BytesIO(b"x" * (10 * 1024 * 1024 + 1)), "grande.pdf")})
    assert response.status_code == 413
    assert response.json["erro"]["codigo"] == "ANEXO_TAMANHO"
    assert session.scalar(select(Afastamentos)) is None
    assert session.scalar(select(AnexosAfastamento)) is None


@pytest.mark.parametrize("modelo,inicio,fim,virada", [
    ("5x2", "08:00", "17:00", False), ("Diurno", "08:00", "12:00", False),
    ("12x36", "19:00", "07:00", False), ("24x72", "07:00", "07:00", True)])
def test_structured_schedules_crud(admin_http, session, modelo, inicio, fim, virada):
    c = admin_http
    payload = {"nome": "Escala " + modelo, "modelo": modelo, "data_referencia": "2026-10-01",
        "turnos": [{"hora_inicio": inicio, "hora_fim": fim, "tempo_intervalo": 0,
            "dias_semana": [1,2,3,4,5], "fim_dia_seguinte": virada}]}
    created = c.client.post("/api/web/escalas", headers=c.headers, json=payload)
    assert created.status_code == 201, created.json
    eid = created.json["escala"]["id"]
    assert any(e["id"] == eid for e in c.client.get("/api/web/escalas", headers=c.headers).json["escalas"])
    assert c.client.post("/api/web/escalas", headers=c.headers, json={**payload, "nome": payload["nome"].lower()}).status_code == 409
    assert c.client.put(f"/api/web/escalas/{eid}", headers=c.headers, json={"ativo": False}).status_code == 200
    assert c.client.delete(f"/api/web/escalas/{eid}", headers=c.headers).status_code == 200
    assert c.client.delete(f"/api/web/escalas/{c.foreign.schedule.id}", headers=c.headers).status_code == 404


def test_schedule_history_cannot_be_rewritten_or_removed(admin_http, session):
    c = admin_http
    sid = str(c.own.schedule.id)
    original = c.own.assignment.id
    assert c.client.delete(f"/api/web/escalas/{sid}", headers=c.headers).status_code == 409
    assert c.client.put(f"/api/web/escalas/{sid}", headers=c.headers, json={"ativo": False}).status_code == 200
    assert c.client.put(f"/api/web/escalas/{sid}", headers=c.headers, json={"modelo": "Diurno"}).status_code == 409
    assert c.own.assignment.id == original


def test_team_dashboard_report_read_database_and_role_boundaries(admin_http, session):
    c = admin_http
    assert c.client.get("/api/web/dashboard", headers=c.headers).json["indicadores"]["funcionarios"] == 1
    team = c.client.get("/api/web/equipe", headers=c.headers)
    assert team.status_code == 200 and len(team.json["funcionarios"]) == 1
    assert team.json["historico"][0]["id"] == str(c.own.assignment.id)
    report = c.client.get("/api/web/relatorios/espelho", headers=c.headers,
        query_string={"funcionario_id": str(c.own.employee.id), "ano": "2026", "mes": "10"})
    assert report.status_code == 200 and len(report.json["espelho"]["dias"]) == 31
    assert c.client.get("/api/web/relatorios/espelho", headers=c.headers,
        query_string={"funcionario_id": str(c.foreign.employee.id), "ano": "2026", "mes": "10"}).status_code == 404
    c.rh.papel = PapelUsuario.GESTOR
    session.commit()
    assert c.client.get("/api/web/equipe", headers=c.headers).status_code == 200
    assert c.client.get("/api/web/afastamentos", headers=c.headers).status_code == 200
    assert c.client.post("/api/web/feriados", headers=c.headers, json={}).status_code == 403
    assert c.client.delete(f"/api/web/escalas/{c.own.schedule.id}", headers=c.headers).status_code == 403
    assert c.client.get("/api/web/relatorios/espelho", headers=c.headers).status_code == 400
    assert c.client.get("/api/web/relatorios/espelho", headers=c.headers,
        query_string={"funcionario_id": str(c.own.employee.id), "ano": "2026", "mes": "10"}).status_code == 200
    assert c.client.get("/api/web/relatorios/espelho", headers=c.headers,
        query_string={"funcionario_id": str(c.foreign.employee.id), "ano": "2026", "mes": "10"}).status_code == 404
