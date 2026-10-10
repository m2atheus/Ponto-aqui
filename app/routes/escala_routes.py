from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required
from app.services.escala_service import EscalaService

escala_bp = Blueprint("escalas", __name__)

@escala_bp.get("")
@jwt_required()
def listar():
    payload, status = EscalaService.listar(get_jwt_identity(), get_jwt().get("empresa_id"))
    return jsonify(payload), status

@escala_bp.post("")
@jwt_required()
def criar():
    payload, status = EscalaService.criar(get_jwt_identity(), get_jwt().get("empresa_id"), request.get_json(silent=True))
    return jsonify(payload), status

@escala_bp.put("/<uuid:alvo_id>")
@jwt_required()
def atualizar(alvo_id):
    payload, status = EscalaService.atualizar(get_jwt_identity(), get_jwt().get("empresa_id"), alvo_id, request.get_json(silent=True))
    return jsonify(payload), status

@escala_bp.delete("/<uuid:alvo_id>")
@jwt_required()
def remover(alvo_id):
    payload, status = EscalaService.remover(get_jwt_identity(), get_jwt().get("empresa_id"), alvo_id)
    return jsonify(payload), status
