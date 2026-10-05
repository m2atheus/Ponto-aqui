import httpx
import pytest

from app import create_app


@pytest.fixture
def sdk_app():
    return create_app({
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": "postgresql://test@localhost/test",
        "JWT_SECRET_KEY": "x" * 64,
        "SUPABASE_URL": "https://projeto-de-teste.supabase.co",
        "SUPABASE_KEY": "sb_publishable_teste",
        "SUPABASE_PUBLISHABLE_KEY": "",
    })


def mock_supabase(monkeypatch, handler):
    def create_http_client(**kwargs):
        return httpx.Client(transport=httpx.MockTransport(handler), **kwargs)
    monkeypatch.setattr("app.supabase_client.HttpClient", create_http_client)


def test_root_and_web_index_use_same_service_without_network(app, monkeypatch):
    def unexpected_client(**kwargs):
        raise AssertionError("A página inicial não deve iniciar uma conexão externa.")
    monkeypatch.setattr("app.supabase_client.HttpClient", unexpected_client)
    client = app.test_client()
    for path in ("/", "/api/web/"):
        response = client.get(path)
        assert response.status_code == 200
        assert response.json == {
            "aplicacao": "Ponto Aqui", "status": "inicializada",
            "supabase_configurado": False,
        }


def test_supabase_status_without_configuration_returns_json(app):
    response = app.test_client().get("/api/web/supabase/status")
    assert response.status_code == 503
    assert response.json["status"] == "nao_configurado"


def test_supabase_status_checks_public_settings_without_reading_tenant_rows(sdk_app, monkeypatch):
    requests = []
    def handle(request):
        requests.append(request)
        return httpx.Response(200, json={"external": {}, "disable_signup": False})
    mock_supabase(monkeypatch, handle)
    response = sdk_app.test_client().get("/api/web/supabase/status")
    assert response.status_code == 200
    assert response.json == {"status": "ok", "servico": "supabase_api"}
    assert len(requests) == 1
    assert requests[0].url.path == "/auth/v1/settings"
    assert requests[0].headers["apikey"] == "sb_publishable_teste"
    assert "Authorization" not in requests[0].headers
    assert "empresas" not in response.get_data(as_text=True)


@pytest.mark.parametrize("status", [401, 403, 404, 500, 503])
def test_upstream_errors_do_not_expose_their_body_or_key(sdk_app, monkeypatch, status):
    mock_supabase(monkeypatch, lambda request: httpx.Response(
        status, json={"message": "informacao-interna-sb_publishable_teste"},
    ))
    response = sdk_app.test_client().get("/api/web/supabase/status")
    assert response.status_code == 503
    assert response.json["status"] == "indisponivel"
    assert "informacao-interna" not in response.get_data(as_text=True)
    assert "sb_publishable_teste" not in response.get_data(as_text=True)


def test_timeout_returns_controlled_service_response(sdk_app, monkeypatch):
    def timeout(request):
        raise httpx.ReadTimeout("Falha de rede", request=request)
    mock_supabase(monkeypatch, timeout)
    response = sdk_app.test_client().get("/api/web/supabase/status")
    assert response.status_code == 503
    assert response.json["status"] == "indisponivel"


@pytest.mark.parametrize("body", [[], {}, {"external": {}}, {"external": [], "disable_signup": False}])
def test_successful_http_response_must_be_a_valid_api_document(sdk_app, monkeypatch, body):
    mock_supabase(monkeypatch, lambda request: httpx.Response(200, json=body))
    response = sdk_app.test_client().get("/api/web/supabase/status")
    assert response.status_code == 503
    assert response.json["status"] == "resposta_invalida"


def test_invalid_json_returns_controlled_service_response(sdk_app, monkeypatch):
    mock_supabase(monkeypatch, lambda request: httpx.Response(200, text="not json"))
    response = sdk_app.test_client().get("/api/web/supabase/status")
    assert response.status_code == 503
    assert response.json["status"] == "indisponivel"
