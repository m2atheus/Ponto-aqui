"""Transporte HTTP mobile; validações, queries e negócios ficam nos Services."""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app.services.registro_ponto_service import RegistroPontoService
from app.services.selfie_service import SelfieService
from app.services.mobile_sync_service import MobileSyncService
from app.middleware.device_middleware import require_device_uuid

mobile_bp = Blueprint("mobile", __name__)
mobile_v1_bp = Blueprint("mobile_v1", __name__)


@mobile_v1_bp.get("/sync")
@jwt_required()
@require_device_uuid
def sincronizar():
    payload, status = MobileSyncService.sincronizar(
        empresa_id=get_jwt().get("empresa_id"), usuario_id=get_jwt_identity(),
        device_uuid=request.headers.get("X-Device-UUID"), claims=get_jwt(),
        setor_id=request.args.get("setor_id"),
    )
    response = jsonify(payload)
    response.status_code = status
    response.headers["Cache-Control"] = "private, no-store"
    if "server_timestamp" in payload:
        response.headers["X-Server-Timestamp"] = payload["server_timestamp"]
    return response


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
