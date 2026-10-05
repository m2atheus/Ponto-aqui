"""Provisionamento confiável pelo console do servidor; sem cadastro público."""
from pathlib import Path
import re
import secrets
import uuid

import click
from flask import current_app
from flask.cli import with_appcontext
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError

from app import db
from app.models import PapelUsuario, Usuarios
from app.services.auth_service import AuthService


@click.command("criar-superadmin")
@click.option("--email", required=True)
@click.option("--nome", default="Administrador", show_default=True)
@click.option("--gerar-senha", is_flag=True, help="Grava senha forte em arquivo privado na pasta instance.")
@with_appcontext
def criar_superadmin(email, nome, gerar_senha):
    email, nome = email.strip().lower(), nome.strip()
    if len(email) > 254 or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email) or not 1 <= len(nome) <= 150:
        raise click.ClickException("Informe nome e e-mail válidos.")
    arquivo = None
    try:
        existing = db.session.scalar(select(Usuarios).where(Usuarios.email == email))
        if existing is not None:
            raise click.ClickException("E-mail já cadastrado. A senha existente não foi alterada.")
        senha = secrets.token_urlsafe(24) if gerar_senha else click.prompt("Senha", hide_input=True, confirmation_prompt=True)
        if not 8 <= len(senha) <= 1024:
            raise click.ClickException("A senha deve conter entre 8 e 1024 caracteres.")
        if gerar_senha:
            pasta = Path(current_app.instance_path)
            pasta.mkdir(parents=True, exist_ok=True)
            arquivo = pasta / ("primeiro-acesso-superadmin-" + uuid.uuid4().hex + ".txt")
            with arquivo.open("x", encoding="utf-8") as handle:
                handle.write(f"E-mail: {email}\nSenha: {senha}\n")
        db.session.add(Usuarios(nome=nome, email=email, senha_hash=AuthService.hash_senha(senha),
            papel=PapelUsuario.SUPERADMIN, empresa_id=None))
        db.session.commit()
    except (SQLAlchemyError, OSError):
        db.session.rollback()
        if arquivo is not None and arquivo.exists():
            arquivo.unlink()
        raise click.ClickException("Não foi possível criar a conta. Verifique a conexão e as migrations.") from None
    click.echo("Superadmin criado: " + email)
    if arquivo is not None:
        click.echo("Credenciais locais: " + str(arquivo))


def registrar_comandos(app):
    app.cli.add_command(criar_superadmin)
