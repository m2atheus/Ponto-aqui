"""W07: registro pessoal transacional e autorização do aparelho da sessão."""

import uuid

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from app import db
from app.models import Dispositivos, Empresas, PapelUsuario, TipoDispositivo, Usuarios


class DeviceError(ValueError):
    def __init__(self, codigo="DISPOSITIVO_NEGADO", mensagem="Dispositivo não autorizado.", status=403):
        super().__init__(mensagem)
        self.codigo, self.status = codigo, status

    def response(self):
        return {"erro": {"codigo": self.codigo, "mensagem": str(self)}}, self.status


def _uuid(valor):
    try:
        return uuid.UUID(str(valor))
    except (ValueError, TypeError, AttributeError):
        raise DeviceError() from None


class DeviceService:
    @staticmethod
    def validar_dispositivo(empresa_id, usuario_id, device_uuid, claims, *, session=None):
        """Read-only; UUID é identificador, nunca uma credencial de autenticação.

        O JWT deve conter dispositivo_id emitido pelo login confiável. Para
        relógios, deve conter também setor_id autorizado no futuro login de setor.
        """
        session = session if session is not None else db.session
        empresa_id, usuario_id, device_uuid = map(_uuid, (empresa_id, usuario_id, device_uuid))
        token_device = _uuid(claims.get("dispositivo_id"))
        usuario = session.scalar(select(Usuarios).join(Empresas, Empresas.id == Usuarios.empresa_id).where(
            Usuarios.empresa_id == empresa_id, Usuarios.id == usuario_id, Usuarios.ativo.is_(True),
            Empresas.id == empresa_id, Empresas.ativo.is_(True),
        ))
        dispositivo = session.scalar(select(Dispositivos).where(
            Dispositivos.empresa_id == empresa_id, Dispositivos.device_uuid == device_uuid,
            Dispositivos.id == token_device, Dispositivos.ativo.is_(True),
        ))
        if usuario is None or dispositivo is None:
            raise DeviceError()
        if "device_uuid" in claims and _uuid(claims["device_uuid"]) != device_uuid:
            raise DeviceError()
        if dispositivo.tipo == TipoDispositivo.PESSOAL:
            if usuario.papel != PapelUsuario.FUNCIONARIO or dispositivo.usuario_id != usuario_id:
                raise DeviceError()
        elif (usuario.papel != PapelUsuario.USUARIO_SETOR
              or dispositivo.setor_id != _uuid(claims.get("setor_id"))):
            raise DeviceError()
        return dispositivo

    @staticmethod
    def registrar_login_pessoal(empresa_id, usuario_id, device_uuid, nome, *, session=None):
        """Somente após AuthService conferir a senha; não é um endpoint de login.

        Confirma a transação antes de retornar sucesso. O caller deve emitir o
        JWT depois deste retorno, com dispositivo_id e device_uuid. Não chamar
        numa transação que contenha outras alterações pendentes.
        O lock no usuário serializa logins concorrentes; um UUID não é transferido
        a outro usuário/empresa. Repetir o login no mesmo aparelho é idempotente.
        """
        session = session if session is not None else db.session
        try:
            empresa_id, usuario_id, device_uuid = map(_uuid, (empresa_id, usuario_id, device_uuid))
            if not isinstance(nome, str) or not nome.strip() or len(nome.strip()) > 120:
                raise DeviceError("DADOS_INVALIDOS", "Nome deve conter entre 1 e 120 caracteres.", 400)
            usuario = session.scalar(select(Usuarios).join(Empresas, Empresas.id == Usuarios.empresa_id).where(
                Usuarios.empresa_id == empresa_id, Usuarios.id == usuario_id, Usuarios.ativo.is_(True),
                Usuarios.papel == PapelUsuario.FUNCIONARIO,
                Empresas.id == empresa_id, Empresas.ativo.is_(True),
            ).with_for_update(of=Usuarios))
            if usuario is None:
                raise DeviceError()
            dispositivo = session.scalar(select(Dispositivos).where(
                Dispositivos.empresa_id == empresa_id, Dispositivos.device_uuid == device_uuid,
            ).with_for_update())
            if dispositivo is not None and (
                dispositivo.usuario_id != usuario_id or dispositivo.tipo != TipoDispositivo.PESSOAL
            ):
                raise DeviceError()
            # Uma colisão de UUID entre empresas é impedida pela unique global;
            # não fazemos consulta sem empresa_id para descobrir seu proprietário.
            session.execute(update(Dispositivos).where(
                Dispositivos.empresa_id == empresa_id, Dispositivos.usuario_id == usuario_id,
                Dispositivos.tipo == TipoDispositivo.PESSOAL, Dispositivos.ativo.is_(True),
                Dispositivos.device_uuid != device_uuid,
            ).values(ativo=False))
            if dispositivo is None:
                dispositivo = Dispositivos(empresa_id=empresa_id, usuario_id=usuario_id,
                    device_uuid=device_uuid, tipo=TipoDispositivo.PESSOAL, nome=nome.strip())
                session.add(dispositivo)
            dispositivo.ativo = True
            dispositivo.nome = nome.strip()
            dispositivo.ultimo_acesso_em = db.func.clock_timestamp()
            session.flush()
            session.refresh(dispositivo)
            resultado = {"dispositivo": {
                "id": str(dispositivo.id), "device_uuid": str(dispositivo.device_uuid),
                "tipo": dispositivo.tipo.value, "ativo": dispositivo.ativo,
                "ultimo_acesso_em": dispositivo.ultimo_acesso_em.isoformat(),
            }}
            session.commit()
            return resultado, 200
        except DeviceError as error:
            session.rollback()
            return error.response()
        except IntegrityError:
            session.rollback()
            return DeviceError("DISPOSITIVO_INDISPONIVEL", "Não foi possível vincular este dispositivo.", 409).response()
        except SQLAlchemyError:
            session.rollback()
            return DeviceError("DISPOSITIVOS_INDISPONIVEIS", "Serviço de dispositivos indisponível.", 503).response()
