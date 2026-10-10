"""Blueprint web: transporte HTTP; consultas e validações ficam nos Services."""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app.services.application_service import ApplicationService
from app.services.supabase_service import SupabaseService
from app.services.empresa_service import EmpresaService
from app.services.funcionario_service import FuncionarioService
from app.services.alocacao_service import AlocacaoService
from app.services.dashboard_service import DashboardService
from .setor_routes import setor_bp
from .w06_routes import w06_bp
from .escala_routes import escala_bp

web_bp = Blueprint("web", __name__)
web_bp.register_blueprint(setor_bp, url_prefix="/setores")
web_bp.register_blueprint(w06_bp)
web_bp.register_blueprint(escala_bp, url_prefix="/escalas")


@web_bp.get("/dashboard")
@jwt_required()
def dashboard():
    payload, status = DashboardService.consultar(get_jwt_identity(), get_jwt().get("empresa_id"))
    return jsonify(payload), status


@web_bp.get("/alocacoes")
@jwt_required()
def listar_alocacoes():
    payload, status = AlocacaoService.listar(
        get_jwt_identity(), get_jwt().get("empresa_id"), request.args.get("funcionario_id"),
    )
    return jsonify(payload), status


@web_bp.post("/alocacoes")
@jwt_required()
def criar_alocacao():
    payload, status = AlocacaoService.criar(
        get_jwt_identity(), get_jwt().get("empresa_id"), request.get_json(silent=True),
    )
    return jsonify(payload), status


@web_bp.route("/alocacoes/<uuid:alocacao_id>", methods=["PUT", "PATCH"])
@jwt_required()
def encerrar_alocacao(alocacao_id):
    payload, status = AlocacaoService.encerrar(
        get_jwt_identity(), get_jwt().get("empresa_id"), alocacao_id, request.get_json(silent=True),
    )
    return jsonify(payload), status


@web_bp.get("/")
def index():
    payload, status = ApplicationService.obter_status()
    return jsonify(payload), status


@web_bp.get("/funcionarios")
@jwt_required()
def listar_funcionarios():
    payload, status = FuncionarioService.listar(get_jwt_identity(), get_jwt().get("empresa_id"))
    return jsonify(payload), status


@web_bp.post("/funcionarios")
@jwt_required()
def criar_funcionario():
    payload, status = FuncionarioService.criar(
        get_jwt_identity(), get_jwt().get("empresa_id"), request.get_json(silent=True),
    )
    return jsonify(payload), status


@web_bp.route("/funcionarios/<uuid:funcionario_id>", methods=["PUT", "PATCH"])
@jwt_required()
def atualizar_funcionario(funcionario_id):
    payload, status = FuncionarioService.atualizar(
        get_jwt_identity(), get_jwt().get("empresa_id"), funcionario_id, request.get_json(silent=True),
    )
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
