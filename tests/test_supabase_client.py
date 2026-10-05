import httpx
import pytest
from supabase import Client

from app import create_app
from app.supabase_client import get_supabase_client


def configured_app(**overrides):
    config = {
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": "postgresql://test@localhost/test",
        "JWT_SECRET_KEY": "x" * 64,
        "SUPABASE_URL": "https://projeto-de-teste.supabase.co",
        "SUPABASE_KEY": "sb_publishable_chave_de_teste",
        "SUPABASE_PUBLISHABLE_KEY": "",
    }
    config.update(overrides)
    return create_app(config)


@pytest.fixture
def captured_requests(monkeypatch):
    requests = []

    def handle(request):
        requests.append(request)
        return httpx.Response(200, json=[], headers={"Content-Type": "application/json"})

    def create_http_client(**kwargs):
        return httpx.Client(transport=httpx.MockTransport(handle), **kwargs)

    monkeypatch.setattr("app.supabase_client.HttpClient", create_http_client)
    return requests


def test_sdk_is_optional_and_existing_factory_still_works(app):
    assert "supabase" in app.extensions
    with app.app_context():
        with pytest.raises(RuntimeError, match="SDK Supabase não configurado"):
            get_supabase_client()


@pytest.mark.parametrize("missing", ["SUPABASE_URL", "SUPABASE_KEY"])
def test_partial_configuration_fails_without_exposing_key(missing):
    with pytest.raises(RuntimeError, match="juntos") as error:
        configured_app(**{missing: ""})
    assert "sb_publishable_chave_de_teste" not in str(error.value)


@pytest.mark.parametrize("url", ["postgresql://localhost/banco", "https://", "https://[invalid"])
def test_invalid_api_url_fails_at_initialization(url):
    with pytest.raises(RuntimeError, match="URL HTTP"):
        configured_app(SUPABASE_URL=url)


def test_new_environment_variable_name_is_supported(captured_requests):
    app = configured_app(SUPABASE_KEY="", SUPABASE_PUBLISHABLE_KEY="sb_publishable_nova")
    with app.app_context():
        client = get_supabase_client()
        assert isinstance(client, Client)
        client.table("empresas").select("id").execute()
    assert captured_requests[0].headers["apikey"] == "sb_publishable_nova"


def test_publishable_variable_takes_precedence_over_compatibility_name(captured_requests):
    app = configured_app(SUPABASE_PUBLISHABLE_KEY="sb_publishable_preferida")
    with app.app_context():
        get_supabase_client().table("empresas").select("id").execute()
    assert captured_requests[0].headers["apikey"] == "sb_publishable_preferida"


def test_client_initialization_is_offline_and_http_transport_closes(captured_requests):
    app = configured_app()
    with app.app_context():
        client = get_supabase_client()
        assert get_supabase_client() is client
        assert captured_requests == []
        transport = client.options.httpx_client
        assert not transport.is_closed
        client.table("empresas").select("id").execute()
    assert transport.is_closed
    assert captured_requests[0].url.path == "/rest/v1/empresas"
    assert captured_requests[0].headers["apikey"] == "sb_publishable_chave_de_teste"
    assert "Authorization" not in captured_requests[0].headers


def test_authenticated_clients_are_not_shared_between_requests(captured_requests):
    app = configured_app()
    with app.test_request_context():
        first_client = get_supabase_client()
        first_client.postgrest.auth("token-do-primeiro-usuario")
        first_client.table("empresas").select("id").execute()
    with app.test_request_context():
        second_client = get_supabase_client()
        assert second_client is not first_client
        second_client.table("empresas").select("id").execute()
    assert captured_requests[0].headers["Authorization"] == "Bearer token-do-primeiro-usuario"
    assert "Authorization" not in captured_requests[1].headers


def test_multiple_applications_keep_their_own_project_credentials(captured_requests):
    first_app = configured_app()
    second_app = configured_app(
        SUPABASE_URL="https://outro-projeto.supabase.co",
        SUPABASE_KEY="sb_publishable_outro_projeto",
    )
    with first_app.app_context():
        get_supabase_client().table("empresas").select("id").execute()
    with second_app.app_context():
        get_supabase_client().table("empresas").select("id").execute()
    assert captured_requests[0].url.host == "projeto-de-teste.supabase.co"
    assert captured_requests[1].url.host == "outro-projeto.supabase.co"
    assert captured_requests[1].headers["apikey"] == "sb_publishable_outro_projeto"


def test_failed_initialization_closes_http_transport(monkeypatch, captured_requests):
    transports = []

    def fail(url, key, options):
        transports.append(options.httpx_client)
        raise RuntimeError("Falha simulada no SDK")

    monkeypatch.setattr("app.supabase_client.create_client", fail)
    with configured_app().app_context():
        with pytest.raises(RuntimeError, match="Falha simulada"):
            get_supabase_client()
    assert transports[0].is_closed


def test_factory_loads_project_dotenv_and_keeps_environment_precedence(monkeypatch, tmp_path):
    dotenv_file = tmp_path / ".env"
    dotenv_file.write_text(
        "DATABASE_URL=postgresql://test@localhost/test\n"
        "JWT_SECRET_KEY=segredo-do-arquivo\n"
        "SUPABASE_URL=https://dotenv.supabase.co\n"
        "SUPABASE_KEY=sb_publishable_dotenv\n",
        encoding="utf-8",
    )
    monkeypatch.setattr("app.ENV_FILE", dotenv_file)
    for name in ("DATABASE_URL", "SUPABASE_URL", "SUPABASE_KEY"):
        # Registra também a restauração quando a variável originalmente não existe.
        monkeypatch.setenv(name, "")
        monkeypatch.delenv(name)
    monkeypatch.setenv("JWT_SECRET_KEY", "segredo-do-ambiente")
    app = create_app()
    assert app.config["JWT_SECRET_KEY"] == "segredo-do-ambiente"
    assert app.config["SUPABASE_URL"] == "https://dotenv.supabase.co"
    assert app.config["SUPABASE_KEY"] == "sb_publishable_dotenv"
