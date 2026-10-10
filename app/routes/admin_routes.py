"""Transporte HTTP dos ajustes manuais; regras e autorização ficam no Service."""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app.services.ajuste_ponto_service import AjustePontoService


admin_bp = Blueprint("admin", __name__)


@admin_bp.post("/ponto-manual")
@jwt_required()
def inserir_ponto_manual():
    payload, status = AjustePontoService.inserir_ponto_manual_rh(
        get_jwt_identity(), get_jwt().get("empresa_id"), request.get_json(silent=True),
    )
    return jsonify(payload), status


@admin_bp.post("/ponto-correcao")
@jwt_required()
def corrigir_ponto_existente():
    payload, status = AjustePontoService.corrigir_ponto_existente_rh(
        get_jwt_identity(), get_jwt().get("empresa_id"), request.get_json(silent=True),
    )
    return jsonify(payload), status
