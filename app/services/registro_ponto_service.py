"""W09: lote independente por item, INSERT idempotente e confirmação após commit."""
import uuid
from datetime import timezone

from flask import current_app
from sqlalchemy import or_, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import SQLAlchemyError

from app import db
from app.models import Alocacoes, DispositivoUsuarios, DispositivoUsuarioSetores, Dispositivos, Empresas, OrigemPonto, PapelUsuario, RegistrosPonto, Setores, TipoDispositivo, Usuarios
from .geofencing_service import GeofencingService
from .ponto_payload import PontoError, parse_uuid, validar_marcacao


def contexto_funcionario(session, empresa_id, usuario_id):
    try:
        empresa_id = parse_uuid(empresa_id, "empresa_id")
        usuario_id = parse_uuid(usuario_id, "sub")
    except PontoError:
        raise PontoError("CONTEXTO_INVALIDO", "JWT sem contexto válido de empresa/usuário.", 401) from None
    usuario = session.scalar(select(Usuarios).join(Empresas, Empresas.id == Usuarios.empresa_id).where(
        Usuarios.id == usuario_id, Usuarios.empresa_id == empresa_id,
        Usuarios.ativo.is_(True), Empresas.id == empresa_id, Empresas.ativo.is_(True)))
    if usuario is None or usuario.papel != PapelUsuario.FUNCIONARIO:
        raise PontoError("ACESSO_NEGADO", "Funcionário não autorizado nesta empresa.", 403)
    return empresa_id, usuario_id


def dispositivo_autorizado(session, empresa_id, usuario_id, dispositivo_id, token_device, setor_id=None):
    try:
        token_device = parse_uuid(token_device, "dispositivo_id")
    except PontoError:
        return None
    if token_device != dispositivo_id:
        return None
    return session.scalar(select(Dispositivos.id).join(DispositivoUsuarios,
        (DispositivoUsuarios.dispositivo_id == Dispositivos.id) & (DispositivoUsuarios.empresa_id == Dispositivos.empresa_id)
    ).where(
        Dispositivos.id == dispositivo_id, Dispositivos.empresa_id == empresa_id,
        Dispositivos.ativo.is_(True), DispositivoUsuarios.empresa_id == empresa_id,
        DispositivoUsuarios.usuario_id == usuario_id, DispositivoUsuarios.ativo.is_(True),
        or_((Dispositivos.tipo == TipoDispositivo.PESSOAL) & (Dispositivos.usuario_id == usuario_id),
            (Dispositivos.tipo == TipoDispositivo.RELOGIO) & select(DispositivoUsuarioSetores.dispositivo_id).where(
                DispositivoUsuarioSetores.dispositivo_id == Dispositivos.id,
                DispositivoUsuarioSetores.empresa_id == empresa_id, DispositivoUsuarioSetores.usuario_id == usuario_id,
                DispositivoUsuarioSetores.setor_id == setor_id, DispositivoUsuarioSetores.ativo.is_(True)).exists()
            if setor_id is not None else db.false()),
    ))


def serializar(point, duplicada):
    return {
        "registro_id": str(point.id), "evento_cliente_id": str(point.evento_cliente_id),
        "situacao": point.situacao.value, "motivos": point.motivos,
        "persistida": True, "duplicada": duplicada,
        "ocorrido_em": point.ocorrido_em.astimezone(timezone.utc).isoformat(),
        "recebido_em": point.recebido_em.astimezone(timezone.utc).isoformat(),
        "offset_original_minutos": point.offset_original_minutos,
        "registrado_offline": point.registrado_offline,
        "desvio_relogio_segundos": point.desvio_relogio_segundos,
        "distancia_centro_metros": None if point.distancia_centro_metros is None else float(point.distancia_centro_metros),
    }


class RegistroPontoService:
    @staticmethod
    def receber_lote(empresa_id, usuario_id, dispositivo_token, dados, session=None):
        session = session if session is not None else db.session
        try:
            empresa_id, usuario_id = contexto_funcionario(session, empresa_id, usuario_id)
            if isinstance(dados, dict) and set(dados) == {"marcacoes"}:
                dados = dados["marcacoes"]
            if not isinstance(dados, list) or not dados:
                raise PontoError("LOTE_INVALIDO", "Envie um array não vazio de marcações.", 400)
            if len(dados) > current_app.config["PONTO_MAX_LOTE"]:
                raise PontoError("LOTE_GRANDE", "Lote excede o limite configurado.", 413)
            resultados = []
            for indice, item in enumerate(dados):
                try:
                    with session.begin_nested():
                        marcacao = validar_marcacao(item)
                        resultado, status = RegistroPontoService._salvar(
                            session, empresa_id, usuario_id, dispositivo_token, marcacao)
                except PontoError as error:
                    resultado, status = error.response()
                    resultado.update(persistida=False, evento_cliente_id=(
                        item.get("evento_cliente_id") if isinstance(item, dict) and isinstance(item.get("evento_cliente_id"), str) else None))
                resultados.append({"indice": indice, "http_status": status, **resultado})
            # Nada é confirmado ao app antes de o PostgreSQL confirmar a transação.
            session.commit()
            return {"resultados": resultados}, 207 if any(r["http_status"] >= 400 for r in resultados) else 200
        except PontoError as error:
            session.rollback()
            return error.response()
        except SQLAlchemyError:
            session.rollback()
            current_app.logger.error("Falha de banco ao persistir lote W09.")
            return {"erro": {"codigo": "PERSISTENCIA_INDISPONIVEL", "mensagem": "Lote não confirmado. Reenvie os mesmos UUIDs."}}, 503

    @staticmethod
    def _existente(session, empresa_id, usuario_id, marcacao):
        point = session.scalar(select(RegistrosPonto).where(
            RegistrosPonto.empresa_id == empresa_id,
            RegistrosPonto.evento_cliente_id == marcacao.evento_id))
        if point is None:
            return None
        if point.usuario_id != usuario_id or point.payload_hash != marcacao.payload_hash:
            raise PontoError("UUID_CONFLITANTE", "UUID já utilizado com outro conteúdo.", 409)
        return point

    @staticmethod
    def _salvar(session, empresa_id, usuario_id, token_device, marcacao):
        existente = RegistroPontoService._existente(session, empresa_id, usuario_id, marcacao)
        if existente is not None:
            return serializar(existente, True), 200
        setor = session.scalar(select(Setores).join(Alocacoes,
            (Alocacoes.setor_id == Setores.id) & (Alocacoes.empresa_id == Setores.empresa_id)).where(
            Alocacoes.id == marcacao.alocacao_id, Alocacoes.empresa_id == empresa_id,
            Alocacoes.usuario_id == usuario_id, Setores.empresa_id == empresa_id))
        if setor is None:
            raise PontoError("ALOCACAO_INVALIDA", "Alocação não encontrada para este funcionário.", 404)
        device = dispositivo_autorizado(session, empresa_id, usuario_id, marcacao.dispositivo_id, token_device, setor.id)
        situacao, motivos, distancia = GeofencingService.avaliar(marcacao, setor, device is not None)
        values = {
            "id": uuid.uuid4(), "empresa_id": empresa_id, "usuario_id": usuario_id,
            "enviado_por_id": usuario_id, "setor_id": setor.id, "alocacao_id": marcacao.alocacao_id,
            "evento_cliente_id": marcacao.evento_id, "payload_hash": marcacao.payload_hash,
            "tipo": marcacao.tipo, "origem": OrigemPonto.MOBILE, "ocorrido_em": marcacao.ocorrido_em,
            "offset_original_minutos": marcacao.offset_minutos, "desvio_relogio_segundos": marcacao.desvio,
            "registrado_offline": marcacao.offline, "dados_dispositivo": marcacao.original,
            "dispositivo_cliente_id": marcacao.dispositivo_id, "dispositivo_registrado_id": device,
            "situacao": situacao, "motivos": motivos,
            "politica_localizacao_validada": setor.politica_localizacao,
            "limite_desvio_validado_segundos": setor.limite_desvio_relogio_segundos,
            "latitude": marcacao.latitude, "longitude": marcacao.longitude, "precisao_metros": marcacao.precisao,
            "latitude_centro_validada": setor.latitude_centro, "longitude_centro_validada": setor.longitude_centro,
            "raio_validado_metros": setor.raio_metros, "distancia_centro_metros": distancia,
        }
        # As chaves por empresa e por funcionário coexistem (a segunda é alvo
        # da FK de selfies). Sem alvo, DO NOTHING cobre a disputa em ambas.
        point_id = session.scalar(insert(RegistrosPonto).values(**values).on_conflict_do_nothing().returning(RegistrosPonto.id))
        if point_id is None:
            point = RegistroPontoService._existente(session, empresa_id, usuario_id, marcacao)
            if point is None:
                raise SQLAlchemyError("Conflito em identificador interno; reenvio necessário.")
            return serializar(point, True), 200
        point = session.scalar(select(RegistrosPonto).where(
            RegistrosPonto.empresa_id == empresa_id, RegistrosPonto.usuario_id == usuario_id,
            RegistrosPonto.id == point_id))
        return serializar(point, False), 201
