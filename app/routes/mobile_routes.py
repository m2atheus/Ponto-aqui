"""Transporte HTTP mobile; validações, queries e negócios ficam nos Services."""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app.services.registro_ponto_service import RegistroPontoService
from app.services.selfie_service import SelfieService

mobile_bp = Blueprint("mobile", __name__)


@mobile_bp.post("/marcacoes/lote")
@jwt_required()
def receber_lote():
    payload, status = RegistroPontoService.receber_lote(
        empresa_id=get_jwt().get("empresa_id"), usuario_id=get_jwt_identity(),
        dispositivo_token=get_jwt().get("dispositivo_id"),
        dados=request.get_json(silent=True),
    )
    return jsonify(payload), status


@mobile_bp.post("/marcacoes/<uuid:evento_id>/selfie")
@jwt_required()
def enviar_selfie(evento_id):
    payload, status = SelfieService.enviar(
        empresa_id=get_jwt().get("empresa_id"), usuario_id=get_jwt_identity(),
        dispositivo_token=get_jwt().get("dispositivo_id"), evento_id=evento_id,
        arquivo=request.files.get("selfie"),
    )
    return jsonify(payload), status
