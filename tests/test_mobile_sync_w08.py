from datetime import date, datetime, time, timedelta, timezone
import uuid

from flask_jwt_extended import create_access_token
import pytest
from sqlalchemy import event
from sqlalchemy.exc import SQLAlchemyError

from app import db
from app.models import (
    Alocacoes, Dispositivos, Empresas, Escalas, Funcionarios, ModeloEscala,
    PapelUsuario, RegistrosPonto, Setores, TipoDispositivo, Turnos, Usuarios,
)
from app.services.device_service import DeviceService
from app.services.mobile_sync_service import MobileSyncService
import app.services.mobile_sync_service as sync_module
from test_mobile_w09 import concurrent_app


AGORA = datetime(2026, 10, 5, 15, 0, tzinfo=timezone.utc)
pytestmark = pytest.mark.postgres


@pytest.fixture(autouse=True)
def fixed_server_clock(monkeypatch):
    monkeypatch.setattr(sync_module, "_agora_utc", lambda: AGORA)


@pytest.fixture
def device(session, tenants):
    t = tenants[0]
    t.schedule.modelo = ModeloEscala.DIURNO
    session.add(Turnos(empresa_id=t.company.id, escala_id=t.schedule.id,
        hora_inicio=time(8), hora_fim=time(17), tempo_intervalo=60))
    item = Dispositivos(empresa_id=t.company.id, usuario_id=t.user.id, nome="Pessoal")
    session.add(item)
    session.flush()
    return item


def sync(session, t, device, *, claims=None):
    return MobileSyncService.sincronizar(t.company.id, t.user.id, device.device_uuid,
        claims or {"dispositivo_id": str(device.id)}, session=session)


def clock(session, t):
    account = Usuarios(empresa_id=t.company.id, nome="Conta do setor", email="sync-clock@example.com",
        senha_hash="hash", papel=PapelUsuario.USUARIO_SETOR)
    device = Dispositivos(empresa_id=t.company.id, setor_id=t.sector.id,
        tipo=TipoDispositivo.RELOGIO, nome="Relógio")
    session.add_all([account, device])
    session.flush()
    return account, device


def clock_sync(session, t, account, device):
    return MobileSyncService.sincronizar(t.company.id, account.id, device.device_uuid,
        {"dispositivo_id": str(device.id), "setor_id": str(t.sector.id)}, session=session)


def test_personal_dto_timestamp_policies_and_shift(session, tenants, device):
    t = tenants[0]
    result, status = sync(session, t, device)
    assert status == 200 and result["status"] == "OK"
    assert result["modo_operacao"] == "PESSOAL"
    assert result["server_timestamp"] == "2026-10-05T15:00:00.000000Z"
    assert result["data_referencia"] == "2026-10-05"
    assert result["funcionario"]["id"] == str(t.employee.id)
    assert result["setor"]["latitude"] == -8.0
    assert result["setor"]["politicas"] == {"exige_selfie": False, "acao_fora_perimetro": "BLOQUEAR",
        "ignorar_localizacao": False, "limite_desvio_relogio_segundos": 120}
    assert result["escala"]["turnos"][0] == {"hora_inicio": "08:00", "hora_fim": "17:00",
        "tempo_intervalo": 60, "fim_dia_seguinte": False, "dias_semana": [1, 2, 3, 4, 5]}
    assert result["marcacoes_recentes"] == []
    assert "senha_hash" not in str(result) and "email" not in str(result)


def test_personal_without_allocation_is_200_with_nulls(session, tenants, device):
    t = tenants[0]
    t.assignment.data_fim = date(2026, 10, 4)
    session.flush()
    result, status = sync(session, t, device)
    assert status == 200 and result["status"] == "SEM_ALOCACAO"
    assert result["setor"] is None and result["escala"] is None
    assert result["alocacoes"] == [] and result["mensagem_status"]
    assert result["funcionario"]["id"] == str(t.employee.id)


def test_today_uses_company_timezone_and_dates_are_inclusive(session, tenants, device, monkeypatch):
    t = tenants[0]
    monkeypatch.setattr(sync_module, "_agora_utc", lambda: datetime(2026, 10, 5, 2, tzinfo=timezone.utc))
    t.assignment.data_fim = date(2026, 10, 4)
    session.flush()
    result, status = sync(session, t, device)
    assert status == 200 and result["data_referencia"] == "2026-10-04"
    assert result["setor"] is not None and result["status"] == "OK"
    t.assignment.data_inicio = date(2026, 10, 4)
    session.flush()
    assert sync(session, t, device)[0]["status"] == "OK"


def test_null_scale_and_legacy_scale_are_explicit(session, tenants, device):
    t = tenants[0]
    t.assignment.escala_id = None
    session.flush()
    result, status = sync(session, t, device)
    assert status == 200 and result["status"] == "SEM_ESCALA" and result["escala"] is None
    t.assignment.escala_id = t.schedule.id
    t.schedule.modelo = ModeloEscala.LEGADO
    # Existing structured turns are valid even when a legacy label is retained.
    session.flush()
    assert sync(session, t, device)[0]["escala"]["modelo"] == "Legado"


def test_personal_preserves_multiple_sectors_and_scales(session, tenants, device):
    t = tenants[0]
    second_sector = Setores(empresa_id=t.company.id, nome="Segundo", latitude_centro=1, longitude_centro=2, raio_metros=200)
    session.add(second_sector)
    session.flush()
    session.add(Alocacoes(empresa_id=t.company.id, funcionario_id=t.employee.id,
        setor_id=second_sector.id, escala_id=t.schedule.id, data_inicio=date(2026, 10, 5)))
    session.flush()
    result, status = sync(session, t, device)
    assert status == 200 and result["status"] == "MULTIPLAS_ALOCACOES"
    assert result["setor"] is None and result["escala"] is None
    assert {a["setor"]["id"] for a in result["alocacoes"]} == {str(t.sector.id), str(second_sector.id)}


def test_personal_without_employee_record_is_informative(session, tenants):
    t = tenants[0]
    user = Usuarios(empresa_id=t.company.id, nome="Sem cadastro", email="no-employee@example.com", senha_hash="hash")
    session.add(user)
    session.flush()
    device = Dispositivos(empresa_id=t.company.id, usuario_id=user.id, nome="Celular")
    session.add(device)
    session.flush()
    result, status = MobileSyncService.sincronizar(t.company.id, user.id, device.device_uuid,
        {"dispositivo_id": str(device.id)}, session=session)
    assert status == 200 and result["status"] == "SEM_FUNCIONARIO" and result["funcionario"] is None


def test_recent_points_are_limited_sorted_by_receipt_and_tenant_isolated(session, tenants, device, point_values):
    t = tenants[0]
    for i in range(25):
        session.add(RegistrosPonto(**{**point_values, "evento_cliente_id": uuid.uuid4(),
            "recebido_em": AGORA - timedelta(seconds=i), "ocorrido_em": AGORA + timedelta(days=365)}))
    session.add(RegistrosPonto(**{**point_values, "evento_cliente_id": uuid.uuid4(), "recebido_em": AGORA - timedelta(days=8)}))
    other = tenants[1]
    session.add(RegistrosPonto(**{**point_values, "empresa_id": other.company.id, "usuario_id": other.user.id,
        "enviado_por_id": other.user.id, "setor_id": other.sector.id, "alocacao_id": other.assignment.id,
        "evento_cliente_id": uuid.uuid4(), "recebido_em": AGORA}))
    session.flush()
    points = sync(session, t, device)[0]["marcacoes_recentes"]
    assert len(points) == 20
    assert points[0]["recebido_em"] == "2026-10-05T15:00:00.000000Z"
    assert points[-1]["recebido_em"] == "2026-10-05T14:59:41.000000Z"
    assert all(p["ocorrido_em"].startswith("2027-") for p in points)
    assert "payload_hash" not in str(points) and "latitude" not in str(points)


def test_clock_employees_include_no_login_and_catalog_scales_are_deduplicated(session, tenants, device):
    t = tenants[0]
    account, clock_device = clock(session, t)
    employee = Funcionarios(empresa_id=t.company.id, nome="Sem conta", matricula="offline-2")
    session.add(employee)
    session.flush()
    session.add(Alocacoes(empresa_id=t.company.id, funcionario_id=employee.id,
        setor_id=t.sector.id, escala_id=t.schedule.id, data_inicio=date(2026, 10, 5)))
    session.flush()
    result, status = clock_sync(session, t, account, clock_device)
    assert status == 200 and result["modo_operacao"] == "RELOGIO"
    assert len(result["funcionarios"]) == 2 and len(result["escalas"]) == 1
    assert {p["id"] for p in result["funcionarios"]} == {str(t.employee.id), str(employee.id)}
    assert next(p for p in result["funcionarios"] if p["id"] == str(employee.id))["usuario_id"] is None
    assert all(p["alocacoes"][0]["escala_id"] == str(t.schedule.id) for p in result["funcionarios"])
    assert "marcacoes_recentes" not in result


def test_clock_excludes_other_sectors_future_ended_and_inactive_employees(session, tenants, device):
    t = tenants[0]
    account, clock_device = clock(session, t)
    for index, (start, end, active, own_sector) in enumerate([
        (date(2026, 10, 6), None, True, True),
        (date(2026, 10, 1), date(2026, 10, 4), True, True),
        (date(2026, 10, 1), None, False, True),
        (date(2026, 10, 1), None, True, False),
    ]):
        employee = Funcionarios(empresa_id=t.company.id, nome=f"Excluído {index}", matricula=f"excluded-{index}", ativo=active)
        sector = t.sector
        if not own_sector:
            sector = Setores(empresa_id=t.company.id, nome="Outro setor", latitude_centro=0, longitude_centro=0, raio_metros=100)
            session.add(sector)
        session.add(employee)
        session.flush()
        session.add(Alocacoes(empresa_id=t.company.id, funcionario_id=employee.id, setor_id=sector.id,
            escala_id=t.schedule.id, data_inicio=start, data_fim=end))
    session.flush()
    result, status = clock_sync(session, t, account, clock_device)
    assert status == 200 and [p["id"] for p in result["funcionarios"]] == [str(t.employee.id)]


def test_empty_clock_is_200_inactive_sector_is_403(session, tenants, device):
    t = tenants[0]
    account, clock_device = clock(session, t)
    t.assignment.data_fim = date(2026, 10, 4)
    session.flush()
    result, status = clock_sync(session, t, account, clock_device)
    assert status == 200 and result["status"] == "SEM_FUNCIONARIOS" and result["funcionarios"] == []
    t.sector.ativo = False
    session.flush()
    assert clock_sync(session, t, account, clock_device)[1] == 403


def test_sync_query_count_does_not_grow_with_employee_count(session, tenants, device):
    t = tenants[0]
    account, clock_device = clock(session, t)
    count = []
    def query_count(conn, cursor, statement, parameters, context, executemany):
        if statement.lstrip().startswith("SELECT"):
            count.append(statement)
    connection = session.connection()
    event.listen(connection, "before_cursor_execute", query_count)
    try:
        clock_sync(session, t, account, clock_device)
        baseline = len(count)
        for i in range(10):
            employee = Funcionarios(empresa_id=t.company.id, nome=f"Funcionário {i}", matricula=f"bulk-{i}")
            session.add(employee)
            session.flush()
            session.add(Alocacoes(empresa_id=t.company.id, funcionario_id=employee.id,
                setor_id=t.sector.id, escala_id=t.schedule.id, data_inicio=date(2026, 10, 5)))
        session.flush()
        count.clear()
        result, status = clock_sync(session, t, account, clock_device)
        assert status == 200 and len(result["funcionarios"]) == 11
        assert len(count) == baseline
    finally:
        event.remove(connection, "before_cursor_execute", query_count)


@pytest.mark.parametrize("invalid_zone", ["Invalid/Zone", "../Invalid"])
def test_invalid_timezone_and_database_failure_return_503(session, tenants, device, monkeypatch, invalid_zone):
    t = tenants[0]
    t.company.fuso_horario = invalid_zone
    session.flush()
    assert sync(session, t, device)[1] == 503
    monkeypatch.setattr(DeviceService, "validar_dispositivo", lambda *a, **kw: (_ for _ in ()).throw(SQLAlchemyError()))
    result, status = sync(session, t, device)
    assert status == 503 and result["erro"]["codigo"] == "SYNC_INDISPONIVEL"


def test_real_http_endpoint_requires_both_middlewares_and_returns_timestamp_header():
    with concurrent_app() as application, application.app_context():
        company = Empresas(razao_social="Sync HTTP", cnpj="55667788990011")
        db.session.add(company)
        db.session.flush()
        user = Usuarios(empresa_id=company.id, nome="Funcionário HTTP", email="sync-http@example.com", senha_hash="hash")
        db.session.add(user)
        db.session.flush()
        employee = Funcionarios(empresa_id=company.id, usuario_id=user.id, nome=user.nome, matricula="1")
        device = Dispositivos(empresa_id=company.id, usuario_id=user.id, nome="Pessoal")
        db.session.add_all([employee, device])
        db.session.commit()
        token = create_access_token(identity=str(user.id), additional_claims={
            "empresa_id": str(company.id), "dispositivo_id": str(device.id)})
        expired = create_access_token(identity=str(user.id), expires_delta=timedelta(seconds=-1))
        headers = {"Authorization": "Bearer " + token, "X-Device-UUID": str(device.device_uuid)}
        client = application.test_client()
        assert client.get("/api/v1/mobile/sync").status_code == 401
        assert client.get("/api/v1/mobile/sync", headers={**headers, "Authorization": "Bearer " + expired}).status_code == 401
        assert client.get("/api/v1/mobile/sync", headers={"Authorization": "Bearer " + token}).status_code == 403
        assert client.get("/api/v1/mobile/sync", headers={**headers, "X-Device-UUID": str(uuid.uuid4())}).status_code == 403
        response = client.get("/api/v1/mobile/sync", headers=headers)
        assert response.status_code == 200 and response.json["status"] == "SEM_ALOCACAO"
        assert response.headers["X-Server-Timestamp"] == response.json["server_timestamp"]
        assert response.headers["Cache-Control"] == "private, no-store"
        assert "-03:00" not in response.json["server_timestamp"]
        device.ativo = False
        db.session.commit()
        assert client.get("/api/v1/mobile/sync", headers=headers).status_code == 403


def test_clock_http_endpoint_is_scoped_to_sector_and_company():
    with concurrent_app() as application, application.app_context():
        company = Empresas(razao_social="Relógio HTTP", cnpj="22334455667788")
        other = Empresas(razao_social="Outra HTTP", cnpj="22334455667789")
        db.session.add_all([company, other])
        db.session.flush()
        account = Usuarios(empresa_id=company.id, nome="Setor", email="sector-http@example.com",
            papel=PapelUsuario.USUARIO_SETOR, senha_hash="hash")
        sector = Setores(empresa_id=company.id, nome="Setor do relógio", latitude_centro=0, longitude_centro=0, raio_metros=100)
        foreign_sector = Setores(empresa_id=other.id, nome="Setor externo", latitude_centro=0, longitude_centro=0, raio_metros=100)
        employee = Funcionarios(empresa_id=company.id, nome="Sem login", matricula="clock-http-1")
        db.session.add_all([account, sector, foreign_sector, employee])
        db.session.flush()
        device = Dispositivos(empresa_id=company.id, tipo=TipoDispositivo.RELOGIO, setor_id=sector.id, nome="Relógio")
        db.session.add_all([device, Alocacoes(empresa_id=company.id, funcionario_id=employee.id,
            setor_id=sector.id, data_inicio=date(2026, 10, 5))])
        db.session.commit()
        def headers(**changes):
            claims = {"empresa_id": str(company.id), "dispositivo_id": str(device.id), "setor_id": str(sector.id)}
            claims.update(changes)
            token = create_access_token(identity=str(account.id), additional_claims=claims)
            return {"Authorization": "Bearer " + token, "X-Device-UUID": str(device.device_uuid)}
        client = application.test_client()
        response = client.get("/api/v1/mobile/sync", headers=headers())
        assert response.status_code == 200 and response.json["modo_operacao"] == "RELOGIO"
        assert response.json["setor"]["id"] == str(sector.id)
        assert [f["id"] for f in response.json["funcionarios"]] == [str(employee.id)]
        assert response.json["funcionarios"][0]["alocacoes"][0]["escala_id"] is None
        assert client.get("/api/v1/mobile/sync", headers=headers(setor_id=str(foreign_sector.id))).status_code == 403
        assert client.get("/api/v1/mobile/sync", headers=headers(empresa_id=str(other.id))).status_code == 403
        assert client.get("/api/v1/mobile/sync", headers=headers(dispositivo_id=None)).status_code == 403


def test_http_cors_accepts_device_header_and_exposes_timestamp(app):
    response = app.test_client().options("/api/v1/mobile/sync", headers={
        "Origin": "https://painel.example", "Access-Control-Request-Method": "GET",
        "Access-Control-Request-Headers": "Authorization, X-Device-UUID",
    })
    assert response.status_code == 200
    assert "X-Device-UUID" in response.headers["Access-Control-Allow-Headers"]
    assert "X-Server-Timestamp" in response.headers["Access-Control-Expose-Headers"]
