"""Regras W06 verificadas nos Services e em PostgreSQL isolado."""

import uuid
from datetime import date, datetime, time, timezone
from types import SimpleNamespace
from concurrent.futures import ThreadPoolExecutor

import pytest
from flask_migrate import upgrade
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError

from app import db
from app.models import (
    Afastamentos, Alocacoes, Empresas, Escalas, Feriados, Funcionarios,
    PapelUsuario, RegistrosPonto, Setores, Turnos, Usuarios,
)
from app.services.afastamento_service import AfastamentoService
from app.services.alocacao_service import AlocacaoService
from app.services.espelho_service import EspelhoService
from app.services.feriado_service import FeriadoService
from conftest import MIGRATIONS

pytestmark = pytest.mark.postgres


@pytest.fixture
def contexto(session, tenants, monkeypatch):
    tenant = tenants[0]
    rh = Usuarios(nome="RH W06", email="rh@w06.example", senha_hash="hash",
        empresa_id=tenant.company.id, papel=PapelUsuario.RH)
    tenant.schedule.modelo = "5x2"
    session.add_all([rh, Turnos(empresa_id=tenant.company.id, escala_id=tenant.schedule.id,
        hora_inicio=time(8), hora_fim=time(17), tempo_intervalo=60)])
    session.commit()
    monkeypatch.setattr("app.services.espelho_service._agora_utc",
        lambda: datetime(2026, 11, 1, 12, tzinfo=timezone.utc))
    return SimpleNamespace(rh=rh, own=tenant, foreign=tenants[1])


def afastamento(ctx, **changes):
    return {"usuario_id": str(ctx.own.user.id), "tipo": "FERIAS",
        "data_inicio": "2026-10-05", "data_fim": "2026-10-09", **changes}


def espelho(ctx, session, ano=2026, mes=10):
    payload, status = EspelhoService.gerar_mensal(ctx.rh.id, ctx.own.company.id,
        ctx.own.user.id, ano, mes, session=session)
    assert status == 200, payload
    return payload["espelho"]


def dia(result, value):
    return next(row for row in result["dias"] if row["data"] == value)


def ponto(session, tenant, values, tipo, instante, *, alocacao=None, **changes):
    allocation = alocacao or tenant.assignment
    row = RegistrosPonto(**{**values, "empresa_id": tenant.company.id,
        "usuario_id": tenant.user.id, "setor_id": allocation.setor_id,
        "alocacao_id": allocation.id, "enviado_por_id": tenant.user.id,
        "tipo": tipo, "ocorrido_em": datetime.fromisoformat(instante),
        "evento_cliente_id": uuid.uuid4(), **changes})
    session.add(row)
    return row


@pytest.mark.parametrize("start,end", [
    ("2026-10-09", "2026-10-12"), ("2026-10-01", "2026-10-05"),
    ("2026-10-06", "2026-10-07"), ("2026-09-01", "2026-11-01"),
])
def test_inclusive_overlap_returns_400_and_next_day_is_allowed(session, contexto, start, end):
    ctx = contexto
    created, status = AfastamentoService.criar(ctx.rh.id, ctx.own.company.id, afastamento(ctx), session=session)
    assert status == 201 and created["afastamento"]["usuario_id"] == str(ctx.own.user.id)
    payload, status = AfastamentoService.criar(ctx.rh.id, ctx.own.company.id,
        afastamento(ctx, data_inicio=start, data_fim=end), session=session)
    assert status == 400 and payload["erro"]["codigo"] == "AFASTAMENTO_SOBREPOSTO"
    assert AfastamentoService.criar(ctx.rh.id, ctx.own.company.id,
        afastamento(ctx, data_inicio="2026-10-10", data_fim="2026-10-10"), session=session)[1] == 201


@pytest.mark.parametrize("changes", [
    {"data_inicio": "2026-10-10", "data_fim": "2026-10-01"},
    {"data_inicio": "2026-02-30"}, {"data_fim": None}, {"tipo": "INVALIDO"},
    {"tipo": []}, {"anexo_url": "javascript:alert(1)"}, {"anexo_url": "https://user:secret@example.com/file"},
    {"empresa_id": str(uuid.uuid4())}, {"descricao": 123},
])
def test_invalid_leave_rejected(session, contexto, changes):
    ctx = contexto
    assert AfastamentoService.criar(ctx.rh.id, ctx.own.company.id,
        afastamento(ctx, **changes), session=session)[1] == 400
    assert session.scalars(select(Afastamentos)).all() == []


def test_leave_update_rechecks_overlap_and_cannot_change_employee(session, contexto):
    ctx = contexto
    first, _ = AfastamentoService.criar(ctx.rh.id, ctx.own.company.id, afastamento(ctx), session=session)
    second, _ = AfastamentoService.criar(ctx.rh.id, ctx.own.company.id,
        afastamento(ctx, data_inicio="2026-10-12", data_fim="2026-10-13"), session=session)
    target = second["afastamento"]["id"]
    assert AfastamentoService.atualizar(ctx.rh.id, ctx.own.company.id, target,
        {"data_inicio": "2026-10-09"}, session=session)[1] == 400
    stored = session.get(Afastamentos, uuid.UUID(target))
    assert stored.data_inicio == date(2026, 10, 12)
    assert AfastamentoService.atualizar(ctx.rh.id, ctx.own.company.id, target,
        {"usuario_id": str(ctx.foreign.user.id)}, session=session)[1] == 400
    assert AfastamentoService.atualizar(ctx.rh.id, ctx.own.company.id, target,
        {"tipo": "ATESTADO", "anexo_url": "https://example.com/atestado.pdf"}, session=session)[1] == 200
    assert AfastamentoService.remover(ctx.rh.id, ctx.own.company.id, first["afastamento"]["id"], session=session)[1] == 200


def test_holiday_company_sector_crud_duplicate_and_scope(session, contexto):
    ctx = contexto
    data = {"data": "2026-10-12", "descricao": " Dia de folga "}
    global_, status = FeriadoService.criar(ctx.rh.id, ctx.own.company.id, data, session=session)
    assert status == 201 and global_["feriado"]["setor_id"] is None
    local, status = FeriadoService.criar(ctx.rh.id, ctx.own.company.id,
        {**data, "setor_id": str(ctx.own.sector.id)}, session=session)
    assert status == 201
    assert FeriadoService.criar(ctx.rh.id, ctx.own.company.id, data, session=session)[1] == 409
    assert FeriadoService.criar(ctx.rh.id, ctx.own.company.id,
        {**data, "setor_id": str(ctx.foreign.sector.id)}, session=session)[1] == 404
    assert len(FeriadoService.listar(ctx.rh.id, ctx.own.company.id, session=session)[0]["feriados"]) == 2
    target = local["feriado"]["id"]
    assert FeriadoService.atualizar(ctx.rh.id, ctx.own.company.id, target,
        {"setor_id": None}, session=session)[1] == 409
    assert FeriadoService.atualizar(ctx.rh.id, ctx.own.company.id, target,
        {"descricao": "Atualizado"}, session=session)[0]["feriado"]["descricao"] == "Atualizado"
    assert FeriadoService.remover(ctx.rh.id, ctx.own.company.id, target, session=session)[1] == 200


@pytest.mark.parametrize("dados", [{}, [], None,
    {"data": "2026-02-30", "descricao": "Inválido"},
    {"data": "2026-10-12", "descricao": " "},
    {"data": "2026-10-12", "descricao": "A", "empresa_id": str(uuid.uuid4())},
])
def test_invalid_holiday(session, contexto, dados):
    ctx = contexto
    assert FeriadoService.criar(ctx.rh.id, ctx.own.company.id, dados, session=session)[1] == 400


def test_foreign_employee_and_records_are_not_visible(session, contexto):
    ctx = contexto
    assert AfastamentoService.criar(ctx.rh.id, ctx.own.company.id,
        afastamento(ctx, usuario_id=str(ctx.foreign.user.id)), session=session)[1] == 404
    foreign = Afastamentos(empresa_id=ctx.foreign.company.id, funcionario_id=ctx.foreign.employee.id,
        usuario_id=ctx.foreign.user.id, tipo="FERIAS", data_inicio=date(2026, 10, 1), data_fim=date(2026, 10, 31))
    holiday = Feriados(empresa_id=ctx.foreign.company.id, data=date(2026, 10, 1), descricao="Outra empresa")
    session.add_all([foreign, holiday])
    session.commit()
    assert AfastamentoService.listar(ctx.rh.id, ctx.own.company.id, session=session)[0] == {"afastamentos": []}
    assert FeriadoService.listar(ctx.rh.id, ctx.own.company.id, session=session)[0] == {"feriados": []}
    assert AfastamentoService.atualizar(ctx.rh.id, ctx.own.company.id, foreign.id, {"tipo": "ATESTADO"}, session=session)[1] == 404
    assert AfastamentoService.remover(ctx.rh.id, ctx.own.company.id, foreign.id, session=session)[1] == 404
    assert FeriadoService.remover(ctx.rh.id, ctx.own.company.id, holiday.id, session=session)[1] == 404
    assert EspelhoService.gerar_mensal(ctx.rh.id, ctx.own.company.id, ctx.foreign.user.id, 2026, 10, session=session)[1] == 404


@pytest.mark.parametrize("role", [PapelUsuario.GESTOR, PapelUsuario.FUNCIONARIO, PapelUsuario.RELOGIO])
def test_only_real_rh_can_manage_or_report(session, contexto, role):
    ctx = contexto
    ctx.rh.papel = role
    session.commit()
    assert AfastamentoService.criar(ctx.rh.id, ctx.own.company.id, afastamento(ctx), session=session)[1] == 403
    assert FeriadoService.listar(ctx.rh.id, ctx.own.company.id, session=session)[1] == (200 if role == PapelUsuario.GESTOR else 403)
    assert EspelhoService.gerar_mensal(ctx.rh.id, ctx.own.company.id, ctx.own.user.id, 2026, 10, session=session)[1] == (200 if role == PapelUsuario.GESTOR else 403)


def test_abonos_remove_absence_and_delay_and_sector_holiday_does_not_leak(session, contexto):
    ctx = contexto
    FeriadoService.criar(ctx.rh.id, ctx.own.company.id,
        {"data": "2026-10-01", "descricao": "Empresa"}, session=session)
    FeriadoService.criar(ctx.rh.id, ctx.own.company.id,
        {"data": "2026-10-02", "descricao": "Setor", "setor_id": str(ctx.own.sector.id)}, session=session)
    other_sector = Setores(empresa_id=ctx.own.company.id, nome="Outro", latitude_centro=0, longitude_centro=0, raio_metros=100)
    session.add(other_sector)
    session.commit()
    FeriadoService.criar(ctx.rh.id, ctx.own.company.id,
        {"data": "2026-10-05", "descricao": "Outro", "setor_id": str(other_sector.id)}, session=session)
    AfastamentoService.criar(ctx.rh.id, ctx.own.company.id,
        afastamento(ctx, data_inicio="2026-10-06", data_fim="2026-10-06"), session=session)
    result = espelho(ctx, session)
    for date_ in ["2026-10-01", "2026-10-02", "2026-10-06"]:
        row = dia(result, date_)
        assert row["status"] == "ABONADO_JUSTIFICADO"
        assert row["minutos_faltas"] == row["minutos_atrasos"] == 0
        assert row["minutos_abonados"] == 480
    row = dia(result, "2026-10-05")
    assert row["status"] == "FALTA" and row["minutos_faltas"] == 480
    assert row["feriados"] == []
    assert result["totais"]["minutos_abonados"] == 1440


def test_points_are_read_only_and_late_holiday_is_abonado(session, contexto, point_values):
    ctx = contexto
    points = [ponto(session, ctx.own, point_values, kind, timestamp) for kind, timestamp in [
        ("Entrada", "2026-10-01T09:00:00-03:00"),
        ("InicioIntervalo", "2026-10-01T12:00:00-03:00"),
        ("FimIntervalo", "2026-10-01T13:00:00-03:00"),
        ("Saida", "2026-10-01T17:00:00-03:00"),
    ]]
    session.commit()
    original = [p.ocorrido_em for p in points]
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["status"] == "ATRASO" and row["minutos_atrasos"] == 60
    assert row["minutos_trabalhados"] == 420
    FeriadoService.criar(ctx.rh.id, ctx.own.company.id,
        {"data": "2026-10-01", "descricao": "Abono"}, session=session)
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["status"] == "ABONADO_JUSTIFICADO"
    assert row["minutos_faltas"] == row["minutos_atrasos"] == 0
    assert [session.get(RegistrosPonto, p.id).ocorrido_em for p in points] == original


def test_historical_switch_preserves_ids_and_old_report_and_rolls_back_invalid_destination(session, contexto):
    ctx = contexto
    old = ctx.own.assignment
    old.data_inicio = date(2026, 9, 1)
    new_sector = Setores(empresa_id=ctx.own.company.id, nome="Destino", latitude_centro=0, longitude_centro=0, raio_metros=100)
    new_schedule = Escalas(empresa_id=ctx.own.company.id, nome="Nova escala", modelo="5x2", tipo="Semanal",
        regras={}, carga_semanal_minutos=1200)
    session.add_all([new_sector, new_schedule])
    session.flush()
    session.add(Turnos(empresa_id=ctx.own.company.id, escala_id=new_schedule.id,
        hora_inicio=time(13), hora_fim=time(17)))
    session.commit()
    before = espelho(ctx, session, mes=9)
    invalid, status = AlocacaoService.trocar(ctx.rh.id, ctx.own.company.id, old.id,
        {"setor_id": str(ctx.foreign.sector.id), "data_inicio": "2026-10-15"}, session=session)
    assert status == 404 and session.get(Alocacoes, old.id).data_fim is None
    payload, status = AlocacaoService.trocar(ctx.rh.id, ctx.own.company.id, old.id, {
        "setor_id": str(new_sector.id), "escala_id": str(new_schedule.id),
        "data_inicio": "2026-10-15", "data_fim": "2026-10-31"}, session=session)
    assert status == 201, payload
    assert old.data_fim == date(2026, 10, 14)
    assert old.setor_id == ctx.own.sector.id and old.escala_id == ctx.own.schedule.id
    assert payload["alocacao"]["id"] != str(old.id)
    posterior = espelho(ctx, session, mes=9)
    assert posterior["dias"] == before["dias"]
    assert posterior["totais"] == before["totais"]
    assert posterior["alocacoes_historicas"][0]["escala"] == before["alocacoes_historicas"][0]["escala"]
    result = espelho(ctx, session)
    assert dia(result, "2026-10-14")["intervalos_previstos"][0]["escala_id"] == str(ctx.own.schedule.id)
    assert dia(result, "2026-10-15")["intervalos_previstos"][0]["escala_id"] == str(new_schedule.id)
    assert dia(result, "2026-10-14")["minutos_previstos"] == 480
    assert dia(result, "2026-10-15")["minutos_previstos"] == 240


def test_night_shift_month_boundary_uses_previous_assignment_and_proportional_break(session, contexto, point_values):
    ctx = contexto
    schedule = ctx.own.schedule
    schedule.modelo = "Diurno"
    shift = session.scalar(select(Turnos).where(Turnos.escala_id == schedule.id))
    shift.hora_inicio, shift.hora_fim, shift.tempo_intervalo, shift.dias_semana = time(19), time(7), 60, [3]
    ctx.own.assignment.data_fim = date(2026, 9, 30)
    session.commit()
    ponto(session, ctx.own, point_values, "Entrada", "2026-09-30T19:00:00-03:00")
    ponto(session, ctx.own, point_values, "InicioIntervalo", "2026-10-01T00:00:00-03:00")
    ponto(session, ctx.own, point_values, "FimIntervalo", "2026-10-01T01:00:00-03:00")
    ponto(session, ctx.own, point_values, "Saida", "2026-10-01T07:00:00-03:00")
    session.commit()
    september, october = espelho(ctx, session, mes=9), espelho(ctx, session)
    assert dia(september, "2026-09-30")["minutos_previstos"] == 275
    row = dia(october, "2026-10-01")
    assert row["minutos_previstos"] == 385 and row["minutos_trabalhados"] == 360
    assert row["minutos_faltas"] == 0
    assert row["intervalos_previstos"][0]["setor_id"] == str(ctx.own.sector.id)
    assert dia(october, "2026-10-02")["status"] == "SEM_ALOCACAO"


def test_no_allocation_missing_shift_pending_punch_and_future_do_not_invent_absences(session, contexto, point_values, monkeypatch):
    ctx = contexto
    ctx.own.schedule.modelo = "Legado"
    session.commit()
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["status"] == "APURACAO_PENDENTE" and row["minutos_faltas"] == 0
    ctx.own.schedule.modelo = "5x2"
    session.commit()
    ponto(session, ctx.own, point_values, "Entrada", "2026-10-01T08:00:00-03:00",
        situacao="PendenteAnalise", motivos=["DESVIO_RELOGIO"])
    session.commit()
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["status"] == "APURACAO_PENDENTE" and row["minutos_faltas"] == 0
    monkeypatch.setattr("app.services.espelho_service._agora_utc", lambda: datetime(2026, 9, 1, tzinfo=timezone.utc))
    row = dia(espelho(ctx, session), "2026-10-02")
    assert row["status"] == "PREVISTO" and row["minutos_faltas"] == 0
    ctx.own.assignment.data_fim = date(2020, 1, 1)
    session.commit()
    assert dia(espelho(ctx, session), "2026-10-02")["status"] == "SEM_ALOCACAO"


def test_same_day_multiple_sectors_only_local_holiday_segment_is_abonado(session, contexto):
    ctx = contexto
    ctx.own.schedule.modelo = "Diurno"
    shift = session.scalar(select(Turnos).where(Turnos.escala_id == ctx.own.schedule.id))
    shift.hora_fim, shift.tempo_intervalo = time(12), 0
    sector = Setores(empresa_id=ctx.own.company.id, nome="Tarde", latitude_centro=0, longitude_centro=0, raio_metros=100)
    schedule = Escalas(empresa_id=ctx.own.company.id, nome="Tarde", modelo="Diurno", tipo="Semanal",
        carga_semanal_minutos=1200, regras={})
    session.add_all([sector, schedule])
    session.flush()
    session.add_all([Turnos(empresa_id=ctx.own.company.id, escala_id=schedule.id, hora_inicio=time(13), hora_fim=time(17)),
        Alocacoes(empresa_id=ctx.own.company.id, funcionario_id=ctx.own.employee.id, usuario_id=ctx.own.user.id,
            setor_id=sector.id, escala_id=schedule.id, data_inicio=date(2026, 10, 1))])
    session.commit()
    FeriadoService.criar(ctx.rh.id, ctx.own.company.id, {"data": "2026-10-01", "descricao": "Manhã",
        "setor_id": str(ctx.own.sector.id)}, session=session)
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["status"] == "ABONO_PARCIAL"
    assert row["minutos_previstos"] == 480 and row["minutos_abonados"] == 240
    assert row["minutos_exigiveis"] == row["minutos_faltas"] == 240


def test_database_enforces_user_company_and_employee_identity(session, contexto):
    ctx = contexto
    with pytest.raises(IntegrityError):
        with session.begin_nested():
            session.add(Afastamentos(empresa_id=ctx.own.company.id, funcionario_id=ctx.own.employee.id,
                usuario_id=ctx.foreign.user.id, tipo="FERIAS", data_inicio=date(2026, 1, 1), data_fim=date(2026, 1, 2)))
            session.flush()


def test_leave_concurrency_preserves_one_record_and_returns_400():
    from test_mobile_w09 import concurrent_app
    with concurrent_app() as application, application.app_context():
        company = Empresas(razao_social="Concorrência W06", cnpj="76543210000199")
        db.session.add(company)
        db.session.flush()
        rh = Usuarios(empresa_id=company.id, nome="RH", email="race-rh@w06.example",
            senha_hash="hash", papel=PapelUsuario.RH)
        user = Usuarios(empresa_id=company.id, nome="Pessoa", email="race-user@w06.example", senha_hash="hash")
        db.session.add_all([rh, user])
        db.session.flush()
        employee = Funcionarios(empresa_id=company.id, usuario_id=user.id, nome="Pessoa", matricula="W06")
        db.session.add(employee)
        db.session.commit()
        actor, tenant, target = rh.id, company.id, user.id
        db.session.remove()
        def cadastrar(_):
            with application.app_context():
                return AfastamentoService.criar(actor, tenant, {"usuario_id": str(target),
                    "tipo": "FERIAS", "data_inicio": "2026-10-01", "data_fim": "2026-10-10"})[1]
        with ThreadPoolExecutor(max_workers=2) as pool:
            assert sorted(pool.map(cadastrar, range(2))) == [201, 400]
        assert len(AfastamentoService.listar(actor, tenant)[0]["afastamentos"]) == 1


def test_migration_backfills_user_without_losing_leave_or_accountless_employee():
    from test_mobile_w09 import concurrent_app
    with concurrent_app(revision="0005") as application, application.app_context():
        company = Empresas(razao_social="Legado W06", cnpj="98764321000199")
        db.session.add(company)
        db.session.flush()
        user = Usuarios(empresa_id=company.id, nome="Pessoa", email="legacy@w06.example", senha_hash="hash")
        db.session.add(user)
        db.session.flush()
        registered = Funcionarios(empresa_id=company.id, usuario_id=user.id, nome="Pessoa", matricula="1")
        accountless = Funcionarios(empresa_id=company.id, nome="Sem login", matricula="2")
        db.session.add_all([registered, accountless])
        db.session.flush()
        ids = []
        for employee in [registered, accountless]:
            lid = uuid.uuid4()
            ids.append(lid)
            db.session.execute(text("""INSERT INTO afastamentos
                (id, empresa_id, funcionario_id, tipo, data_inicio, data_fim)
                VALUES (:id, :empresa, :funcionario, 'FERIAS', '2026-10-01', '2026-10-10')"""),
                {"id": lid, "empresa": company.id, "funcionario": employee.id})
        uid = user.id
        db.session.commit()
        upgrade(directory=MIGRATIONS)
        records = [db.session.get(Afastamentos, lid) for lid in ids]
        assert records[0].usuario_id == uid and records[1].usuario_id is None
        assert all(row.data_fim == date(2026, 10, 10) for row in records)


def test_cyclic_schedule_inactive_historical_records_and_no_current_filter(session, contexto):
    ctx = contexto
    ctx.own.schedule.modelo, ctx.own.schedule.tipo = "12x36", "Ciclica"
    ctx.own.schedule.data_referencia = date(2026, 10, 1)
    ctx.own.schedule.ativo = ctx.own.sector.ativo = ctx.own.employee.ativo = False
    shift = session.scalar(select(Turnos).where(Turnos.escala_id == ctx.own.schedule.id))
    shift.hora_inicio, shift.hora_fim, shift.tempo_intervalo = time(19), time(7), 0
    session.commit()
    result = espelho(ctx, session)
    assert dia(result, "2026-10-01")["minutos_previstos"] == 300
    assert dia(result, "2026-10-02")["minutos_previstos"] == 420
    assert dia(result, "2026-10-03")["minutos_previstos"] == 300


def test_switch_detects_night_conflict_and_rolls_back_previous_end(session, contexto):
    ctx = contexto
    ctx.own.schedule.modelo = "Diurno"
    shift = session.scalar(select(Turnos).where(Turnos.escala_id == ctx.own.schedule.id))
    shift.hora_inicio, shift.hora_fim, shift.tempo_intervalo, shift.dias_semana = time(19), time(7), 0, [3]
    new = Escalas(empresa_id=ctx.own.company.id, nome="Manhã", tipo="Semanal", modelo="Diurno",
        carga_semanal_minutos=1200, regras={})
    session.add(new)
    session.flush()
    session.add(Turnos(empresa_id=ctx.own.company.id, escala_id=new.id,
        hora_inicio=time(6), hora_fim=time(12), dias_semana=[4]))
    session.commit()
    payload, status = AlocacaoService.trocar(ctx.rh.id, ctx.own.company.id, ctx.own.assignment.id,
        {"setor_id": str(ctx.own.sector.id), "escala_id": str(new.id),
            "data_inicio": "2026-10-01", "data_fim": "2026-10-02"}, session=session)
    assert status == 409 and payload["erro"]["codigo"] == "CONFLITO_ESCALA"
    assert session.get(Alocacoes, ctx.own.assignment.id).data_fim is None


def test_incomplete_night_entry_marks_both_days_pending(session, contexto, point_values):
    ctx = contexto
    ctx.own.schedule.modelo = "Diurno"
    shift = session.scalar(select(Turnos).where(Turnos.escala_id == ctx.own.schedule.id))
    shift.hora_inicio, shift.hora_fim, shift.tempo_intervalo, shift.dias_semana = time(19), time(7), 0, [4]
    session.commit()
    ponto(session, ctx.own, point_values, "Entrada", "2026-10-01T19:00:00-03:00")
    session.commit()
    result = espelho(ctx, session)
    assert dia(result, "2026-10-01")["status"] == "APURACAO_PENDENTE"
    assert dia(result, "2026-10-02")["status"] == "APURACAO_PENDENTE"
    assert dia(result, "2026-10-02")["minutos_faltas"] == 0


@pytest.mark.parametrize("ano,mes", [(2026, 0), (2026, 13), (True, 1), (2026, "10"), (9999, 12)])
def test_invalid_month_is_clean_400(session, contexto, ano, mes):
    ctx = contexto
    assert EspelhoService.gerar_mensal(ctx.rh.id, ctx.own.company.id, ctx.own.user.id,
        ano, mes, session=session)[1] == 400


def test_accountless_employee_is_supported_without_fake_user(session, contexto):
    ctx = contexto
    employee = Funcionarios(empresa_id=ctx.own.company.id, nome="Sem conta", matricula="OFFLINE")
    session.add(employee)
    session.commit()
    payload, status = AfastamentoService.criar(ctx.rh.id, ctx.own.company.id,
        {"funcionario_id": str(employee.id), "tipo": "LICENCA", "data_inicio": "2026-10-01", "data_fim": "2026-10-02"}, session=session)
    assert status == 201 and payload["afastamento"]["usuario_id"] is None
    result, status = EspelhoService.gerar_mensal(ctx.rh.id, ctx.own.company.id, None,
        2026, 10, funcionario_id=employee.id, session=session)
    assert status == 200 and dia(result["espelho"], "2026-10-01")["status"] == "ABONADO_JUSTIFICADO"
