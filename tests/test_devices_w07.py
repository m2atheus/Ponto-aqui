from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from datetime import timedelta
import uuid

from flask import g
from flask_jwt_extended import create_access_token
import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import db
from app.middleware.device_middleware import require_device_uuid
from app.models import Dispositivos, Empresas, PapelUsuario, Usuarios
from app.services.device_service import DeviceError, DeviceService
from test_mobile_w09 import concurrent_app


pytestmark = pytest.mark.postgres


def login(session, tenant, device_uuid=None):
    return DeviceService.registrar_login_pessoal(tenant.company.id, tenant.user.id,
        device_uuid or uuid.uuid4(), "Celular", session=session)


def test_auto_revocation_is_idempotent_and_does_not_touch_other_company(session, tenants):
    t, other = tenants
    first, _ = login(session, t)
    other_device, _ = login(session, other)
    second_uuid = uuid.uuid4()
    second, status = login(session, t, second_uuid)
    assert status == 200
    assert second["dispositivo"]["ultimo_acesso_em"] is not None
    assert not session.get(Dispositivos, uuid.UUID(first["dispositivo"]["id"])).ativo
    assert session.get(Dispositivos, uuid.UUID(other_device["dispositivo"]["id"])).ativo
    repeated, status = login(session, t, second_uuid)
    assert status == 200 and repeated["dispositivo"]["id"] == second["dispositivo"]["id"]
    assert session.scalar(select(func.count()).select_from(Dispositivos).where(
        Dispositivos.empresa_id == t.company.id, Dispositivos.usuario_id == t.user.id,
        Dispositivos.ativo.is_(True))) == 1


def test_duplicate_uuid_elsewhere_rolls_back_revocation(session, tenants):
    t, other = tenants
    first, _ = login(session, t)
    other_uuid = uuid.uuid4()
    login(session, other, other_uuid)
    assert login(session, t, other_uuid)[1] == 409
    assert session.get(Dispositivos, uuid.UUID(first["dispositivo"]["id"])).ativo


def test_clock_not_revoked_by_personal_login_and_cannot_be_reassigned(session, tenants):
    t = tenants[0]
    clock = Dispositivos(empresa_id=t.company.id, tipo="RELOGIO", setor_id=t.sector.id, nome="Relógio")
    session.add(clock)
    session.flush()
    clock_uuid, clock_id = clock.device_uuid, clock.id
    login(session, t)
    assert session.get(Dispositivos, clock_id).ativo
    assert login(session, t, clock_uuid)[1] == 403


def test_personal_login_rejects_inactive_company_and_non_employee(session, tenants):
    t = tenants[0]
    login(session, t)
    t.company.ativo = False
    session.commit()
    assert login(session, t)[1] == 403
    t.company.ativo = True
    t.user.papel = PapelUsuario.RH
    session.commit()
    assert login(session, t)[1] == 403


def test_middleware_real_jwt_binding_and_revoked_device(app, session, tenants, monkeypatch):
    t, other = tenants
    first, _ = login(session, t)
    device = first["dispositivo"]
    validator = DeviceService.validar_dispositivo
    monkeypatch.setattr(DeviceService, "validar_dispositivo", staticmethod(
        lambda **kwargs: validator(**kwargs, session=session)))
    @app.get("/test/device")
    @require_device_uuid
    def protected():
        return {"device_uuid": str(g.dispositivo.device_uuid)}
    with app.app_context():
        token = create_access_token(identity=str(t.user.id), additional_claims={
            "empresa_id": str(t.company.id), "dispositivo_id": device["id"]})
        foreign_token = create_access_token(identity=str(other.user.id), additional_claims={
            "empresa_id": str(other.company.id), "dispositivo_id": device["id"]})
        expired = create_access_token(identity=str(t.user.id), expires_delta=timedelta(seconds=-1))
    client = app.test_client()
    headers = {"Authorization": "Bearer " + token, "X-Device-UUID": device["device_uuid"]}
    assert client.get("/test/device", headers=headers).status_code == 200
    for header in [None, "invalid", str(uuid.uuid4())]:
        changed = dict(headers)
        if header is None:
            changed.pop("X-Device-UUID")
        else:
            changed["X-Device-UUID"] = header
        assert client.get("/test/device", headers=changed).status_code == 403
    assert client.get("/test/device", headers={**headers, "Authorization": "Bearer " + foreign_token}).status_code == 403
    assert client.get("/test/device").status_code == 401
    assert client.get("/test/device", headers={**headers, "Authorization": "Bearer " + expired}).status_code == 401
    second, _ = login(session, t)
    assert client.get("/test/device", headers=headers).status_code == 403
    # Token antigo não volta a funcionar ao trocar somente o UUID do header.
    assert client.get("/test/device", headers={**headers, "X-Device-UUID": second["dispositivo"]["device_uuid"]}).status_code == 403


def test_service_refuses_other_owner_and_clock_wrong_sector(session, tenants):
    t, other = tenants
    user = Usuarios(empresa_id=t.company.id, nome="Conta de setor", email="clock@example.com",
        senha_hash="hash", papel=PapelUsuario.USUARIO_SETOR)
    clock = Dispositivos(empresa_id=t.company.id, nome="Relógio", tipo="RELOGIO", setor_id=t.sector.id)
    session.add_all([user, clock])
    session.flush()
    values = dict(empresa_id=t.company.id, usuario_id=user.id, device_uuid=clock.device_uuid,
                  claims={"dispositivo_id": str(clock.id), "setor_id": str(t.sector.id)}, session=session)
    assert DeviceService.validar_dispositivo(**values).id == clock.id
    for claims in [{"dispositivo_id": str(clock.id)}, {"dispositivo_id": str(clock.id), "setor_id": str(other.sector.id)}]:
        with pytest.raises(DeviceError):
            DeviceService.validar_dispositivo(**{**values, "claims": claims})


def test_parallel_personal_logins_leave_exactly_one_active_device():
    with concurrent_app() as application:
        with application.app_context():
            company = Empresas(razao_social="Dispositivos", cnpj="88776655443322")
            db.session.add(company)
            db.session.flush()
            user = Usuarios(empresa_id=company.id, nome="Funcionário", email="parallel-device@example.com", senha_hash="hash")
            db.session.add(user)
            db.session.commit()
            company_id, user_id, engine = company.id, user.id, db.engine
        barrier = Barrier(4)
        def worker(number):
            with application.app_context(), Session(engine) as session:
                barrier.wait(timeout=10)
                return DeviceService.registrar_login_pessoal(company_id, user_id, uuid.uuid4(), f"Celular {number}", session=session)
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(worker, range(4)))
        assert all(status == 200 for _, status in results)
        with application.app_context():
            assert db.session.scalar(select(func.count()).select_from(Dispositivos).where(
                Dispositivos.empresa_id == company_id, Dispositivos.usuario_id == user_id)) == 4
            assert db.session.scalar(select(func.count()).select_from(Dispositivos).where(
                Dispositivos.empresa_id == company_id, Dispositivos.usuario_id == user_id,
                Dispositivos.ativo.is_(True))) == 1
