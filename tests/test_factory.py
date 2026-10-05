import pytest
from flask_jwt_extended import create_access_token, decode_token
from sqlalchemy.orm import configure_mappers

from app import create_app, db


def test_factory_initializes_extensions_and_blueprints_without_database_access(app):
    configure_mappers()
    assert {"sqlalchemy", "migrate", "flask-jwt-extended"} <= app.extensions.keys()
    assert set(app.blueprints) == {"web", "mobile"}
    assert len(db.metadata.tables) == 7
    url = app.config["SQLALCHEMY_DATABASE_URI"]
    assert url.drivername == "postgresql+psycopg2"
    assert url.query["sslmode"] == "require"


@pytest.mark.parametrize(("config", "message"), [
    ({"SQLALCHEMY_DATABASE_URI": None, "JWT_SECRET_KEY": "x" * 64}, "DATABASE_URL"),
    ({"SQLALCHEMY_DATABASE_URI": "postgresql://test@localhost/test", "JWT_SECRET_KEY": None}, "JWT_SECRET_KEY"),
    ({"SQLALCHEMY_DATABASE_URI": "sqlite://", "JWT_SECRET_KEY": "x" * 64}, "PostgreSQL"),
])
def test_factory_rejects_missing_or_incompatible_configuration(config, message):
    with pytest.raises(RuntimeError, match=message):
        create_app(config)


def test_factory_preserves_stronger_ssl_configuration():
    app = create_app({
        "SQLALCHEMY_DATABASE_URI": "postgres://test@localhost/test?sslmode=verify-full",
        "JWT_SECRET_KEY": "x" * 64,
    })
    assert app.config["SQLALCHEMY_DATABASE_URI"].query["sslmode"] == "verify-full"


def test_jwt_can_transport_empresa_claim(app):
    with app.app_context():
        token = create_access_token(identity="usuario-id", additional_claims={"empresa_id": "empresa-id"})
        decoded = decode_token(token)
    assert decoded["sub"] == "usuario-id"
    assert decoded["empresa_id"] == "empresa-id"


def test_cors_only_accepts_configured_origins(app):
    client = app.test_client()
    allowed = client.get("/api/web/inexistente", headers={"Origin": "https://painel.example"})
    denied = client.get("/api/web/inexistente", headers={"Origin": "https://outro.example"})
    assert allowed.headers["Access-Control-Allow-Origin"] == "https://painel.example"
    assert "Access-Control-Allow-Origin" not in denied.headers


def database_fields(**overrides):
    config = {
        "SQLALCHEMY_DATABASE_URI": "",
        "DATABASE_HOST": "host-do-pooler.example",
        "DATABASE_PORT": "5432",
        "DATABASE_NAME": "postgres",
        "DATABASE_USER": "postgres.projeto",
        "DATABASE_PASSWORD": "senha@com#caracteres/especiais:100%",
        "JWT_SECRET_KEY": "x" * 64,
    }
    config.update(overrides)
    return config


def test_database_fields_support_original_password_without_url_encoding():
    config = database_fields()
    app = create_app(config)
    url = app.config["SQLALCHEMY_DATABASE_URI"]
    assert url.host == config["DATABASE_HOST"]
    assert url.username == config["DATABASE_USER"]
    assert url.password == config["DATABASE_PASSWORD"]
    assert url.database == "postgres"
    assert url.port == 5432
    assert url.query["sslmode"] == "require"


def test_full_database_url_has_precedence_over_separate_fields():
    app = create_app(database_fields(
        SQLALCHEMY_DATABASE_URI="postgresql://usuario:senha@outro.example/banco?sslmode=verify-full",
    ))
    url = app.config["SQLALCHEMY_DATABASE_URI"]
    assert url.host == "outro.example"
    assert url.database == "banco"
    assert url.query["sslmode"] == "verify-full"


def test_missing_database_password_has_actionable_error_without_exposing_values():
    with pytest.raises(RuntimeError, match="DATABASE_PASSWORD") as error:
        create_app(database_fields(DATABASE_PASSWORD=""))
    assert "host-do-pooler.example" not in str(error.value)


@pytest.mark.parametrize("port", ["abc", "0", "65536"])
def test_invalid_database_port_is_rejected(port):
    with pytest.raises(RuntimeError, match="DATABASE_PORT"):
        create_app(database_fields(DATABASE_PORT=port))
