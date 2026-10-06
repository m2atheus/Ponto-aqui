from datetime import date, time
import uuid

import pytest
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from flask_migrate import upgrade

from app import db
from app.models import Afastamento, Dispositivo, Escala, Feriado, Turno
from conftest import MIGRATIONS
from test_mobile_w09 import concurrent_app


pytestmark = pytest.mark.postgres


def rejected(session, record, code):
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(record)
            session.flush()
    assert error.value.orig.pgcode == code


@pytest.mark.parametrize("model,tipo,reference", [
    ("24x72", "Ciclica", date(2026, 1, 1)),
    ("12x36", "Ciclica", date(2026, 1, 1)),
    ("Diurno", "Semanal", None), ("5x2", "Semanal", None),
])
def test_schedule_models(session, tenants, model, tipo, reference):
    schedule = Escala(empresa_id=tenants[0].company.id, nome=model, modelo=model, tipo=tipo,
                      data_referencia=reference, carga_semanal_minutos=2400, regras={})
    session.add(schedule)
    session.flush()
    session.refresh(schedule)
    assert schedule.modelo.value == model


@pytest.mark.parametrize("model,tipo,reference", [
    ("24x72", "Ciclica", None), ("12x36", "Semanal", date(2026, 1, 1)),
    ("5x2", "Ciclica", None),
])
def test_schedule_requires_model_and_reference_consistency(session, tenants, model, tipo, reference):
    rejected(session, Escala(empresa_id=tenants[0].company.id, nome=model, modelo=model,
        tipo=tipo, data_referencia=reference, carga_semanal_minutos=0, regras={}), "23514")


def shift(tenant, **changes):
    values = dict(empresa_id=tenant.company.id, escala_id=tenant.schedule.id,
                  hora_inicio=time(19), hora_fim=time(7))
    values.update(changes)
    return Turno(**values)


def test_multiple_day_shifts_and_24h_shift(session, tenants):
    tenant = tenants[0]
    session.add_all([shift(tenant, hora_inicio=time(8), hora_fim=time(12), ordem=0),
                     shift(tenant, hora_inicio=time(13), hora_fim=time(17), ordem=1)])
    session.flush()
    assert [t.ordem for t in tenant.schedule.turnos] == [0, 1]
    session.add(shift(tenant, hora_inicio=time(8), hora_fim=time(8), ordem=2, fim_dia_seguinte=True))
    session.flush()


@pytest.mark.parametrize("changes", [
    {"tempo_intervalo": -1}, {"tempo_intervalo": 720}, {"ordem": -1},
    {"hora_fim": time(19)}, {"hora_inicio": time(8), "hora_fim": time(17), "fim_dia_seguinte": True},
    {"hora_inicio": time(19, 0, 1)}, {"dias_semana": [0]}, {"dias_semana": [8]},
    {"dias_semana": []}, {"dias_semana": [1, None]},
])
def test_shift_constraints(session, tenants, changes):
    rejected(session, shift(tenants[0], **changes), "23514")


def test_new_models_cannot_link_foreign_tenant(session, tenants):
    own, foreign = tenants
    rejected(session, shift(own, escala_id=foreign.schedule.id), "23503")
    rejected(session, Feriado(empresa_id=own.company.id, setor_id=foreign.sector.id,
        data=date(2026, 1, 1), descricao="Ano novo"), "23503")
    rejected(session, Afastamento(empresa_id=own.company.id, funcionario_id=foreign.employee.id,
        tipo="FERIAS", data_inicio=date(2026, 1, 1), data_fim=date(2026, 1, 10)), "23503")
    rejected(session, Dispositivo(empresa_id=own.company.id, setor_id=foreign.sector.id,
        tipo="RELOGIO", nome="Relógio"), "23503")


def test_holidays_company_and_sector_with_duplicate_protection(session, tenants):
    t = tenants[0]
    values = dict(empresa_id=t.company.id, data=date(2026, 1, 1), descricao="Ano novo")
    session.add_all([Feriado(**values), Feriado(**values, setor_id=t.sector.id)])
    session.flush()
    rejected(session, Feriado(**values), "23505")
    rejected(session, Feriado(**values, setor_id=t.sector.id), "23505")


def test_leave_inclusive_overlap_and_next_day(session, tenants):
    t = tenants[0]
    values = dict(empresa_id=t.company.id, funcionario_id=t.employee.id, tipo="FERIAS")
    session.add(Afastamento(**values, data_inicio=date(2026, 1, 1), data_fim=date(2026, 1, 10)))
    session.flush()
    for start, end in [(date(2026, 1, 10), date(2026, 1, 15)),
                       (date(2025, 12, 1), date(2026, 1, 30)),
                       (date(2026, 1, 5), date(2026, 1, 6))]:
        rejected(session, Afastamento(**values, data_inicio=start, data_fim=end), "23P01")
    session.add(Afastamento(**values, data_inicio=date(2026, 1, 11), data_fim=date(2026, 1, 12)))
    session.flush()
    rejected(session, Afastamento(**values, data_inicio=date(2026, 2, 2), data_fim=date(2026, 2, 1)), "23514")


def test_device_uuid_globally_unique_and_deactivation_keeps_row(session, tenants):
    t, other = tenants
    device_uuid = uuid.uuid4()
    device = Dispositivo(empresa_id=t.company.id, usuario_id=t.user.id, nome="Celular", device_uuid=device_uuid)
    clock = Dispositivo(empresa_id=t.company.id, setor_id=t.sector.id, tipo="RELOGIO", nome="Relógio")
    session.add_all([device, clock])
    session.flush()
    rejected(session, Dispositivo(empresa_id=other.company.id, usuario_id=other.user.id,
        nome="Duplicado", device_uuid=device_uuid), "23505")
    device.ativo = False
    session.flush()
    assert session.scalar(select(Dispositivo).where(Dispositivo.device_uuid == device_uuid)).id == device.id


@pytest.mark.parametrize("kind,owner,sector", [
    ("PESSOAL", False, False), ("PESSOAL", True, True),
    ("RELOGIO", True, True), ("RELOGIO", False, False),
])
def test_device_requires_exclusive_binding(session, tenants, kind, owner, sector):
    t = tenants[0]
    rejected(session, Dispositivo(empresa_id=t.company.id, nome="Inválido", tipo=kind,
        usuario_id=t.user.id if owner else None, setor_id=t.sector.id if sector else None), "23514")


def test_migration_preserves_existing_device_and_legacy_schedule():
    with concurrent_app(revision="0003") as application, application.app_context():
        company, user, device, schedule = [uuid.uuid4() for _ in range(4)]
        db.session.execute(text("INSERT INTO empresas (id,razao_social,cnpj) VALUES (:id,'Legado','98765432100000')"), {"id": company})
        db.session.execute(text("INSERT INTO usuarios (id,empresa_id,nome,email,senha_hash) VALUES (:id,:company,'Nome','legacy@example.com','hash')"), {"id": user, "company": company})
        db.session.execute(text("INSERT INTO dispositivos (id,empresa_id,usuario_id,nome) VALUES (:id,:company,:user,'Celular')"), {"id": device, "company": company, "user": user})
        db.session.execute(text("INSERT INTO escalas (id,empresa_id,nome,tipo,carga_semanal_minutos,regras) VALUES (:id,:company,'Escala','Semanal',2400,'{}')"), {"id": schedule, "company": company})
        db.session.commit()
        upgrade(directory=MIGRATIONS)
        record = db.session.get(Dispositivo, device)
        assert record.device_uuid == device and record.usuario_id == user
        assert record.tipo.value == "PESSOAL"
        assert db.session.get(Escala, schedule).modelo.value == "Legado"
