"""Validação do contrato W09; nenhum dado derivado é confiado ao aparelho."""
import hashlib
import json
import math
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal

from app.models import TipoPonto


class PontoError(Exception):
    def __init__(self, codigo, mensagem, status=422):
        super().__init__(mensagem)
        self.codigo, self.mensagem, self.status = codigo, mensagem, status

    def response(self):
        return {"erro": {"codigo": self.codigo, "mensagem": self.mensagem}}, self.status


def parse_uuid(value, campo):
    if not isinstance(value, (str, uuid.UUID)):
        raise PontoError("DADOS_INVALIDOS", f"{campo} deve ser um UUID.")
    try:
        return uuid.UUID(str(value))
    except (ValueError, AttributeError):
        raise PontoError("DADOS_INVALIDOS", f"{campo} deve ser um UUID.") from None


def number(value, campo, minimo, maximo):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise PontoError("DADOS_INVALIDOS", f"{campo} deve ser numérico.")
    if (isinstance(value, float) and not math.isfinite(value)) or not minimo <= value <= maximo:
        raise PontoError("DADOS_INVALIDOS", f"{campo} está fora dos limites.")
    return Decimal(str(value))


@dataclass(frozen=True)
class Marcacao:
    evento_id: uuid.UUID
    alocacao_id: uuid.UUID
    dispositivo_id: uuid.UUID
    tipo: TipoPonto
    ocorrido_em: datetime
    offset_minutos: int
    desvio: int
    offline: bool
    latitude: Decimal | None
    longitude: Decimal | None
    precisao: Decimal | None
    payload_hash: str
    original: dict


def validar_marcacao(dados):
    campos = {"evento_cliente_id", "alocacao_id", "dispositivo_id", "tipo",
              "ocorrido_em", "desvio_relogio_segundos", "registrado_offline", "posicao"}
    obrigatorios = campos - {"posicao"}
    if not isinstance(dados, dict) or not obrigatorios <= dados.keys() or dados.keys() - campos:
        raise PontoError("DADOS_INVALIDOS", "Campos ausentes ou desconhecidos na marcação.")
    evento_id = parse_uuid(dados["evento_cliente_id"], "evento_cliente_id")
    alocacao_id = parse_uuid(dados["alocacao_id"], "alocacao_id")
    dispositivo_id = parse_uuid(dados["dispositivo_id"], "dispositivo_id")
    try:
        tipo = TipoPonto(dados["tipo"])
        horario = datetime.fromisoformat(dados["ocorrido_em"])
    except (ValueError, TypeError):
        raise PontoError("DADOS_INVALIDOS", "Tipo ou ocorrido_em inválido.") from None
    offset = horario.utcoffset()
    if offset is None or offset.total_seconds() % 60 or abs(offset.total_seconds()) > 840 * 60:
        raise PontoError("DADOS_INVALIDOS", "ocorrido_em exige timezone explícito válido.")
    try:
        horario_utc = horario.astimezone(timezone.utc)
    except (OverflowError, ValueError):
        raise PontoError("DADOS_INVALIDOS", "ocorrido_em fora dos limites.") from None
    desvio = dados["desvio_relogio_segundos"]
    if type(desvio) is not int or not -(2**63) <= desvio < 2**63:
        raise PontoError("DADOS_INVALIDOS", "desvio_relogio_segundos deve ser inteiro assinado.")
    if type(dados["registrado_offline"]) is not bool:
        raise PontoError("DADOS_INVALIDOS", "registrado_offline deve ser booleano.")
    posicao = dados.get("posicao")
    latitude = longitude = precisao = None
    if posicao is not None:
        if not isinstance(posicao, dict) or not {"latitude", "longitude"} <= posicao.keys() or posicao.keys() - {"latitude", "longitude", "precisao_metros"}:
            raise PontoError("DADOS_INVALIDOS", "Posição deve conter latitude e longitude.")
        latitude = number(posicao["latitude"], "latitude", -90, 90)
        longitude = number(posicao["longitude"], "longitude", -180, 180)
        if posicao.get("precisao_metros") is not None:
            precisao = number(posicao["precisao_metros"], "precisao_metros", 0, 9999999999.99)
    def decimal_text(value):
        return None if value is None else str(value.normalize())
    canonico = {
        "evento_cliente_id": str(evento_id), "alocacao_id": str(alocacao_id),
        "dispositivo_id": str(dispositivo_id), "tipo": tipo.value,
        "ocorrido_em": horario_utc.isoformat(), "offset_minutos": int(offset.total_seconds() // 60),
        "desvio_relogio_segundos": desvio, "registrado_offline": dados["registrado_offline"],
        "latitude": decimal_text(latitude), "longitude": decimal_text(longitude),
        "precisao_metros": decimal_text(precisao),
    }
    digest = hashlib.sha256(json.dumps(canonico, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return Marcacao(evento_id, alocacao_id, dispositivo_id, tipo, horario_utc,
                    canonico["offset_minutos"], desvio, dados["registrado_offline"],
                    latitude, longitude, precisao, digest, dados.copy())
