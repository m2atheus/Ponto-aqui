"""Transporte HTTP para geração de acesso do funcionário pelo RH."""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app.services.funcionario_service import FuncionarioService


funcionario_bp = Blueprint("funcionarios_v1", __name__)


@funcionario_bp.post("/<uuid:funcionario_id>/vincular-acesso")
@jwt_required()
def vincular_acesso(funcionario_id):
    payload, status = FuncionarioService.vincular_acesso(
        get_jwt_identity(), get_jwt().get("empresa_id"),
        funcionario_id, request.get_json(silent=True),
    )
    response = jsonify(payload)
    response.headers["Cache-Control"] = "private, no-store"
    return response, status
