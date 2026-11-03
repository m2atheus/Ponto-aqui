"""Controllers W02: autenticação e transporte HTTP, sem regras de negócio."""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app.services.setor_service import SetorService

setor_bp = Blueprint("setores", __name__)


@setor_bp.get("/busca")
@jwt_required()
def buscar_setores():
    payload, status = SetorService.buscar(
        get_jwt_identity(), get_jwt().get("empresa_id"), request.args.get("q"),
    )
    return jsonify(payload), status


@setor_bp.get("")
@jwt_required()
def listar_setores():
    payload, status = SetorService.listar(get_jwt_identity(), get_jwt().get("empresa_id"))
    return jsonify(payload), status


@setor_bp.post("")
@jwt_required()
def criar_setor():
    payload, status = SetorService.criar_setor(
        get_jwt_identity(), get_jwt().get("empresa_id"), request.get_json(silent=True),
    )
    return jsonify(payload), status


@setor_bp.put("/<uuid:setor_id>")
@jwt_required()
def atualizar_setor(setor_id):
    payload, status = SetorService.atualizar_setor(
        get_jwt_identity(), get_jwt().get("empresa_id"), setor_id, request.get_json(silent=True),
    )
    return jsonify(payload), status


@setor_bp.delete("/<uuid:setor_id>")
@jwt_required()
def deletar_setor(setor_id):
    payload, status = SetorService.deletar_setor(
        get_jwt_identity(), get_jwt().get("empresa_id"), setor_id,
    )
    return jsonify(payload), status
