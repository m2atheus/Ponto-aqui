from datetime import date, datetime, time, timedelta, timezone
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest

from sqlalchemy.orm import Session

from app import db
from app.models import Alocacoes, Empresas, Escalas, Funcionarios, ModeloEscala, Setores, Turnos, Usuarios
from app.services.check_schedule_conflict_service import CheckScheduleConflictService as Service
from test_mobile_w09 import concurrent_app


def schedule(session, tenant, name="Nova", start=8, end=17, days=None, model="Diurno", reference=None):
    escala = Escalas(empresa_id=tenant.company.id, nome=name, modelo=model,
        tipo="Ciclica" if model in ("12x36", "24x72") else "Semanal",
        data_referencia=reference, regras={}, carga_semanal_minutos=0)
    session.add(escala)
    session.flush()
    session.add(Turnos(empresa_id=tenant.company.id, escala_id=escala.id,
        hora_inicio=time(start), hora_fim=time(end), dias_semana=days or [1, 2, 3, 4, 5],
        fim_dia_seguinte=start == end))
    session.flush()
    return escala


def existing(session, tenant, start=8, end=17, days=None):
    tenant.schedule.modelo = ModeloEscala.DIURNO
    session.add(Turnos(empresa_id=tenant.company.id, escala_id=tenant.schedule.id,
        hora_inicio=time(start), hora_fim=time(end), dias_semana=days or [1, 2, 3, 4, 5]))
    session.flush()


def check(session, tenant, escala, start="2026-10-05", end="2026-10-05"):
    return Service.validar_alocacao(tenant.company.id, tenant.user.id, escala.id, start, end, session=session)


@pytest.mark.parametrize("a,b,c,d,overlap", [(8, 19, 19, 23, False), (8, 19, 18, 23, True),
                                          (8, 19, 9, 10, True), (19, 23, 8, 19, False)])
def test_half_open_intervals(a, b, c, d, overlap):
    anchor = datetime(2026, 10, 5, tzinfo=timezone.utc)
    assert Service.intervalos_sobrepostos(*(anchor + timedelta(hours=h) for h in (a, b, c, d))) is overlap


def test_interval_helper_rejects_naive_or_empty_intervals():
    anchor = datetime(2026, 1, 1, tzinfo=timezone.utc)
    with pytest.raises(ValueError):
        Service.intervalos_sobrepostos(anchor, anchor, anchor, anchor + timedelta(hours=1))
    with pytest.raises(ValueError):
        Service.intervalos_sobrepostos(anchor.replace(tzinfo=None), anchor, anchor, anchor + timedelta(hours=1))


@pytest.mark.postgres
def test_contiguous_shift_permitted_and_conflict_details(session, tenants):
    t = tenants[0]
    existing(session, t, start=8, end=19)
    escala = schedule(session, t, start=19, end=23)
    result, status = check(session, t, escala)
    assert status == 200 and result["valida"]
    escala = schedule(session, t, name="Sobreposta", start=18, end=23)
    result, status = check(session, t, escala)
    assert status == 409
    details = result["erro"]["detalhes"]
    assert details["escala_id"] == str(t.schedule.id)
    assert details["inicio"] == "2026-10-05T18:00:00-03:00"
    assert details["fim"] == "2026-10-05T19:00:00-03:00"


@pytest.mark.postgres
def test_night_from_ended_allocation_conflicts_with_next_day(session, tenants):
    t = tenants[0]
    t.schedule.modelo, t.schedule.tipo = "12x36", "Ciclica"
    t.schedule.data_referencia = date(2026, 10, 5)
    t.assignment.data_fim = date(2026, 10, 5)
    session.add(Turnos(empresa_id=t.company.id, escala_id=t.schedule.id,
        hora_inicio=time(19), hora_fim=time(7)))
    session.flush()
    escala = schedule(session, t, start=6, end=18, days=[2])
    result, status = check(session, t, escala, "2026-10-06", "2026-10-06")
    assert status == 409 and result["erro"]["detalhes"]["data"] == "2026-10-06"
    assert result["erro"]["detalhes"]["fim"].endswith("07:00:00-03:00")
    escala = schedule(session, t, name="Contígua manhã", start=7, end=18, days=[2])
    assert check(session, t, escala, "2026-10-06", "2026-10-06")[1] == 200


@pytest.mark.postgres
def test_checks_any_sector_and_employee_allocation_without_user_id(session, tenants):
    t = tenants[0]
    existing(session, t, start=10, end=11)
    other = Setores(empresa_id=t.company.id, nome="Outro", latitude_centro=0, longitude_centro=0, raio_metros=100)
    escala = schedule(session, t, name="Outro setor", start=8, end=9)
    session.add(other)
    session.flush()
    allocation = Alocacoes(empresa_id=t.company.id, funcionario_id=t.employee.id,
        setor_id=other.id, escala_id=escala.id, data_inicio=date(2026, 10, 5))
    session.add(allocation)
    session.flush()
    nova = schedule(session, t, name="Pretendida", start=8, end=10)
    result, status = check(session, t, nova)
    assert status == 409 and result["erro"]["detalhes"]["setor_id"] == str(other.id)


@pytest.mark.postgres
def test_night_tail_of_candidate_intersects_allocation_starting_next_day(session, tenants):
    t = tenants[0]
    t.assignment.data_inicio = date(2026, 10, 6)
    existing(session, t, start=6, end=18, days=[2])
    nova = schedule(session, t, start=19, end=7, model="12x36", reference=date(2026, 10, 5))
    assert check(session, t, nova)[1] == 409


@pytest.mark.postgres
def test_inactive_existing_schedule_still_occupies_time(session, tenants):
    t = tenants[0]
    existing(session, t)
    t.schedule.ativo = False
    session.flush()
    assert check(session, t, schedule(session, t))[1] == 409


@pytest.mark.postgres
def test_cyclic_rest_and_reference_phase(session, tenants):
    t = tenants[0]
    existing(session, t)
    nova = schedule(session, t, start=19, end=7, model="12x36", reference=date(2026, 10, 5))
    result, status = check(session, t, nova, "2026-10-06", "2026-10-06")
    assert status == 200 and result["intervalos"] == []
    # A vigência começa na terça: o plantão iniciado na segunda não pertence a ela.


@pytest.mark.postgres
def test_cycle_with_multiple_components(session, tenants):
    t = tenants[0]
    existing(session, t, start=19, end=20)
    nova = schedule(session, t, start=7, end=12, model="12x36", reference=date(2026, 10, 5))
    session.add(Turnos(empresa_id=t.company.id, escala_id=nova.id, ordem=1,
        hora_inicio=time(13), hora_fim=time(19)))
    session.flush()
    result, status = check(session, t, nova)
    assert status == 200 and len(result["intervalos"]) == 2


@pytest.mark.postgres
def test_foreign_tenant_user_and_schedule_hidden(session, tenants):
    t, other = tenants
    nova = schedule(session, t)
    for user_id, schedule_id in [(other.user.id, nova.id), (t.user.id, other.schedule.id)]:
        _, status = Service.validar_alocacao(t.company.id, user_id, schedule_id, "2026-10-05", "2026-10-05", session=session)
        assert status == 404


@pytest.mark.postgres
@pytest.mark.parametrize("start,end", [("2026-10-05", None), ("2026-10-06", "2026-10-05"),
                                      ("2026-02-30", "2026-10-05"), ("2020-01-01", "2050-01-01")])
def test_bad_periods_rejected(session, tenants, start, end):
    assert check(session, tenants[0], tenants[0].schedule, start, end)[1] == 400


@pytest.mark.postgres
def test_legacy_allocation_cannot_be_silently_ignored(session, tenants):
    t = tenants[0]
    result, status = check(session, t, schedule(session, t))
    assert status == 400 and result["erro"]["codigo"] == "ESCALA_SEM_TURNOS"


@pytest.mark.postgres
def test_parallel_allocations_in_different_sectors_are_serialized():
    with concurrent_app() as application:
        with application.app_context():
            company = Empresas(razao_social="Agenda concorrente", cnpj="11223344556677")
            db.session.add(company)
            db.session.flush()
            user = Usuarios(empresa_id=company.id, nome="Funcionário", email="schedule-race@example.com", senha_hash="hash")
            scale = Escalas(empresa_id=company.id, nome="Manhã", modelo="Diurno", tipo="Semanal",
                carga_semanal_minutos=0, regras={})
            sectors = [Setores(empresa_id=company.id, nome=f"Setor {i}", latitude_centro=0,
                longitude_centro=0, raio_metros=100) for i in range(2)]
            db.session.add_all([user, scale, *sectors])
            db.session.flush()
            employee = Funcionarios(empresa_id=company.id, usuario_id=user.id, nome=user.nome, matricula="1")
            db.session.add_all([employee, Turnos(empresa_id=company.id, escala_id=scale.id,
                hora_inicio=time(8), hora_fim=time(12), dias_semana=[1])])
            db.session.commit()
            company_id, user_id, employee_id, scale_id = company.id, user.id, employee.id, scale.id
            sector_ids, engine = [s.id for s in sectors], db.engine
        barrier = Barrier(2)
        def worker(sector_id):
            with application.app_context(), Session(engine) as session:
                barrier.wait(timeout=10)
                _, status = Service.validar_alocacao(company_id, user_id, scale_id,
                    "2026-10-05", "2026-10-05", session=session)
                if status == 200:
                    session.add(Alocacoes(empresa_id=company_id, funcionario_id=employee_id,
                        usuario_id=user_id, escala_id=scale_id, setor_id=sector_id,
                        data_inicio=date(2026, 10, 5), data_fim=date(2026, 10, 5)))
                    session.commit()
                else:
                    session.rollback()
                return status
        with ThreadPoolExecutor(max_workers=2) as pool:
            assert sorted(pool.map(worker, sector_ids)) == [200, 409]
