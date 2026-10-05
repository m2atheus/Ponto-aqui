"""Application Factory e extensões compartilhadas."""

import os
from datetime import timedelta
from pathlib import Path

from dotenv import load_dotenv
from flask import Flask
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import MetaData

from .config import resolve_database_url
from .supabase_client import SupabaseExtension


ENV_FILE = Path(__file__).resolve().parent.parent / ".env"

metadata = MetaData(naming_convention={
    "ix": "ix_%(table_name)s_%(column_0_name)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
})

db = SQLAlchemy(metadata=metadata)
migrate = Migrate()
jwt = JWTManager()
cors = CORS()
supabase = SupabaseExtension()


def create_app(config: dict | None = None) -> Flask:
    # Funciona também ao importar a factory fora do Flask CLI.
    # Variáveis definidas no ambiente têm precedência sobre o arquivo local.
    load_dotenv(ENV_FILE, override=False)
    app = Flask(__name__)
    app.config.from_mapping(
        SQLALCHEMY_DATABASE_URI=os.getenv("DATABASE_URL"),
        DATABASE_HOST=os.getenv("DATABASE_HOST", ""),
        DATABASE_PORT=os.getenv("DATABASE_PORT", "5432"),
        DATABASE_NAME=os.getenv("DATABASE_NAME", "postgres"),
        DATABASE_USER=os.getenv("DATABASE_USER", ""),
        DATABASE_PASSWORD=os.getenv("DATABASE_PASSWORD", ""),
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        SQLALCHEMY_ENGINE_OPTIONS={"pool_pre_ping": True},
        JWT_SECRET_KEY=os.getenv("JWT_SECRET_KEY"),
        JWT_TOKEN_LOCATION=["headers"],
        JWT_ACCESS_TOKEN_EXPIRES=timedelta(minutes=30),
        JWT_REFRESH_TOKEN_EXPIRES=timedelta(days=7),
        SUPABASE_URL=os.getenv("SUPABASE_URL", ""),
        SUPABASE_KEY=os.getenv("SUPABASE_KEY", ""),
        SUPABASE_PUBLISHABLE_KEY=os.getenv("SUPABASE_PUBLISHABLE_KEY", ""),
        CORS_ORIGINS=[
            origin.strip()
            for origin in os.getenv("CORS_ORIGINS", "").split(",")
            if origin.strip()
        ],
    )
    if config is not None:
        app.config.update(config)

    app.config["SQLALCHEMY_DATABASE_URI"] = resolve_database_url(app.config)
    if not app.config.get("JWT_SECRET_KEY"):
        raise RuntimeError("Configure JWT_SECRET_KEY.")

    supabase.init_app(app)
    db.init_app(app)
    jwt.init_app(app)
    from . import models  # noqa: F401
    migrate.init_app(app, db, compare_type=True, render_as_batch=False)
    cors.init_app(
        app,
        resources={r"/api/*": {"origins": app.config["CORS_ORIGINS"]}},
        supports_credentials=False,
        allow_headers=["Authorization", "Content-Type"],
        methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    )

    from .routes.mobile_routes import mobile_bp
    from .routes.web_routes import web_bp
    app.register_blueprint(web_bp, url_prefix="/api/web")
    app.register_blueprint(mobile_bp, url_prefix="/api/mobile")
    # A página inicial usa o mesmo handler modular de /api/web/.
    app.add_url_rule("/", endpoint="index", view_func=app.view_functions["web.index"])
    return app
