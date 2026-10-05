import os
import uuid
from datetime import date, datetime, timezone
from pathlib import Path
from types import SimpleNamespace

import pytest
from flask_migrate import upgrade
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from app import create_app, db
from app.models import Alocacoes, Empresas, Escalas, Setores, TipoEscala, Usuarios


MIGRATIONS = str(Path(__file__).resolve().parents[1] / "migrations")


@pytest.fixture(autouse=True)
def isolate_connection_environment(monkeypatch):
    # Configuração local do desenvolvedor não entra em testes sem intenção.
    for name in (
        "SUPABASE_URL", "SUPABASE_KEY", "SUPABASE_PUBLISHABLE_KEY",
        "DATABASE_HOST", "DATABASE_PORT", "DATABASE_NAME", "DATABASE_USER", "DATABASE_PASSWORD",
    ):
        monkeypatch.setenv(name, "")


@pytest.fixture
def app():
    return create_app({
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": "postgresql://test@localhost/test",
        "JWT_SECRET_KEY": "x" * 64,
        "CORS_ORIGINS": ["https://painel.example"],
    })


@pytest.fixture(scope="session")
def pg_app():
    database_uri = os.getenv("TEST_DATABASE_URL")
    if not database_uri:
        pytest.skip("Defina TEST_DATABASE_URL para executar os testes PostgreSQL.")

    url = make_url(database_uri)
    if url.get_backend_name() != "postgresql":
        raise ValueError("TEST_DATABASE_URL deve apontar para PostgreSQL.")
    url = url.set(drivername="postgresql+psycopg2")
    # Apenas este schema aleatório é criado/removido. Não alteramos o schema
    # public nem reutilizamos DATABASE_URL da aplicação automaticamente.
    schema = "test_ponto_" + uuid.uuid4().hex
    admin_engine = create_engine(url)
    with admin_engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))

    options = str(url.query.get("options", ""))
    scoped_url = url.update_query_dict({
        "options": f"{options} -c search_path={schema}".strip(),
    })
    test_app = create_app({
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": scoped_url,
        "JWT_SECRET_KEY": "x" * 64,
        "SUPABASE_URL": "",
        "SUPABASE_KEY": "",
        "SUPABASE_PUBLISHABLE_KEY": "",
    })
    try:
        with test_app.app_context():
            upgrade(directory=MIGRATIONS)
        yield test_app
    finally:
        with test_app.app_context():
            db.session.remove()
            db.engine.dispose()
        with admin_engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin_engine.dispose()


@pytest.fixture
def session(pg_app):
    with pg_app.app_context():
        with db.engine.connect() as connection:
            transaction = connection.begin()
            with Session(
                bind=connection,
                join_transaction_mode="create_savepoint",
                expire_on_commit=False,
            ) as test_session:
                yield test_session
            transaction.rollback()


@pytest.fixture
def tenants(session):
    result = []
    for number in (1, 2):
        company = Empresas(razao_social=f"Empresa {number}", cnpj=f"{number:014d}")
        session.add(company)
        session.flush()
        user = Usuarios(
            empresa_id=company.id, nome="Funcionário",
            email="funcionario@example.com", matricula="001", senha_hash="hash-de-teste",
        )
        sector = Setores(
            empresa_id=company.id, nome="Sede", latitude_centro=-8.0,
            longitude_centro=-35.0, raio_metros=100,
        )
        schedule = Escalas(
            empresa_id=company.id, nome="Comercial", tipo=TipoEscala.SEMANAL,
            carga_semanal_minutos=2400, regras={"versao": 1, "dias": []},
        )
        session.add_all([user, sector, schedule])
        session.flush()
        assignment = Alocacoes(
            empresa_id=company.id, usuario_id=user.id, setor_id=sector.id,
            escala_id=schedule.id, data_inicio=date(2020, 1, 1),
        )
        session.add(assignment)
        session.flush()
        result.append(SimpleNamespace(
            company=company, user=user, sector=sector,
            schedule=schedule, assignment=assignment,
        ))
    return result


@pytest.fixture
def point_values(tenants):
    tenant = tenants[0]
    return {
        "empresa_id": tenant.company.id,
        "usuario_id": tenant.user.id,
        "setor_id": tenant.sector.id,
        "alocacao_id": tenant.assignment.id,
        "enviado_por_id": tenant.user.id,
        "evento_cliente_id": uuid.uuid4(),
        "payload_hash": "a" * 64,
        "tipo": "Entrada",
        "origem": "Mobile",
        "ocorrido_em": datetime(2020, 1, 2, 11, 0, tzinfo=timezone.utc),
        "offset_original_minutos": -180,
        "latitude": -8.0,
        "longitude": -35.0,
        "precisao_metros": 5,
        "latitude_centro_validada": -8.0,
        "longitude_centro_validada": -35.0,
        "raio_validado_metros": 100,
        "distancia_centro_metros": 0,
    }
