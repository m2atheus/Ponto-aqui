"""Blueprint web: transporte HTTP; consultas e validações ficam nos Services."""

from flask import Blueprint, jsonify

from app.services.application_service import ApplicationService
from app.services.supabase_service import SupabaseService

web_bp = Blueprint("web", __name__)


@web_bp.get("/")
def index():
    payload, status = ApplicationService.obter_status()
    return jsonify(payload), status


@web_bp.get("/supabase/status")
def supabase_status():
    payload, status = SupabaseService.verificar_conexao()
    return jsonify(payload), status
