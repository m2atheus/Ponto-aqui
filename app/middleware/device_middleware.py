"""W07: autorização de aparelho no sync W08; não aplicado às marcações W09."""

from functools import wraps

from flask import current_app, g, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, verify_jwt_in_request
from sqlalchemy.exc import SQLAlchemyError

from app import db
from app.services.device_service import DeviceError, DeviceService


def require_device_uuid(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        # JWT ausente/expirado mantém o contrato 401 da API. Com sessão válida,
        # header ausente/inválido ou aparelho não autorizado retornam 403.
        verify_jwt_in_request()
        try:
            dispositivo = DeviceService.validar_dispositivo(
                empresa_id=get_jwt().get("empresa_id"), usuario_id=get_jwt_identity(),
                device_uuid=request.headers.get("X-Device-UUID"), claims=get_jwt(),
            )
        except DeviceError as error:
            payload, status = error.response()
            return jsonify(payload), status
        except SQLAlchemyError:
            db.session.rollback()
            current_app.logger.error("Falha ao verificar dispositivo mobile.")
            return jsonify({"erro": {"codigo": "DISPOSITIVOS_INDISPONIVEIS",
                "mensagem": "Serviço de dispositivos indisponível."}}), 503
        g.dispositivo = dispositivo
        return view(*args, **kwargs)
    return wrapped
