"""Autenticação real, contrato Flutter e restrições W01/W02/W03 no PostgreSQL."""

from datetime import date, timedelta
import uuid

import pytest
from flask_jwt_extended import create_access_token, decode_token
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError

from app.models import AcaoForaPerimetro, Alocacoes, Funcionarios, PapelUsuario, Setores, Usuarios
from app.services.auth_service import AuthService


@pytest.fixture(scope="session")
def senha_hash():
    return AuthService.hash_senha("senha-real-de-teste")


@pytest.fixture
def auth_client(session, pg_app, tenants, senha_hash, monkeypatch):
    user = tenants[0].user
    user.senha_hash = senha_hash
    session.flush()
    login, me = AuthService.login, AuthService.me
    monkeypatch.setattr(AuthService, "login", staticmethod(lambda dados: login(dados, session=session)))
    monkeypatch.setattr(AuthService, "me", staticmethod(lambda uid, claims: me(uid, claims, session=session)))
    return pg_app.test_client(), tenants[0]


def login(client, user, **changes):
    return client.post("/api/web/auth/login", json={
        "email": user.email, "senha": "senha-real-de-teste", **changes,
    })


@pytest.mark.postgres
@pytest.mark.parametrize("role", list(PapelUsuario))
def test_login_returns_database_profile_signed_expiring_jwt(auth_client, session, role):
    client, tenant = auth_client
    if role == PapelUsuario.SUPERADMIN:
        user = Usuarios(nome="Admin", email="superadmin@teste.com", empresa_id=None,
            papel=role, senha_hash=tenant.user.senha_hash)
        session.add(user)
    else:
        user = tenant.user
        user.papel = role
    session.flush()
    response = login(client, user, email="  " + user.email.upper() + "  ")
    assert response.status_code == 200
    body = response.get_json()
    assert "senha" not in body["usuario"] and "senha_hash" not in body["usuario"]
    assert body["usuario"]["empresa_id"] == (None if role == PapelUsuario.SUPERADMIN else str(tenant.company.id))
    assert body["usuario"]["papel"] == ("USUARIO_SETOR" if role == PapelUsuario.RELOGIO else role.name)
    claims = decode_token(body["access_token"])
    assert claims["sub"] == str(user.id)
    assert claims["empresa_id"] == body["usuario"]["empresa_id"]
    assert claims["role"] == body["usuario"]["papel"]
    assert claims["exp"] - claims["iat"] == 30 * 60
    restored = client.get("/api/web/auth/me", headers={"Authorization": "Bearer " + body["access_token"]})
    assert restored.status_code == 200 and restored.get_json()["usuario"] == body["usuario"]


@pytest.mark.postgres
@pytest.mark.parametrize("case", ["unknown", "wrong_password", "inactive_user", "inactive_company", "bad_hash", "missing", "role_injection"])
def test_all_failed_logins_are_identical(auth_client, session, case):
    client, tenant = auth_client
    changes = {}
    if case == "unknown":
        changes["email"] = "inexistente@teste.com"
    elif case == "wrong_password":
        changes["senha"] = "errada"
    elif case == "inactive_user":
        tenant.user.ativo = False
    elif case == "inactive_company":
        tenant.company.ativo = False
    elif case == "bad_hash":
        tenant.user.senha_hash = "hash-legado-invalido"
    elif case == "missing":
        changes["senha"] = None
    else:
        changes["role"] = "SUPERADMIN"
    session.flush()
    response = login(client, tenant.user, **changes)
    assert response.status_code == 401
    assert response.get_json() == {"erro": {"codigo": "LOGIN_INVALIDO", "mensagem": "Usuário ou senha inválidos"}}
    assert "access_token" not in response.get_json()


@pytest.mark.parametrize("mode", ["missing", "expired", "malformed", "bad_signature"])
@pytest.mark.parametrize("path", ["/auth/me", "/api/web/auth/me", "/api/mobile/auth/me", "/api/mobile/marcacoes/lote"])
def test_protected_routes_return_401_without_valid_jwt(app, path, mode):
    headers = {}
    if mode != "missing":
        with app.app_context():
            token = create_access_token(identity=str(uuid.uuid4()), expires_delta=(
                timedelta(seconds=-1) if mode == "expired" else timedelta(minutes=1)))
        if mode == "malformed":
            token = "sem-assinatura"
        elif mode == "bad_signature":
            header, payload, signature = token.split(".")
            token = ".".join((header, payload, ("A" if signature[0] != "A" else "B") + signature[1:]))
        headers["Authorization"] = "Bearer " + token
    response = app.test_client().open(path, method="POST" if path.endswith("lote") else "GET", headers=headers)
    assert response.status_code == 401


@pytest.mark.postgres
def test_restore_denies_disabled_company_and_other_tenant_claim(auth_client, session, tenants):
    client, tenant = auth_client
    token = login(client, tenant.user).get_json()["access_token"]
    tenant.company.ativo = False
    session.flush()
    assert client.get("/api/web/auth/me", headers={"Authorization": "Bearer " + token}).status_code == 401
    tenant.company.ativo = True
    wrong_tenant = create_access_token(identity=str(tenant.user.id), additional_claims={"empresa_id": str(tenants[1].company.id)})
    assert client.get("/api/web/auth/me", headers={"Authorization": "Bearer " + wrong_tenant}).status_code == 401


@pytest.mark.postgres
def test_mobile_login_only_binds_registered_owned_active_device(auth_client, session, tenants):
    from app.models import Dispositivos
    client, tenant = auth_client
    own = Dispositivos(empresa_id=tenant.company.id, usuario_id=tenant.user.id, nome="Próprio")
    foreign = Dispositivos(empresa_id=tenants[1].company.id, usuario_id=tenants[1].user.id, nome="Outra empresa")
    session.add_all([own, foreign])
    session.flush()
    for path in ("/auth/login", "/api/web/auth/login", "/api/mobile/auth/login"):
        response = client.post(path, json={"email": tenant.user.email,
            "senha": "senha-real-de-teste", "dispositivo_id": str(own.id)})
        assert response.status_code == 200
        assert decode_token(response.get_json()["access_token"])["dispositivo_id"] == str(own.id)
    for device in (str(foreign.id), str(uuid.uuid4()), "inválido"):
        assert login(client, tenant.user, dispositivo_id=device).status_code == 401
    own.ativo = False
    session.flush()
    assert login(client, tenant.user, dispositivo_id=str(own.id)).status_code == 401


def test_passwords_use_salted_one_way_hashes():
    from werkzeug.security import check_password_hash
    first = AuthService.hash_senha("senha-real-de-teste")
    second = AuthService.hash_senha("senha-real-de-teste")
    assert first != second and first.startswith("scrypt:")
    assert check_password_hash(first, "senha-real-de-teste")
    assert not check_password_hash(first, "outra-senha")


@pytest.mark.postgres
@pytest.mark.parametrize("role,tenant_link", [(PapelUsuario.SUPERADMIN, True), (PapelUsuario.RH, False)])
def test_only_superadmin_can_have_null_company(session, tenants, role, tenant_link):
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(Usuarios(nome="Inválido", email="invalido@teste.com", senha_hash="hash",
                papel=role, empresa_id=tenants[0].company.id if tenant_link else None))
            session.flush()
    assert error.value.orig.pgcode == "23514"


@pytest.mark.postgres
def test_employee_registration_is_unique_in_company(session, tenants):
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(Funcionarios(empresa_id=tenants[0].company.id,
                nome="Duplicado", matricula=tenants[0].employee.matricula))
            session.flush()
    assert error.value.orig.pgcode == "23505"


@pytest.mark.postgres
@pytest.mark.parametrize("start,end", [
    (date(2020, 1, 10), None),
    (date(2019, 1, 1), date(2020, 1, 1)),
    (date(2019, 1, 1), date(2021, 1, 1)),
])
def test_overlapping_allocations_rejected_in_database(session, tenants, start, end):
    tenant = tenants[0]
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(Alocacoes(empresa_id=tenant.company.id, funcionario_id=tenant.employee.id,
                usuario_id=tenant.user.id, setor_id=tenant.sector.id, data_inicio=start, data_fim=end))
            session.flush()
    assert error.value.orig.pgcode == "23P01"


@pytest.mark.postgres
def test_end_allocation_preserves_history_and_allows_following_day(session, tenants):
    tenant = tenants[0]
    original_id = tenant.assignment.id
    tenant.assignment.data_fim = date(2020, 1, 31)
    session.flush()
    session.add(Alocacoes(empresa_id=tenant.company.id, funcionario_id=tenant.employee.id,
        usuario_id=tenant.user.id, setor_id=tenant.sector.id, data_inicio=date(2020, 2, 1)))
    session.flush()
    assert session.scalar(select(Alocacoes).where(Alocacoes.id == original_id)).data_inicio == date(2020, 1, 1)
    with pytest.raises(IntegrityError):
        with session.begin_nested():
            session.delete(tenant.sector)
            session.flush()


@pytest.mark.postgres
def test_employee_and_allocation_cannot_link_another_company(session, tenants):
    first, second = tenants
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(Funcionarios(empresa_id=first.company.id, usuario_id=second.user.id,
                nome="Inválido", matricula="999"))
            session.flush()
    assert error.value.orig.pgcode == "23503"
    with pytest.raises(IntegrityError) as error:
        with session.begin_nested():
            session.add(Alocacoes(empresa_id=first.company.id, funcionario_id=second.employee.id,
                setor_id=first.sector.id, data_inicio=date(2019, 1, 1), data_fim=date(2019, 1, 10)))
            session.flush()
    assert error.value.orig.pgcode == "23503"


@pytest.mark.postgres
def test_new_sector_policies_remain_compatible_with_w09(session, tenants):
    from app.models import PoliticaLocalizacao
    sector = tenants[0].sector
    sector.acao_fora_perimetro = AcaoForaPerimetro.PENDENTE
    sector.exige_selfie = True
    session.flush()
    assert sector.politica_localizacao == PoliticaLocalizacao.PENDENTE
    sector.ignorar_localizacao = True
    session.flush()
    assert sector.politica_localizacao == PoliticaLocalizacao.IGNORAR


@pytest.mark.postgres
@pytest.mark.parametrize("policy", ["Bloquear", "Pendente", "Ignorar"])
def test_upgrade_preserves_existing_points_and_backfills_employees(policy, senha_hash):
    from flask_migrate import upgrade
    from app import db
    from conftest import MIGRATIONS
    from test_mobile_w09 import concurrent_app
    with concurrent_app(revision="0002") as application, application.app_context():
        ids = {key: uuid.uuid4() for key in ("empresa", "usuario", "setor", "escala", "alocacao", "ponto", "evento", "admin", "conta_setor")}
        with db.engine.begin() as connection:
            connection.execute(text("INSERT INTO empresas (id, razao_social, cnpj) VALUES (:empresa, 'Legada', '88888888888888')"), ids)
            connection.execute(text("""INSERT INTO usuarios (id, empresa_id, nome, email, senha_hash)
                VALUES (:usuario, :empresa, 'Funcionário', 'legado@teste.com', :hash)"""), {**ids, "hash": senha_hash})
            connection.execute(text("""INSERT INTO usuarios (id, empresa_id, nome, email, senha_hash, papel)
                VALUES (:admin, :empresa, 'Global', 'global@teste.com', :hash, 'Superadmin')"""), {**ids, "hash": senha_hash})
            connection.execute(text("""INSERT INTO usuarios (id, empresa_id, nome, email, senha_hash, papel)
                VALUES (:conta_setor, :empresa, 'Setor', 'setor@teste.com', :hash, 'Relogio')"""), {**ids, "hash": senha_hash})
            connection.execute(text("""INSERT INTO setores (id, empresa_id, nome, latitude_centro, longitude_centro, raio_metros, politica_localizacao)
                VALUES (:setor, :empresa, 'Sede', -8, -35, 100, :policy)"""), {**ids, "policy": policy})
            connection.execute(text("""INSERT INTO escalas (id, empresa_id, nome, tipo, carga_semanal_minutos, regras)
                VALUES (:escala, :empresa, 'Comercial', 'Semanal', 2400, '{}')"""), ids)
            connection.execute(text("""INSERT INTO alocacoes (id, empresa_id, usuario_id, setor_id, escala_id, data_inicio)
                VALUES (:alocacao, :empresa, :usuario, :setor, :escala, '2020-01-01')"""), ids)
            connection.execute(text("""INSERT INTO registros_ponto (id, empresa_id, usuario_id, setor_id, alocacao_id,
                enviado_por_id, evento_cliente_id, payload_hash, tipo, origem, ocorrido_em, offset_original_minutos,
                latitude, longitude, latitude_centro_validada, longitude_centro_validada, raio_validado_metros,
                distancia_centro_metros, registrado_offline, desvio_relogio_segundos)
                VALUES (:ponto, :empresa, :usuario, :setor, :alocacao, :usuario, :evento, :hash,
                    'Entrada', 'Mobile', '2020-01-02T08:00:00-03:00', -180, -8, -35, -8, -35, 100, 0, true, 15)"""),
                {**ids, "hash": "a" * 64})
            before = dict(connection.execute(text("SELECT * FROM registros_ponto")).mappings().one())
        upgrade(directory=MIGRATIONS)
        with db.engine.connect() as connection:
            assert dict(connection.execute(text("SELECT * FROM registros_ponto")).mappings().one()) == before
            employee = connection.execute(text("SELECT * FROM funcionarios")).mappings().one()
            assert employee["usuario_id"] == ids["usuario"] and employee["matricula"] == "LEGACY-" + str(ids["usuario"])
            assert connection.scalar(text("SELECT funcionario_id FROM alocacoes")) == employee["id"]
            assert connection.scalar(text("SELECT empresa_id FROM usuarios WHERE papel = 'Superadmin'")) is None
            assert connection.scalar(text("SELECT papel FROM usuarios WHERE id = :conta_setor"), ids) == "UsuarioSetor"
            sector = connection.execute(text("SELECT * FROM setores")).mappings().one()
            assert sector["ignorar_localizacao"] == (policy == "Ignorar")
            assert sector["acao_fora_perimetro"] == ("PENDENTE" if policy == "Pendente" else "BLOQUEAR")


@pytest.mark.postgres
def test_duplicate_legacy_emails_block_upgrade_without_modifying_data(capfd):
    from flask_migrate import upgrade
    from app import db
    from conftest import MIGRATIONS
    from test_mobile_w09 import concurrent_app
    with concurrent_app(revision="0002") as application, application.app_context():
        with db.engine.begin() as connection:
            for number in (1, 2):
                company_id = uuid.uuid4()
                connection.execute(text("INSERT INTO empresas (id, razao_social, cnpj) VALUES (:id, 'Empresa', :cnpj)"),
                    {"id": company_id, "cnpj": f"{number:014d}"})
                connection.execute(text("""INSERT INTO usuarios (id, empresa_id, nome, email, senha_hash)
                    VALUES (:id, :company, 'Funcionário', 'repetido@teste.com', 'hash')"""),
                    {"id": uuid.uuid4(), "company": company_id})
        with pytest.raises(SystemExit):
            upgrade(directory=MIGRATIONS)
        assert "e-mails repetidos" in capfd.readouterr().err
        with db.engine.connect() as connection:
            assert connection.scalar(text("SELECT version_num FROM alembic_version")) == "0002"
            assert connection.scalar(text("SELECT count(*) FROM usuarios")) == 2
