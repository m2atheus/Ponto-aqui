"""Blueprint web: transporte HTTP; consultas e validações ficam nos Services."""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app.services.application_service import ApplicationService
from app.services.supabase_service import SupabaseService
from app.services.empresa_service import EmpresaService

web_bp = Blueprint("web", __name__)


@web_bp.get("/")
def index():
    payload, status = ApplicationService.obter_status()
    return jsonify(payload), status


@web_bp.get("/supabase/status")
def supabase_status():
    payload, status = SupabaseService.verificar_conexao()
    return jsonify(payload), status


@web_bp.get("/empresas")
@jwt_required()
def listar_empresas():
    payload, status = EmpresaService.listar(get_jwt_identity(), get_jwt().get("empresa_id"))
    return jsonify(payload), status


@web_bp.post("/empresas")
@jwt_required()
def criar_empresa():
    payload, status = EmpresaService.criar(get_jwt_identity(), get_jwt().get("empresa_id"), request.get_json(silent=True))
    return jsonify(payload), status


@web_bp.route("/empresas/<uuid:empresa_id>", methods=["PUT", "PATCH"])
@jwt_required()
def atualizar_empresa(empresa_id):
    payload, status = EmpresaService.atualizar(get_jwt_identity(), get_jwt().get("empresa_id"),
        empresa_id, request.get_json(silent=True))
    return jsonify(payload), status
