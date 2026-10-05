"""Transporte de autenticação; regras e consultas ficam no AuthService."""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required

from app.services.auth_service import AuthService


auth_bp = Blueprint("auth", __name__)


@auth_bp.post("/login")
def login():
    payload, status = AuthService.login(request.get_json(silent=True))
    return jsonify(payload), status


@auth_bp.get("/me")
@jwt_required()
def me():
    payload, status = AuthService.me(get_jwt_identity(), get_jwt())
    return jsonify(payload), status
