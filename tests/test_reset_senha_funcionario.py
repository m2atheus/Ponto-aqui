"""Recuperação administrativa de acesso, sem modificar o histórico de ponto."""
import uuid
from datetime import timedelta

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import event, select
from sqlalchemy.exc import OperationalError
from werkzeug.security import check_password_hash

from app.models import Funcionarios, PapelUsuario, Usuarios
from app.services.auth_service import AuthService
from test_ajustes_rh import contexto, headers, snapshot


def path(funcionario_id):
    return f"/api/v1/admin/funcionarios/{funcionario_id}/resetar-senha"


@pytest.mark.parametrize("modo", ["ausente", "invalido", "expirado"])
def test_exige_jwt_valido(app, modo):
    cabecalhos = {}
    if modo != "ausente":
        with app.app_context():
            token = create_access_token(identity=str(uuid.uuid4()), expires_delta=timedelta(seconds=-1))
        cabecalhos["Authorization"] = "Bearer " + (token if modo == "expirado" else "invalid")
    assert app.test_client().put(path(uuid.uuid4()), json={"nova_senha": "NovaSenha123!"}, headers=cabecalhos).status_code == 401


@pytest.mark.postgres
def test_redefine_hash_e_login_preservando_conta_e_registros(contexto, session):
    ctx = contexto
    ctx.own.user.senha_hash = AuthService.hash_senha("SenhaAnterior123!")
    session.commit()
    antigo_hash = ctx.own.user.senha_hash
    pontos = snapshot(session)
    funcionario = dict(session.execute(select(Funcionarios.__table__).where(Funcionarios.id == ctx.own.employee.id)).mappings().one())
    original = dict(session.execute(select(Usuarios.__table__).where(Usuarios.id == ctx.own.user.id)).mappings().one())
    nova = "  Nova senha 123!  "
    resposta = ctx.client.put(path(ctx.own.employee.id), json={"nova_senha": nova}, headers=headers(ctx.rh))
    assert resposta.status_code == 200, resposta.json
    assert resposta.json == {"mensagem": "Senha redefinida com sucesso para este funcionário.",
        "funcionario_id": str(ctx.own.employee.id), "empresa_id": str(ctx.own.company.id), "usuario_id": str(ctx.own.user.id)}
    assert resposta.headers["Cache-Control"] == "no-store"
    session.expire_all()
    usuario = session.get(Usuarios, ctx.own.user.id)
    assert usuario.senha_hash != antigo_hash and usuario.senha_hash.startswith("scrypt:")
    assert check_password_hash(usuario.senha_hash, nova)
    assert not check_password_hash(usuario.senha_hash, nova.strip())
    depois = dict(session.execute(select(Usuarios.__table__).where(Usuarios.id == usuario.id)).mappings().one())
    assert {k: v for k, v in depois.items() if k != "senha_hash"} == {k: v for k, v in original.items() if k != "senha_hash"}
    assert dict(session.execute(select(Funcionarios.__table__).where(Funcionarios.id == ctx.own.employee.id)).mappings().one()) == funcionario
    assert snapshot(session) == pontos
    assert AuthService.login({"email": usuario.email, "senha": "SenhaAnterior123!"}, session=session)[1] == 401
    assert AuthService.login({"email": usuario.email, "senha": nova}, session=session)[1] == 200


@pytest.mark.postgres
@pytest.mark.parametrize("dados", [None, [], {}, {"senha": "NovaSenha123!"}, {"nova_senha": None},
    {"nova_senha": 12345678}, {"nova_senha": "1234567"}, {"nova_senha": " " * 8}, {"nova_senha": "x" * 1025},
    {"nova_senha": "NovaSenha123!", "empresa_id": str(uuid.uuid4())}])
def test_payload_invalido_preserva_hash(contexto, session, dados):
    ctx = contexto
    antes = ctx.own.user.senha_hash
    response = ctx.client.put(path(ctx.own.employee.id), json=dados, headers=headers(ctx.rh))
    assert response.status_code == 400, response.json
    assert session.get(Usuarios, ctx.own.user.id).senha_hash == antes


@pytest.mark.postgres
def test_bloqueia_outro_tenant_e_papeis_sem_permissao(contexto, session):
    ctx = contexto
    body = {"nova_senha": "NovaSenha123!"}
    assert ctx.client.put(path(ctx.foreign.employee.id), json=body, headers=headers(ctx.rh)).status_code == 404
    assert ctx.client.put(path(ctx.own.employee.id), json=body,
        headers=headers(ctx.rh, empresa=ctx.foreign.company.id)).status_code == 401
    for papel in (PapelUsuario.GESTOR, PapelUsuario.FUNCIONARIO, PapelUsuario.RELOGIO):
        ctx.rh.papel = papel
        session.commit()
        # Claim de RH forjada não substitui a autorização real no banco.
        assert ctx.client.put(path(ctx.own.employee.id), json=body, headers=headers(ctx.rh)).status_code == 403


@pytest.mark.postgres
def test_superadmin_global_sem_empresa_nao_pode_redefinir_senha(contexto, session):
    ctx = contexto
    admin = Usuarios(empresa_id=None, nome="Superadmin", papel=PapelUsuario.SUPERADMIN,
        email="superadmin-reset@example.com", senha_hash="hash")
    session.add(admin)
    session.commit()
    antes = ctx.own.user.senha_hash
    response = ctx.client.put(path(ctx.own.employee.id), json={"nova_senha": "NovaSenha123!"},
        headers=headers(admin, role="SUPERADMIN"))
    assert response.status_code == 403
    assert session.get(Usuarios, ctx.own.user.id).senha_hash == antes


@pytest.mark.postgres
def test_sem_conta_nao_cria_usuario_e_conta_admin_nao_pode_ser_redefinida(contexto, session):
    ctx = contexto
    pessoa = Funcionarios(empresa_id=ctx.own.company.id, nome="Sem conta", matricula="SEM-ACESSO")
    session.add(pessoa)
    session.commit()
    body = {"nova_senha": "NovaSenha123!"}
    response = ctx.client.put(path(pessoa.id), json=body, headers=headers(ctx.rh))
    assert response.status_code == 409 and response.json["erro"]["codigo"] == "ACESSO_NAO_VINCULADO"
    assert session.get(Funcionarios, pessoa.id).usuario_id is None
    ctx.own.user.papel = PapelUsuario.RH
    session.commit()
    assert ctx.client.put(path(ctx.own.employee.id), json=body, headers=headers(ctx.rh)).status_code == 409


@pytest.mark.postgres
def test_inativo_nao_e_reativado_e_falha_de_banco_faz_rollback(contexto, session):
    ctx = contexto
    ctx.own.user.ativo = False
    ctx.own.employee.ativo = False
    session.commit()
    assert ctx.client.put(path(ctx.own.employee.id), json={"nova_senha": "NovaSenha123!"}, headers=headers(ctx.rh)).status_code == 200
    assert session.get(Usuarios, ctx.own.user.id).ativo is False
    assert session.get(Funcionarios, ctx.own.employee.id).ativo is False
    anterior = ctx.own.user.senha_hash
    def falhar(connection, cursor, statement, parameters, context, many):
        if statement.startswith("UPDATE usuarios"):
            raise OperationalError(statement, parameters, Exception("indisponivel"))
    connection = session.connection()
    event.listen(connection, "before_cursor_execute", falhar)
    try:
        resposta = ctx.client.put(path(ctx.own.employee.id), json={"nova_senha": "OutraSenha123!"}, headers=headers(ctx.rh))
    finally:
        event.remove(connection, "before_cursor_execute", falhar)
    assert resposta.status_code == 503
    assert session.get(Usuarios, ctx.own.user.id).senha_hash == anterior
