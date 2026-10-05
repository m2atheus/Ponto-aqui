"""Critérios W09 com PostgreSQL real e transporte Flask autenticado."""
import io
import os
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from threading import Barrier

import pytest
from flask_jwt_extended import create_access_token
from flask_migrate import downgrade, upgrade
from PIL import Image
from sqlalchemy import create_engine, event, func, select, text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import DBAPIError, OperationalError
from sqlalchemy.orm import Session

from app import create_app, db
from app.models import (
    Alocacoes, Dispositivos, Empresas, Escalas, Funcionarios, PapelUsuario,
    PoliticaLocalizacao, RegistrosPonto, SelfiesPonto, Setores,
    TipoEscala, Usuarios,
)
from app.services.ponto_payload import PontoError, validar_marcacao
from app.services.registro_ponto_service import RegistroPontoService
from app.services.selfie_service import SelfieService


def payload(tenant, device, **changes):
    return {
        "evento_cliente_id": str(uuid.uuid4()), "alocacao_id": str(tenant.assignment.id),
        "dispositivo_id": str(device), "tipo": "Entrada",
        "ocorrido_em": "2020-01-02T08:00:00.123456-03:00",
        "desvio_relogio_segundos": -15, "registrado_offline": True,
        "posicao": {"latitude": -8.0, "longitude": -35.0, "precisao_metros": 5},
        **changes,
    }


@pytest.fixture
def mobile(session, tenants, pg_app, monkeypatch):
    tenant = tenants[0]
    device = Dispositivos(empresa_id=tenant.company.id, usuario_id=tenant.user.id, nome="Celular")
    session.add(device)
    session.flush()
    device_id = device.id
    session.commit()  # A fixture conserva a transação externa para limpeza.
    receive = RegistroPontoService.receber_lote
    upload = SelfieService.enviar
    monkeypatch.setattr(RegistroPontoService, "receber_lote", staticmethod(
        lambda **kwargs: receive(**kwargs, session=session)))
    monkeypatch.setattr(SelfieService, "enviar", staticmethod(
        lambda **kwargs: upload(**kwargs, session=session)))

    def auth(empresa_id=None, usuario_id=None, device_claim=device_id):
        claims = {"empresa_id": str(empresa_id or tenant.company.id)}
        if device_claim is not None:
            claims["dispositivo_id"] = str(device_claim)
        token = create_access_token(identity=str(usuario_id or tenant.user.id), additional_claims=claims)
        return {"Authorization": "Bearer " + token}

    return pg_app.test_client(), auth, tenant, device_id


def send(mobile, item, headers=None):
    client, auth, _, _ = mobile
    response = client.post("/api/mobile/marcacoes/lote", json={"marcacoes": [item]}, headers=headers or auth())
    return response, response.get_json()


@pytest.mark.postgres
def test_batch_preserves_original_time_offline_and_server_receipt(mobile, session):
    _, _, tenant, device = mobile
    item = payload(tenant, device)
    response, body = send(mobile, item)
    assert response.status_code == 200
    row = body["resultados"][0]
    assert row["http_status"] == 201 and row["situacao"] == "Aceita"
    assert row["registrado_offline"] is True and row["desvio_relogio_segundos"] == -15
    point = session.scalar(select(RegistrosPonto))
    assert point.ocorrido_em == datetime(2020, 1, 2, 11, 0, 0, 123456, tzinfo=timezone.utc)
    assert point.offset_original_minutos == -180
    assert point.recebido_em > point.ocorrido_em
    assert point.dados_dispositivo == item
    assert point.distancia_centro_metros == 0


@pytest.mark.postgres
def test_replay_keeps_status_even_after_policy_and_device_change(mobile, session):
    _, _, tenant, device = mobile
    item = payload(tenant, device)
    first = send(mobile, item)[1]["resultados"][0]
    tenant.sector.politica_localizacao = PoliticaLocalizacao.IGNORAR
    session.get(Dispositivos, device).ativo = False
    session.commit()
    second = send(mobile, item)[1]["resultados"][0]
    assert second["duplicada"] is True
    assert second["registro_id"] == first["registro_id"]
    assert second["recebido_em"] == first["recebido_em"]
    assert second["situacao"] == "Aceita"
    assert session.scalar(select(func.count()).select_from(RegistrosPonto)) == 1
    conflict = send(mobile, {**item, "tipo": "Saida"})[1]["resultados"][0]
    assert conflict["http_status"] == 409 and conflict["persistida"] is False
    assert session.scalar(select(RegistrosPonto)).tipo.value == "Entrada"


@pytest.mark.postgres
@pytest.mark.parametrize("policy,position,drift,registered,status,reason", [
    (PoliticaLocalizacao.BLOQUEAR, {"latitude": -8, "longitude": -35}, 120, True, "Aceita", None),
    (PoliticaLocalizacao.BLOQUEAR, {"latitude": -8, "longitude": -35}, -121, True, "PendenteAnalise", "DESVIO_RELOGIO_ACIMA_DO_LIMITE"),
    (PoliticaLocalizacao.PENDENTE, {"latitude": -9, "longitude": -35}, 0, True, "PendenteAnalise", "FORA_DO_PERIMETRO"),
    (PoliticaLocalizacao.BLOQUEAR, {"latitude": -9, "longitude": -35}, 9999999, True, "Recusada", "FORA_DO_PERIMETRO"),
    (PoliticaLocalizacao.IGNORAR, None, 0, True, "Aceita", None),
    (PoliticaLocalizacao.IGNORAR, {"latitude": -9, "longitude": -35}, 0, True, "Aceita", None),
    (PoliticaLocalizacao.BLOQUEAR, {"latitude": -8, "longitude": -35}, 2**63 - 1, True, "PendenteAnalise", "DESVIO_RELOGIO_ACIMA_DO_LIMITE"),
    (PoliticaLocalizacao.IGNORAR, None, 121, True, "PendenteAnalise", "DESVIO_RELOGIO_ACIMA_DO_LIMITE"),
    (PoliticaLocalizacao.BLOQUEAR, None, 0, True, "Recusada", "LOCALIZACAO_AUSENTE"),
    (PoliticaLocalizacao.PENDENTE, None, 0, True, "PendenteAnalise", "LOCALIZACAO_AUSENTE"),
    (PoliticaLocalizacao.IGNORAR, None, 0, False, "Recusada", "APARELHO_NAO_REGISTRADO"),
])
def test_classification_matrix(mobile, session, policy, position, drift, registered, status, reason):
    _, _, tenant, device = mobile
    tenant.sector.politica_localizacao = policy
    session.get(Dispositivos, device).ativo = registered
    session.commit()
    item = payload(tenant, device, posicao=position, desvio_relogio_segundos=drift)
    _, body = send(mobile, item)
    row = body["resultados"][0]
    assert row["situacao"] == status and row["persistida"] is True
    assert reason is None or reason in row["motivos"]
    if position is not None and position["latitude"] == -9:
        assert row["distancia_centro_metros"] > 100_000


@pytest.mark.postgres
def test_unregistered_uuid_is_preserved_without_registry_fk(mobile, session):
    client, auth, tenant, _ = mobile
    unknown = uuid.uuid4()
    item = payload(tenant, unknown)
    _, body = send(mobile, item, headers=auth(device_claim=unknown))
    assert body["resultados"][0]["situacao"] == "Recusada"
    point = session.scalar(select(RegistrosPonto))
    assert point.dispositivo_cliente_id == unknown
    assert point.dispositivo_registrado_id is None


@pytest.mark.postgres
def test_device_must_be_bound_to_token_and_owner(mobile, session, tenants):
    _, auth, tenant, device = mobile
    for token_device in (None, uuid.uuid4()):
        row = send(mobile, payload(tenant, device), headers=auth(device_claim=token_device))[1]["resultados"][0]
        assert row["situacao"] == "Recusada"
    foreign = Dispositivos(empresa_id=tenants[1].company.id, usuario_id=tenants[1].user.id, nome="Outro")
    session.add(foreign)
    session.commit()
    row = send(mobile, payload(tenant, foreign.id), headers=auth(device_claim=foreign.id))[1]["resultados"][0]
    assert row["situacao"] == "Recusada"


@pytest.mark.postgres
def test_mixed_batch_commits_good_items_and_reports_invalid_entries(mobile, session):
    client, auth, tenant, device = mobile
    valid = payload(tenant, device)
    response = client.post("/api/mobile/marcacoes/lote", headers=auth(),
        json=[valid, {**payload(tenant, device), "posicao": {"latitude": 91, "longitude": 0}}, valid])
    rows = response.get_json()["resultados"]
    assert response.status_code == 207
    assert [row["http_status"] for row in rows] == [201, 422, 200]
    assert rows[1]["persistida"] is False and rows[2]["duplicada"] is True
    assert session.scalar(select(func.count()).select_from(RegistrosPonto)) == 1


@pytest.mark.postgres
def test_tenant_and_role_are_taken_from_signed_token_and_database(mobile, session, tenants):
    client, auth, tenant, device = mobile
    foreign = tenants[1]
    response = client.post("/api/mobile/marcacoes/lote", json=[payload(tenant, device)])
    assert response.status_code == 401
    wrong_tenant = send(mobile, payload(tenant, device), headers=auth(empresa_id=foreign.company.id))[0]
    assert wrong_tenant.status_code == 403
    response, body = send(mobile, payload(tenant, device, alocacao_id=str(foreign.assignment.id)))
    assert body["resultados"][0]["http_status"] == 404
    tenant.user.papel = PapelUsuario.RH
    session.commit()
    assert send(mobile, payload(tenant, device))[0].status_code == 403
    assert session.scalar(select(func.count()).select_from(RegistrosPonto)) == 0


@pytest.mark.postgres
def test_duplicate_uuid_does_not_leak_another_employee_or_tenant(mobile, session, tenants):
    _, auth, tenant, device = mobile
    item = payload(tenant, device)
    send(mobile, item)
    foreign = tenants[1]
    foreign_device = Dispositivos(empresa_id=foreign.company.id, usuario_id=foreign.user.id, nome="Outro")
    session.add(foreign_device)
    session.commit()
    response, body = send(mobile, payload(foreign, foreign_device.id, evento_cliente_id=item["evento_cliente_id"]),
        headers=auth(empresa_id=foreign.company.id, usuario_id=foreign.user.id, device_claim=foreign_device.id))
    assert body["resultados"][0]["http_status"] == 201
    assert session.scalar(select(func.count()).select_from(RegistrosPonto)) == 2


@pytest.mark.postgres
def test_uuid_conflict_with_colleague_does_not_disclose_original_receipt(mobile, session):
    _, auth, tenant, device = mobile
    item = payload(tenant, device)
    send(mobile, item)
    colleague = Usuarios(empresa_id=tenant.company.id, nome="Colega", email="colega@teste.com", senha_hash="hash")
    session.add(colleague)
    session.flush()
    employee = Funcionarios(empresa_id=tenant.company.id, usuario_id=colleague.id, nome=colleague.nome, matricula="002")
    session.add(employee)
    session.flush()
    assignment = Alocacoes(empresa_id=tenant.company.id, funcionario_id=employee.id, usuario_id=colleague.id,
        setor_id=tenant.sector.id, escala_id=tenant.schedule.id, data_inicio=tenant.assignment.data_inicio)
    other_device = Dispositivos(empresa_id=tenant.company.id, usuario_id=colleague.id, nome="Outro")
    session.add_all([assignment, other_device])
    session.commit()
    response, body = send(mobile, {**item, "alocacao_id": str(assignment.id), "dispositivo_id": str(other_device.id)},
        headers=auth(usuario_id=colleague.id, device_claim=other_device.id))
    row = body["resultados"][0]
    assert row["http_status"] == 409 and row["persistida"] is False
    assert "registro_id" not in row and "recebido_em" not in row
    assert session.scalar(select(func.count()).select_from(RegistrosPonto)) == 1


def picture(color="red"):
    stream = io.BytesIO()
    Image.new("RGB", (8, 8), color).save(stream, format="PNG")
    return stream.getvalue()


@pytest.mark.postgres
def test_selfie_is_separate_private_idempotent_and_cannot_replace_point(mobile, session):
    client, auth, tenant, device = mobile
    item = payload(tenant, device)
    first = send(mobile, item)[1]["resultados"][0]
    url = "/api/mobile/marcacoes/" + item["evento_cliente_id"] + "/selfie"
    def upload(content):
        return client.post(url, headers=auth(), data={"selfie": (io.BytesIO(content), "../../selfie.png")},
                           content_type="multipart/form-data")
    response = upload(picture())
    assert response.status_code == 201
    assert upload(picture()).get_json()["duplicada"] is True
    assert upload(picture("blue")).status_code == 409
    point = session.scalar(select(RegistrosPonto))
    assert point.recebido_em.astimezone(timezone.utc).isoformat() == first["recebido_em"]
    assert session.scalar(select(func.count()).select_from(SelfiesPonto)) == 1
    assert client.post("/api/mobile/marcacoes/" + str(uuid.uuid4()) + "/selfie",
        headers=auth(), data={"selfie": (io.BytesIO(picture()), "x.png")}).status_code == 404
    for operation in ("UPDATE selfies_ponto SET sha256 = sha256", "DELETE FROM selfies_ponto", "TRUNCATE selfies_ponto"):
        with pytest.raises(DBAPIError):
            with session.begin_nested():
                session.execute(text(operation))


@pytest.mark.postgres
def test_selfie_rejects_fake_image_oversize_and_foreign_owner(mobile, session, tenants):
    client, auth, tenant, device = mobile
    item = payload(tenant, device)
    send(mobile, item)
    url = "/api/mobile/marcacoes/" + item["evento_cliente_id"] + "/selfie"
    for content, status in ((b"not an image", 422), (b"x" * (2 * 1024 * 1024 + 1), 413)):
        response = client.post(url, headers=auth(),
            data={"selfie": (io.BytesIO(content), "image.png")})
        assert response.status_code == status
    foreign = tenants[1]
    assert client.post(url, headers=auth(empresa_id=foreign.company.id, usuario_id=foreign.user.id),
        data={"selfie": (io.BytesIO(picture()), "image.png")}).status_code == 404
    assert session.scalar(select(func.count()).select_from(SelfiesPonto)) == 0


@pytest.mark.postgres
def test_limits_bad_context_and_missing_mutation_routes(mobile, pg_app):
    client, auth, tenant, device = mobile
    for body in (None, [], {"marcacoes": []}, {"marcacoes": [], "empresa_id": str(tenant.company.id)}):
        assert client.post("/api/mobile/marcacoes/lote", json=body, headers=auth()).status_code == 400
    old_limit = pg_app.config["PONTO_MAX_LOTE"]
    pg_app.config["PONTO_MAX_LOTE"] = 1
    try:
        assert client.post("/api/mobile/marcacoes/lote", json=[payload(tenant, device)] * 2, headers=auth()).status_code == 413
    finally:
        pg_app.config["PONTO_MAX_LOTE"] = old_limit
    assert client.post("/api/mobile/marcacoes/lote", headers={**auth(), "Content-Type": "application/json"},
        data=b" " * (5 * 1024 * 1024 + 1)).status_code == 413
    for method in ("put", "patch", "delete"):
        assert getattr(client, method)("/api/mobile/marcacoes/lote", headers=auth()).status_code == 405


@pytest.mark.postgres
def test_commit_failure_does_not_acknowledge_uncommitted_points(mobile, session, monkeypatch):
    _, _, tenant, device = mobile
    def fail():
        raise OperationalError("commit", {}, Exception("database down"))
    with monkeypatch.context() as patch:
        patch.setattr(session, "commit", fail)
        response, body = send(mobile, payload(tenant, device))
    assert response.status_code == 503 and "resultados" not in body
    assert session.scalar(select(func.count()).select_from(RegistrosPonto)) == 0


@pytest.mark.parametrize("changes", [
    {"ocorrido_em": "2020-01-01T08:00:00"},
    {"registrado_offline": "true"}, {"desvio_relogio_segundos": True},
    {"desvio_relogio_segundos": 2**64}, {"posicao": {"latitude": True, "longitude": 0}},
    {"posicao": {"latitude": float("nan"), "longitude": 0}},
    {"posicao": {"latitude": 10**400, "longitude": 0}},
    {"distancia_centro_metros": 0}, {"situacao": "Aceita"},
])
def test_payload_rejects_spoofed_or_malformed_data(changes):
    from types import SimpleNamespace
    tenant = SimpleNamespace(assignment=SimpleNamespace(id=uuid.uuid4()))
    with pytest.raises(PontoError):
        validar_marcacao(payload(tenant, uuid.uuid4(), **changes))


@contextmanager
def concurrent_app(revision="head"):
    uri = os.getenv("TEST_DATABASE_URL")
    if not uri:
        pytest.skip("Defina TEST_DATABASE_URL.")
    url = make_url(uri).set(drivername="postgresql+psycopg2")
    schema = "test_w09_race_" + uuid.uuid4().hex
    engine = create_engine(url)
    with engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    scoped_url = url.update_query_dict({"options": "-c search_path=" + schema})
    application = create_app({"TESTING": True, "SQLALCHEMY_DATABASE_URI": scoped_url,
        "JWT_SECRET_KEY": "x" * 64, "SUPABASE_URL": "", "SUPABASE_KEY": "", "SUPABASE_PUBLISHABLE_KEY": ""})
    try:
        with application.app_context():
            upgrade(directory=str(Path(__file__).resolve().parents[1] / "migrations"), revision=revision)
        yield application
    finally:
        with application.app_context():
            db.session.remove()
            db.engine.dispose()
        with engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        engine.dispose()


@pytest.mark.postgres
def test_simultaneous_deliveries_insert_exactly_one_row(capfd):
    from types import SimpleNamespace
    with concurrent_app() as application:
        with application.app_context():
            company = Empresas(razao_social="Concorrência", cnpj="99999999999999")
            db.session.add(company)
            db.session.flush()
            user = Usuarios(empresa_id=company.id, nome="Funcionário", email="race@example.com", senha_hash="hash")
            sector = Setores(empresa_id=company.id, nome="Sede", latitude_centro=-8, longitude_centro=-35, raio_metros=100)
            schedule = Escalas(empresa_id=company.id, nome="Escala", tipo=TipoEscala.SEMANAL,
                carga_semanal_minutos=2400, regras={})
            db.session.add_all([user, sector, schedule])
            db.session.flush()
            employee = Funcionarios(empresa_id=company.id, usuario_id=user.id, nome=user.nome, matricula="001")
            db.session.add(employee)
            db.session.flush()
            assignment = Alocacoes(empresa_id=company.id, funcionario_id=employee.id, usuario_id=user.id, setor_id=sector.id,
                escala_id=schedule.id, data_inicio=datetime(2020, 1, 1).date())
            device = Dispositivos(empresa_id=company.id, usuario_id=user.id, nome="Celular")
            db.session.add_all([assignment, device])
            db.session.flush()
            empresa_id, usuario_id, device_id = company.id, user.id, device.id
            item = payload(SimpleNamespace(assignment=assignment), device.id)
            db.session.commit()
            engine = db.engine
        def worker():
            with application.app_context(), Session(engine) as worker_session:
                return RegistroPontoService.receber_lote(empresa_id, usuario_id, device_id, [item], session=worker_session)
        barrier = Barrier(6)
        def simultaneous_insert(connection, cursor, statement, parameters, context, executemany):
            if statement.startswith("INSERT INTO registros_ponto"):
                barrier.wait(timeout=15)
        event.listen(engine, "before_cursor_execute", simultaneous_insert)
        try:
            with ThreadPoolExecutor(max_workers=6) as pool:
                results = list(pool.map(lambda _: worker(), range(6)))
        finally:
            event.remove(engine, "before_cursor_execute", simultaneous_insert)
        assert all(status == 200 for _, status in results)
        assert sum(not body["resultados"][0]["duplicada"] for body, _ in results) == 1
        with application.app_context():
            assert db.session.scalar(select(func.count()).select_from(RegistrosPonto)) == 1
            with pytest.raises(SystemExit) as blocked:
                downgrade(directory=str(Path(__file__).resolve().parents[1] / "migrations"), revision="0001")
            assert blocked.value.code == 1
            assert "Downgrade W01/W03 bloqueado" in capfd.readouterr().err
            assert db.session.scalar(select(func.count()).select_from(RegistrosPonto)) == 1
