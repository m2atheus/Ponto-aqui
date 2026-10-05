from datetime import date, datetime, timezone

import pytest
from flask_migrate import downgrade, upgrade
from sqlalchemy import func, inspect, select, text
from sqlalchemy.exc import DBAPIError, IntegrityError
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext

from app import db
from app.models import (
    Alocacoes, JustificativasAjustes, PapelUsuario, RegistrosPonto,
    Setores, TipoPonto, Usuarios,
)
from conftest import MIGRATIONS


pytestmark = pytest.mark.postgres


def save_point(session, point_values):
    point = RegistrosPonto(**point_values)
    session.add(point)
    session.flush()
    return point


@pytest.mark.parametrize("field", ["usuario_id", "setor_id", "escala_id"])
def test_allocation_rejects_references_to_other_company(session, tenants, field):
    first, second = tenants
    values = {
        "empresa_id": first.company.id, "usuario_id": first.user.id,
        "funcionario_id": first.employee.id,
        "setor_id": first.sector.id, "escala_id": first.schedule.id,
        "data_inicio": date(2019, 1, 1), "data_fim": date(2019, 1, 10),
    }
    foreign_ids = {
        "usuario_id": second.user.id, "setor_id": second.sector.id,
        "escala_id": second.schedule.id,
    }
    values[field] = foreign_ids[field]
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(Alocacoes(**values))
            session.flush()
    assert error.value.orig.pgcode == "23503"


def test_email_is_unique_globally_and_registration_can_repeat_between_companies(session, tenants):
    assert tenants[0].employee.matricula == tenants[1].employee.matricula
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(Usuarios(
                empresa_id=tenants[1].company.id, nome="Duplicado",
                email=tenants[0].user.email, senha_hash="hash-de-teste",
            ))
            session.flush()
    assert error.value.orig.pgcode == "23505"


@pytest.mark.parametrize("field", ["enviado_por_id", "alocacao_id"])
def test_point_rejects_other_company_sender_or_assignment(session, tenants, point_values, field):
    point_values[field] = (
        tenants[1].user.id if field == "enviado_por_id" else tenants[1].assignment.id
    )
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            save_point(session, point_values)
    assert error.value.orig.pgcode == "23503"


def test_point_must_match_employee_in_assignment(session, tenants, point_values):
    colleague = Usuarios(
        empresa_id=tenants[0].company.id, nome="Colega",
        email="colega@example.com", senha_hash="hash-de-teste",
    )
    session.add(colleague)
    session.flush()
    point_values["usuario_id"] = colleague.id
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            save_point(session, point_values)
    assert error.value.orig.pgcode == "23503"


def test_duplicate_client_event_cannot_create_second_point(session, point_values):
    original = save_point(session, point_values)
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            save_point(session, point_values)
    assert error.value.orig.pgcode == "23505"
    assert error.value.orig.diag.constraint_name == "uq_registros_evento_cliente"
    assert session.scalar(select(func.count()).select_from(RegistrosPonto)) == 1
    session.refresh(original)
    assert original.ocorrido_em == point_values["ocorrido_em"]
    assert original.recebido_em > original.ocorrido_em


@pytest.mark.parametrize("operation", [
    "UPDATE registros_ponto SET tipo = 'Saida' WHERE id = :id",
    "DELETE FROM registros_ponto WHERE id = :id",
    "TRUNCATE registros_ponto CASCADE",
])
def test_database_rejects_mutation_even_through_direct_sql(session, point_values, operation):
    point = save_point(session, point_values)
    with pytest.raises(DBAPIError) as error:
        with session.begin_nested():
            session.execute(text(operation), {"id": point.id})
    assert error.value.orig.pgcode == "P0001"
    assert "imutaveis" in str(error.value.orig)
    session.refresh(point)
    assert point.tipo == TipoPonto.ENTRADA


@pytest.mark.parametrize("operation", ["update", "delete"])
def test_orm_rejects_mutation_before_sending_sql(session, point_values, operation):
    point = save_point(session, point_values)
    with pytest.raises(RuntimeError):
        with session.begin_nested():
            if operation == "update":
                point.tipo = TipoPonto.SAIDA
            else:
                session.delete(point)
            session.flush()
    session.refresh(point)
    assert point.tipo == TipoPonto.ENTRADA


def test_setting_same_value_does_not_reject_harmless_flush(session, point_values):
    point = save_point(session, point_values)
    point.tipo = TipoPonto.ENTRADA
    session.flush()


@pytest.mark.parametrize(("field", "value"), [
    ("latitude_centro", 91), ("longitude_centro", 181), ("raio_metros", 0),
])
def test_sector_rejects_invalid_perimeter(session, tenants, field, value):
    values = {
        "empresa_id": tenants[0].company.id, "nome": "Inválido",
        "latitude_centro": -8, "longitude_centro": -35, "raio_metros": 100,
    }
    values[field] = value
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(Setores(**values))
            session.flush()
    assert error.value.orig.pgcode == "23514"


def test_point_rejects_distance_outside_recorded_perimeter(session, point_values):
    point_values["distancia_centro_metros"] = 101
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            save_point(session, point_values)
    assert error.value.orig.pgcode == "23514"


def test_approved_adjustment_preserves_original_point(session, tenants, point_values):
    point = save_point(session, point_values)
    reviewer = Usuarios(
        empresa_id=tenants[0].company.id, nome="RH",
        email="rh@example.com", senha_hash="hash-de-teste", papel=PapelUsuario.RH,
    )
    session.add(reviewer)
    session.flush()
    proposed_time = datetime(2020, 1, 2, 12, 0, tzinfo=timezone.utc)
    adjustment = JustificativasAjustes(
        empresa_id=tenants[0].company.id, usuario_id=point.usuario_id,
        registro_ponto_id=point.id, solicitado_por_id=point.usuario_id,
        justificativa="Correção do horário", tipo_proposto="Entrada",
        ocorrido_em_proposto=proposed_time, status="Aprovado",
        decidido_por_id=reviewer.id, decidido_em=datetime.now(timezone.utc),
    )
    session.add(adjustment)
    session.flush()
    session.refresh(point)
    assert point.ocorrido_em == point_values["ocorrido_em"]
    assert adjustment.ocorrido_em_proposto == proposed_time


def test_adjustment_cannot_reference_another_company_point(session, tenants, point_values):
    point = save_point(session, point_values)
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(JustificativasAjustes(
                empresa_id=tenants[1].company.id, usuario_id=tenants[1].user.id,
                registro_ponto_id=point.id, solicitado_por_id=tenants[1].user.id,
                justificativa="Tentativa inválida", tipo_proposto="Entrada",
                ocorrido_em_proposto=point.ocorrido_em,
            ))
            session.flush()
    assert error.value.orig.pgcode == "23503"


def test_approved_adjustment_requires_decision_audit(session, tenants):
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(JustificativasAjustes(
                empresa_id=tenants[0].company.id, usuario_id=tenants[0].user.id,
                solicitado_por_id=tenants[0].user.id, justificativa="Batida esquecida",
                tipo_proposto="Entrada", ocorrido_em_proposto=datetime.now(timezone.utc),
                status="Aprovado",
            ))
            session.flush()
    assert error.value.orig.pgcode == "23514"


def test_rls_denies_direct_reads_to_role_without_bypass(session, tenants):
    protected_tables = session.scalars(text(
        "SELECT relname FROM pg_class WHERE relnamespace = current_schema()::regnamespace "
        "AND relrowsecurity"
    )).all()
    assert set(protected_tables) == set(db.metadata.tables)
    # This built-in PostgreSQL role can read every table, but cannot bypass RLS.
    session.execute(text("SET LOCAL ROLE pg_read_all_data"))
    assert session.scalars(select(Usuarios)).all() == []


def test_migration_matches_models_and_supports_downgrade_upgrade(pg_app):
    with pg_app.app_context():
        with db.engine.connect() as connection:
            context = MigrationContext.configure(connection, opts={"compare_server_default": True})
            assert compare_metadata(context, db.metadata) == []
        downgrade(directory=MIGRATIONS, revision="base")
        with db.engine.connect() as connection:
            assert set(inspect(connection).get_table_names()) == {"alembic_version"}
            assert inspect(connection).get_enums() == []
            assert connection.scalar(text(
                "SELECT count(*) FROM pg_proc WHERE pronamespace = "
                "current_schema()::regnamespace AND proname = 'impedir_mutacao_registro_ponto'"
            )) == 0
        upgrade(directory=MIGRATIONS)
        with db.engine.connect() as connection:
            context = MigrationContext.configure(connection, opts={"compare_server_default": True})
            assert compare_metadata(context, db.metadata) == []
