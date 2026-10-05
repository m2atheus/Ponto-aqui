"""Integração do SDK Supabase com o ciclo de vida de contextos Flask."""

from urllib.parse import urlsplit

from flask import Flask, current_app, g
from httpx import Client as HttpClient, Request
from supabase import Client, ClientOptions, create_client


def _prepare_request(request: Request) -> None:
    # Chaves modernas identificam a aplicação no header apikey. Elas não são
    # JWTs. Preserva Authorization quando contém um token de usuário real.
    authorization = request.headers.get("Authorization", "")
    if authorization.startswith(("Bearer sb_publishable_", "Bearer sb_secret_")):
        request.headers.pop("Authorization", None)


class SupabaseExtension:
    """Configuração por aplicação; cliente e transporte por contexto Flask."""

    def init_app(self, app: Flask) -> None:
        url = (app.config.get("SUPABASE_URL") or "").strip()
        key = (
            app.config.get("SUPABASE_PUBLISHABLE_KEY")
            or app.config.get("SUPABASE_KEY")
            or ""
        ).strip()
        if bool(url) != bool(key):
            raise RuntimeError(
                "Configure SUPABASE_URL e SUPABASE_KEY "
                "(ou SUPABASE_PUBLISHABLE_KEY) juntos."
            )
        if url:
            try:
                parsed = urlsplit(url)
                valid = parsed.scheme in {"http", "https"} and bool(parsed.hostname)
            except ValueError:
                valid = False
            if not valid:
                raise RuntimeError("SUPABASE_URL deve ser uma URL HTTP(S) válida.")

        app.config["SUPABASE_URL"] = url
        app.config["SUPABASE_KEY"] = key
        app.extensions["supabase"] = self
        app.teardown_appcontext(self._close_client)

    def get_client(self) -> Client:
        client = g.get("_ponto_supabase_client")
        if client is not None:
            return client

        url = current_app.config["SUPABASE_URL"]
        key = current_app.config["SUPABASE_KEY"]
        if not url or not key:
            raise RuntimeError(
                "SDK Supabase não configurado. Preencha SUPABASE_URL e SUPABASE_KEY "
                "(ou SUPABASE_PUBLISHABLE_KEY)."
            )

        http_client = HttpClient(
            timeout=10,
            event_hooks={"request": [_prepare_request]},
        )
        try:
            client = create_client(
                url,
                key,
                options=ClientOptions(
                    persist_session=False,
                    auto_refresh_token=False,
                    httpx_client=http_client,
                    postgrest_client_timeout=10,
                    storage_client_timeout=10,
                ),
            )
        except Exception:
            http_client.close()
            raise

        g._ponto_supabase_client = client
        g._ponto_supabase_http_client = http_client
        return client

    @staticmethod
    def _close_client(exception=None) -> None:
        g.pop("_ponto_supabase_client", None)
        http_client = g.pop("_ponto_supabase_http_client", None)
        if http_client is not None:
            http_client.close()


def get_supabase_client() -> Client:
    """Obtém o cliente do contexto atual para uso na camada de Services."""
    return current_app.extensions["supabase"].get_client()
