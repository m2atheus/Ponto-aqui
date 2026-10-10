"""Transporte W06; autorização, consultas e validações pertencem aos Services."""
import io
from flask import Blueprint, current_app, jsonify, request, send_file
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app.services.feriado_service import FeriadoService
from app.services.afastamento_service import AfastamentoService
from app.services.anexo_afastamento_service import AnexoAfastamentoService
from app.services.equipe_service import EquipeService
from app.services.espelho_service import EspelhoService

w06_bp = Blueprint("w06", __name__)


@w06_bp.get("/feriados")
@jwt_required()
def feriados():
    payload, status = FeriadoService.listar(get_jwt_identity(), get_jwt().get("empresa_id"), request.args.to_dict())
    return jsonify(payload), status


@w06_bp.post("/feriados")
@jwt_required()
def criar_feriado():
    payload, status = FeriadoService.criar(get_jwt_identity(), get_jwt().get("empresa_id"), request.get_json(silent=True))
    return jsonify(payload), status


@w06_bp.put("/feriados/<uuid:alvo_id>")
@jwt_required()
def atualizar_feriado(alvo_id):
    payload, status = FeriadoService.atualizar(get_jwt_identity(), get_jwt().get("empresa_id"), alvo_id, request.get_json(silent=True))
    return jsonify(payload), status


@w06_bp.delete("/feriados/<uuid:alvo_id>")
@jwt_required()
def remover_feriado(alvo_id):
    payload, status = FeriadoService.remover(get_jwt_identity(), get_jwt().get("empresa_id"), alvo_id)
    return jsonify(payload), status


@w06_bp.get("/afastamentos")
@jwt_required()
def afastamentos():
    payload, status = AfastamentoService.listar(get_jwt_identity(), get_jwt().get("empresa_id"), request.args.to_dict())
    return jsonify(payload), status


@w06_bp.post("/afastamentos")
@jwt_required()
def criar_afastamento():
    request.max_content_length = current_app.config["MAX_ATTACHMENT_CONTENT_LENGTH"]
    payload, status = AfastamentoService.criar(get_jwt_identity(), get_jwt().get("empresa_id"),
        request.get_json(silent=True) if request.is_json else request.form.to_dict(),
        arquivo=request.files.get("anexo"), base_url=request.url_root)
    return jsonify(payload), status


@w06_bp.put("/afastamentos/<uuid:alvo_id>")
@jwt_required()
def atualizar_afastamento(alvo_id):
    request.max_content_length = current_app.config["MAX_ATTACHMENT_CONTENT_LENGTH"]
    payload, status = AfastamentoService.atualizar(get_jwt_identity(), get_jwt().get("empresa_id"), alvo_id,
        request.get_json(silent=True) if request.is_json else request.form.to_dict(),
        arquivo=request.files.get("anexo"), base_url=request.url_root)
    return jsonify(payload), status


@w06_bp.delete("/afastamentos/<uuid:alvo_id>")
@jwt_required()
def remover_afastamento(alvo_id):
    payload, status = AfastamentoService.remover(get_jwt_identity(), get_jwt().get("empresa_id"), alvo_id)
    return jsonify(payload), status


@w06_bp.get("/afastamentos/<uuid:alvo_id>/anexo")
@jwt_required()
def baixar_anexo(alvo_id):
    payload, status = AnexoAfastamentoService.baixar(get_jwt_identity(), get_jwt().get("empresa_id"), alvo_id)
    if status != 200:
        return jsonify(payload), status
    response = send_file(io.BytesIO(payload["conteudo"]), mimetype=payload["content_type"],
        download_name=payload["nome"], as_attachment=True, max_age=0)
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "sandbox"
    return response


@w06_bp.get("/equipe")
@jwt_required()
def equipe():
    payload, status = EquipeService.listar(get_jwt_identity(), get_jwt().get("empresa_id"))
    return jsonify(payload), status


@w06_bp.get("/relatorios/espelho")
@jwt_required()
def espelho():
    payload, status = EspelhoService.consultar(get_jwt_identity(), get_jwt().get("empresa_id"), request.args.to_dict())
    return jsonify(payload), status
