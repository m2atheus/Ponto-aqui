"""Resolução da conexão PostgreSQL sem interpolar senhas em strings."""

from collections.abc import Mapping

from sqlalchemy.engine import URL, make_url


def resolve_database_url(config: Mapping) -> URL:
    database_uri = config.get("SQLALCHEMY_DATABASE_URI")
    if not database_uri:
        required = (
            "DATABASE_HOST", "DATABASE_NAME", "DATABASE_USER", "DATABASE_PASSWORD",
        )
        missing = [name for name in required if not config.get(name)]
        if missing:
            raise RuntimeError(
                "Configure DATABASE_URL ou os campos de conexão PostgreSQL. "
                "Faltam: " + ", ".join(missing) + "."
            )
        try:
            port = int(config.get("DATABASE_PORT") or 5432)
        except (TypeError, ValueError):
            raise RuntimeError("DATABASE_PORT deve ser uma porta válida.") from None
        if not 1 <= port <= 65535:
            raise RuntimeError("DATABASE_PORT deve estar entre 1 e 65535.")
        database_uri = URL.create(
            "postgresql+psycopg2",
            username=config["DATABASE_USER"],
            password=config["DATABASE_PASSWORD"],
            host=config["DATABASE_HOST"],
            port=port,
            database=config["DATABASE_NAME"],
        )

    if isinstance(database_uri, str) and database_uri.startswith("postgres://"):
        database_uri = database_uri.replace("postgres://", "postgresql://", 1)
    database_url = make_url(database_uri)
    if database_url.get_backend_name() != "postgresql":
        raise RuntimeError("Este projeto requer PostgreSQL.")
    database_url = database_url.set(drivername="postgresql+psycopg2")
    if "sslmode" not in database_url.query:
        database_url = database_url.update_query_dict({"sslmode": "require"})
    return database_url
