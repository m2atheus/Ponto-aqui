"""Informações públicas da aplicação, sem consultas a dados de empresas."""

from flask import current_app


class ApplicationService:
    @staticmethod
    def obter_status() -> tuple[dict, int]:
        return {
            "aplicacao": "Ponto Aqui",
            "status": "inicializada",
            "supabase_configurado": bool(
                current_app.config.get("SUPABASE_URL")
                and current_app.config.get("SUPABASE_KEY")
            ),
        }, 200
