"""Transporte HTTP dos ajustes manuais; regras e autorização ficam no Service."""

import io

from flask import Blueprint, jsonify, request, send_file
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app.services.ajuste_ponto_service import AjustePontoService
from app.services.selfie_service import SelfieService
from app.services.device_service import DeviceService


admin_bp = Blueprint("admin", __name__)


@admin_bp.get("/funcionarios/<uuid:funcionario_id>/dispositivos")
@jwt_required()
def listar_dispositivos(funcionario_id):
    payload, status = DeviceService.listar_funcionario(
        get_jwt_identity(), get_jwt().get("empresa_id"), funcionario_id)
    return jsonify(payload), status


@admin_bp.post("/funcionarios/<uuid:funcionario_id>/dispositivos")
@jwt_required()
def vincular_dispositivo(funcionario_id):
    payload, status = DeviceService.vincular_manual(
        get_jwt_identity(), get_jwt().get("empresa_id"), funcionario_id, request.get_json(silent=True))
    return jsonify(payload), status


@admin_bp.post("/funcionarios/<uuid:funcionario_id>/dispositivos/<uuid:dispositivo_id>/revogar")
@jwt_required()
def revogar_dispositivo(funcionario_id, dispositivo_id):
    payload, status = DeviceService.revogar_manual(
        get_jwt_identity(), get_jwt().get("empresa_id"), funcionario_id, dispositivo_id)
    return jsonify(payload), status


@admin_bp.get("/pontos/<uuid:registro_id>/selfie")
@jwt_required()
def visualizar_selfie(registro_id):
    payload, status = SelfieService.baixar_admin(
        get_jwt_identity(), get_jwt().get("empresa_id"), registro_id,
    )
    if status != 200:
        return jsonify(payload), status
    response = send_file(io.BytesIO(payload["conteudo"]), mimetype=payload["content_type"],
        download_name="selfie", max_age=0)
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@admin_bp.post("/pontos/<uuid:registro_id>/invalidar")
@jwt_required()
def invalidar_marcacao(registro_id):
    payload, status = AjustePontoService.invalidar_marcacao(
        get_jwt_identity(), get_jwt().get("empresa_id"), registro_id,
        request.get_json(silent=True),
    )
    return jsonify(payload), status


@admin_bp.post("/pontos/<uuid:registro_id>/aprovar")
@jwt_required()
def aprovar_marcacao(registro_id):
    payload, status = AjustePontoService.aprovar_marcacao(
        get_jwt_identity(), get_jwt().get("empresa_id"), registro_id,
        request.get_json(silent=True),
    )
    return jsonify(payload), status


@admin_bp.post("/pontos/<uuid:registro_id>/reaprovar")
@jwt_required()
def reaprovar_marcacao(registro_id):
    payload, status = AjustePontoService.reaprovar_marcacao(
        get_jwt_identity(), get_jwt().get("empresa_id"), registro_id,
        request.get_json(silent=True),
    )
    return jsonify(payload), status


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
