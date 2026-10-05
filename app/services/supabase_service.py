"""Diagnóstico HTTP do Supabase, sem consultar registros de empresas."""

from flask import current_app
from httpx import HTTPError

from app.supabase_client import get_supabase_client


class SupabaseService:
    @staticmethod
    def verificar_conexao() -> tuple[dict, int]:
        if not (
            current_app.config.get("SUPABASE_URL")
            and current_app.config.get("SUPABASE_KEY")
        ):
            return {
                "status": "nao_configurado",
                "mensagem": "Configure SUPABASE_URL e SUPABASE_KEY no backend.",
            }, 503

        client = get_supabase_client()
        try:
            # As configurações públicas do Auth verificam URL/chave sem ler
            # usuários ou tabelas. O diagnóstico não exige uma chave secreta.
            response = client.options.httpx_client.get(
                str(client.auth_url).rstrip("/") + "/settings",
                headers={
                    **client.options.headers,
                    "Accept": "application/json",
                },
            )
            response.raise_for_status()
            schema = response.json()
        except (HTTPError, ValueError):
            # Não devolvemos corpos ou exceções externas que possam conter
            # dados de configuração. Uma indisponibilidade gera JSON estável.
            return {
                "status": "indisponivel",
                "mensagem": "Não foi possível verificar a API do Supabase.",
            }, 503

        if not isinstance(schema, dict) or not (
            isinstance(schema.get("external"), dict)
            and isinstance(schema.get("disable_signup"), bool)
        ):
            return {
                "status": "resposta_invalida",
                "mensagem": "A URL configurada não retornou as configurações do Supabase.",
            }, 503

        return {"status": "ok", "servico": "supabase_api"}, 200
