"""W07: registro pessoal transacional e autorização do aparelho da sessão."""

import uuid
from datetime import datetime, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import or_, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from app import db
from app.models import Alocacoes, DispositivoUsuarios, DispositivoUsuarioSetores, Dispositivos, Empresas, Funcionarios, PapelUsuario, Setores, TipoDispositivo, Usuarios
from .rh_access import GestaoError, executar_empresa, executar_rh
from .w06_validation import funcionario, identificador


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
    def _hoje(session, empresa):
        fuso = session.scalar(select(Empresas.fuso_horario).where(Empresas.id == empresa))
        try:
            return datetime.now(timezone.utc).astimezone(ZoneInfo(fuso)).date()
        except (ZoneInfoNotFoundError, ValueError, TypeError):
            raise GestaoError("Fuso da empresa indisponível.", 503, "FUSO_INVALIDO") from None

    @staticmethod
    def _setores(session, empresa, alvo):
        hoje = DeviceService._hoje(session, empresa)
        return session.execute(select(Setores.id, Setores.nome).join(Alocacoes,
            (Alocacoes.setor_id == Setores.id) & (Alocacoes.empresa_id == Setores.empresa_id)
        ).where(Setores.empresa_id == empresa, Setores.ativo.is_(True),
            Alocacoes.empresa_id == empresa, Alocacoes.funcionario_id == alvo.id,
            Alocacoes.data_inicio <= hoje, or_(Alocacoes.data_fim.is_(None), Alocacoes.data_fim >= hoje)
        ).distinct().order_by(Setores.nome, Setores.id)).all()

    @staticmethod
    def _json(aparelho, vinculo=None, setores=None, setor_contexto=None):
        ativo = aparelho.ativo and (vinculo is None or vinculo.ativo)
        return {"id": str(aparelho.id), "empresa_id": str(aparelho.empresa_id),
            "device_uuid": str(aparelho.device_uuid), "tipo": TipoDispositivo(aparelho.tipo).value,
            "nome_identificador": aparelho.nome, "ativo": ativo,
            "status": "Ativo" if ativo else "Inativo",
            "setor_id": str(setor_contexto or aparelho.setor_id) if (setor_contexto or aparelho.setor_id) else None,
            "setores": setores or [],
            "ultimo_acesso_em": aparelho.ultimo_acesso_em.isoformat() if aparelho.ultimo_acesso_em else None}

    @staticmethod
    def listar_funcionario(usuario_id, empresa_id, funcionario_id, session=None):
        def operacao(session, empresa):
            alvo = funcionario(session, empresa, funcionario_id=funcionario_id)
            setores = DeviceService._setores(session, empresa, alvo)
            linhas = [] if alvo.usuario_id is None else session.execute(select(Dispositivos, DispositivoUsuarios).join(
                DispositivoUsuarios, (DispositivoUsuarios.dispositivo_id == Dispositivos.id)
                & (DispositivoUsuarios.empresa_id == Dispositivos.empresa_id)
            ).where(Dispositivos.empresa_id == empresa, DispositivoUsuarios.empresa_id == empresa,
                DispositivoUsuarios.usuario_id == alvo.usuario_id).order_by(Dispositivos.criado_em.desc(), Dispositivos.id)).all()
            escopos = DeviceService._escopos_json(session, empresa, alvo.usuario_id, [d.id for d, _ in linhas])
            return {"dispositivos": [DeviceService._json(d, v, escopos.get(d.id, [])) for d, v in linhas],
                "setores_disponiveis": [{"id": str(s.id), "nome": s.nome} for s in setores],
                "tem_acesso_app": alvo.usuario_id is not None}, 200
        return executar_empresa(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def _escopos_json(session, empresa, usuario, aparelhos):
        resultado = {}
        if usuario is None or not aparelhos:
            return resultado
        rows = session.execute(select(DispositivoUsuarioSetores.dispositivo_id, Setores.id,
            Setores.nome, DispositivoUsuarioSetores.ativo).join(Setores,
                (Setores.id == DispositivoUsuarioSetores.setor_id) & (Setores.empresa_id == DispositivoUsuarioSetores.empresa_id)
            ).where(DispositivoUsuarioSetores.empresa_id == empresa, Setores.empresa_id == empresa,
                DispositivoUsuarioSetores.usuario_id == usuario, DispositivoUsuarioSetores.dispositivo_id.in_(aparelhos)
            ).order_by(Setores.nome, Setores.id)).all()
        for row in rows:
            resultado.setdefault(row.dispositivo_id, []).append({"id": str(row.id), "nome": row.nome, "ativo": row.ativo})
        return resultado

    @staticmethod
    def _autorizar_setor(session, empresa, aparelho, usuario, setor, autor):
        escopo = session.scalar(select(DispositivoUsuarioSetores).where(
            DispositivoUsuarioSetores.empresa_id == empresa, DispositivoUsuarioSetores.dispositivo_id == aparelho,
            DispositivoUsuarioSetores.usuario_id == usuario, DispositivoUsuarioSetores.setor_id == setor
        ).with_for_update().execution_options(populate_existing=True))
        if escopo is None:
            escopo = DispositivoUsuarioSetores(empresa_id=empresa, dispositivo_id=aparelho, usuario_id=usuario, setor_id=setor)
            session.add(escopo)
        escopo.ativo = True
        escopo.autorizado_por_id = autor

    @staticmethod
    def setores_autorizados(session, empresa, usuario, aparelho):
        hoje = DeviceService._hoje(session, empresa)
        return session.execute(select(Setores.id, Setores.nome).join(DispositivoUsuarioSetores,
            (DispositivoUsuarioSetores.setor_id == Setores.id) & (DispositivoUsuarioSetores.empresa_id == Setores.empresa_id)
        ).join(DispositivoUsuarios,
            (DispositivoUsuarios.dispositivo_id == DispositivoUsuarioSetores.dispositivo_id)
            & (DispositivoUsuarios.empresa_id == DispositivoUsuarioSetores.empresa_id)
            & (DispositivoUsuarios.usuario_id == DispositivoUsuarioSetores.usuario_id)
        ).join(Alocacoes, (Alocacoes.empresa_id == DispositivoUsuarioSetores.empresa_id)
            & (Alocacoes.usuario_id == DispositivoUsuarioSetores.usuario_id) & (Alocacoes.setor_id == Setores.id)
        ).join(Funcionarios, (Funcionarios.id == Alocacoes.funcionario_id)
            & (Funcionarios.empresa_id == Alocacoes.empresa_id) & (Funcionarios.usuario_id == usuario)
        ).join(Usuarios, (Usuarios.id == Funcionarios.usuario_id) & (Usuarios.empresa_id == Funcionarios.empresa_id)
        ).where(Setores.empresa_id == empresa, Setores.ativo.is_(True),
            DispositivoUsuarioSetores.empresa_id == empresa, DispositivoUsuarioSetores.usuario_id == usuario,
            DispositivoUsuarioSetores.dispositivo_id == aparelho, DispositivoUsuarioSetores.ativo.is_(True),
            DispositivoUsuarios.ativo.is_(True), Funcionarios.ativo.is_(True),
            Usuarios.ativo.is_(True), Usuarios.papel == PapelUsuario.FUNCIONARIO,
            Alocacoes.data_inicio <= hoje, or_(Alocacoes.data_fim.is_(None), Alocacoes.data_fim >= hoje)
        ).distinct().order_by(Setores.nome, Setores.id)).all()

    @staticmethod
    def _alvo_ativo(session, empresa, funcionario_id):
        alvo = funcionario(session, empresa, funcionario_id=funcionario_id, lock=True, ativo=True)
        if alvo.usuario_id is None:
            raise GestaoError("Gere o acesso ao aplicativo antes de autorizar aparelhos.", 400, "FUNCIONARIO_SEM_USUARIO")
        conta = session.scalar(select(Usuarios).where(Usuarios.id == alvo.usuario_id,
            Usuarios.empresa_id == empresa, Usuarios.ativo.is_(True), Usuarios.papel == PapelUsuario.FUNCIONARIO
        ).with_for_update())
        if conta is None:
            raise GestaoError("A conta do funcionário precisa estar ativa.")
        return alvo

    @staticmethod
    def vincular_manual(usuario_id, empresa_id, funcionario_id, dados, session=None):
        def operacao(session, empresa):
            if not isinstance(dados, dict) or dados.keys() - {"device_uuid", "tipo", "nome_identificador", "setor_id", "converter_para_relogio"}:
                raise GestaoError("Informe código, tipo e nome do aparelho.")
            codigo = identificador(dados.get("device_uuid"), "device_uuid")
            try:
                tipo = TipoDispositivo(dados.get("tipo"))
            except (ValueError, TypeError):
                raise GestaoError("tipo deve ser PESSOAL ou RELOGIO.") from None
            converter = dados.get("converter_para_relogio", False)
            if type(converter) is not bool or (converter and tipo != TipoDispositivo.RELOGIO):
                raise GestaoError("converter_para_relogio deve ser booleano e só vale para RELOGIO.")
            nome = dados.get("nome_identificador")
            if nome is None:
                nome = "Aparelho pessoal" if tipo == TipoDispositivo.PESSOAL else "Relógio compartilhado"
            if not isinstance(nome, str) or not 1 <= len(nome.strip()) <= 120:
                raise GestaoError("O nome do aparelho deve conter entre 1 e 120 caracteres.")
            alvo = DeviceService._alvo_ativo(session, empresa, funcionario_id)
            existente = session.scalar(select(Dispositivos).where(Dispositivos.empresa_id == empresa,
                Dispositivos.device_uuid == codigo).with_for_update())
            if tipo == TipoDispositivo.PESSOAL:
                if dados.get("setor_id") is not None:
                    raise GestaoError("Aparelho pessoal não deve receber setor_id.")
                if existente is not None and existente.tipo == TipoDispositivo.RELOGIO:
                    raise GestaoError("Este aparelho já é compartilhado. Selecione Relógio Compartilhado.",
                        409, "APARELHO_JA_COMPARTILHADO")
                if existente is not None and existente.usuario_id != alvo.usuario_id:
                    raise GestaoError("Este aparelho é Pessoal e pertence a outro funcionário. Para compartilhá-lo, selecione Relógio Compartilhado.",
                        409, "APARELHO_PESSOAL_EXCLUSIVO")
                payload, status = DeviceService.registrar_login_pessoal(empresa, alvo.usuario_id, codigo, nome,
                    session=session, autorizado_por_id=identificador(usuario_id, "autor"))
                return payload, 201 if status == 200 else status

            setores = DeviceService._setores(session, empresa, alvo)
            setor_id = identificador(dados["setor_id"], "setor_id") if dados.get("setor_id") is not None else (
                setores[0].id if len(setores) == 1 else existente.setor_id
                if existente is not None and existente.setor_id in {s.id for s in setores} else None)
            if setor_id is None or setor_id not in {s.id for s in setores}:
                raise GestaoError("Selecione um setor com alocação vigente para este funcionário.", 400, "SETOR_NAO_AUTORIZADO")
            if existente is not None and existente.tipo == TipoDispositivo.PESSOAL:
                if not converter:
                    raise GestaoError("Este aparelho está cadastrado como Pessoal. Confirme a conversão para Relógio Compartilhado.",
                        409, "CONVERSAO_RELOGIO_NECESSARIA")
                DeviceService._converter_relogio(session, empresa, existente, setor_id, nome.strip(), identificador(usuario_id, "autor"))
            # A conversão e a nova autorização são confirmadas na mesma transação.
            session.flush()
            session.execute(insert(Dispositivos).values(id=uuid.uuid4(), empresa_id=empresa, device_uuid=codigo,
                tipo=TipoDispositivo.RELOGIO, setor_id=setor_id, nome=nome.strip(), ativo=True
            ).on_conflict_do_nothing(index_elements=[Dispositivos.device_uuid]))
            aparelho = session.scalar(select(Dispositivos).where(Dispositivos.empresa_id == empresa,
                Dispositivos.device_uuid == codigo).with_for_update())
            if aparelho is None:
                raise GestaoError("Não foi possível vincular este código de aparelho.", 409, "DISPOSITIVO_CONFLITANTE")
            if aparelho.tipo != TipoDispositivo.RELOGIO:
                raise GestaoError("Este código já pertence a outro vínculo de aparelho.", 409, "DISPOSITIVO_CONFLITANTE")
            if not aparelho.ativo:
                # Reativação física não restaura autorizações antes inoperantes.
                session.execute(update(DispositivoUsuarios).where(DispositivoUsuarios.empresa_id == empresa,
                    DispositivoUsuarios.dispositivo_id == aparelho.id).values(ativo=False))
                session.execute(update(DispositivoUsuarioSetores).where(DispositivoUsuarioSetores.empresa_id == empresa,
                    DispositivoUsuarioSetores.dispositivo_id == aparelho.id).values(ativo=False))
            # Não revoga nem altera os vínculos de outros usuários do relógio.
            vinculo = session.scalar(select(DispositivoUsuarios).where(
                DispositivoUsuarios.dispositivo_id == aparelho.id, DispositivoUsuarios.empresa_id == empresa,
                DispositivoUsuarios.usuario_id == alvo.usuario_id).with_for_update().execution_options(populate_existing=True))
            if vinculo is None:
                vinculo = DispositivoUsuarios(dispositivo_id=aparelho.id, empresa_id=empresa, usuario_id=alvo.usuario_id)
                session.add(vinculo)
            vinculo.ativo = True
            vinculo.autorizado_por_id = identificador(usuario_id, "autor")
            aparelho.ativo = True
            DeviceService._autorizar_setor(session, empresa, aparelho.id, alvo.usuario_id, setor_id, identificador(usuario_id, "autor"))
            session.flush()
            escopos = DeviceService._escopos_json(session, empresa, alvo.usuario_id, [aparelho.id])
            payload = {"dispositivo": DeviceService._json(aparelho, vinculo, escopos.get(aparelho.id, []), setor_id)}
            session.commit()
            return payload, 201
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def _converter_relogio(session, empresa, aparelho, setor_id, nome, autor):
        """Apenas após confirmação explícita do RH; não transfere a propriedade do histórico."""
        vinculo_anterior = session.scalar(select(DispositivoUsuarios).where(
            DispositivoUsuarios.empresa_id == empresa, DispositivoUsuarios.dispositivo_id == aparelho.id,
            DispositivoUsuarios.usuario_id == aparelho.usuario_id).with_for_update())
        conta_anterior = session.scalar(select(Usuarios).where(Usuarios.empresa_id == empresa,
            Usuarios.id == aparelho.usuario_id, Usuarios.ativo.is_(True)))
        if aparelho.ativo and vinculo_anterior is not None and vinculo_anterior.ativo and conta_anterior is not None:
            titular = session.scalar(select(Funcionarios).where(Funcionarios.empresa_id == empresa,
                Funcionarios.usuario_id == aparelho.usuario_id, Funcionarios.ativo.is_(True)))
            if titular is not None:
                for setor in DeviceService._setores(session, empresa, titular):
                    DeviceService._autorizar_setor(session, empresa, aparelho.id, titular.usuario_id, setor.id, autor)
        elif vinculo_anterior is not None:
            # Reativar o aparelho para outro usuário não restaura uma autorização revogada.
            vinculo_anterior.ativo = False
        aparelho.tipo = TipoDispositivo.RELOGIO
        aparelho.usuario_id = None
        aparelho.setor_id = setor_id
        aparelho.nome = nome

    @staticmethod
    def revogar_manual(usuario_id, empresa_id, funcionario_id, dispositivo_id, session=None):
        def operacao(session, empresa):
            alvo = funcionario(session, empresa, funcionario_id=funcionario_id, lock=True)
            aparelho_id = identificador(dispositivo_id, "dispositivo_id")
            linha = session.execute(select(Dispositivos, DispositivoUsuarios).join(DispositivoUsuarios,
                (DispositivoUsuarios.dispositivo_id == Dispositivos.id) & (DispositivoUsuarios.empresa_id == Dispositivos.empresa_id)
            ).where(Dispositivos.id == aparelho_id, Dispositivos.empresa_id == empresa,
                DispositivoUsuarios.empresa_id == empresa, DispositivoUsuarios.usuario_id == alvo.usuario_id
            ).with_for_update()).first()
            if linha is None:
                raise GestaoError("Aparelho não encontrado para este funcionário.", 404, "DISPOSITIVO_NAO_ENCONTRADO")
            aparelho, vinculo = linha
            vinculo.ativo = False
            session.execute(update(DispositivoUsuarioSetores).where(DispositivoUsuarioSetores.empresa_id == empresa,
                DispositivoUsuarioSetores.dispositivo_id == aparelho.id,
                DispositivoUsuarioSetores.usuario_id == alvo.usuario_id).values(ativo=False))
            if aparelho.tipo == TipoDispositivo.PESSOAL:
                aparelho.ativo = False
            escopos = DeviceService._escopos_json(session, empresa, alvo.usuario_id, [aparelho.id])
            payload = {"dispositivo": DeviceService._json(aparelho, vinculo, escopos.get(aparelho.id, []))}
            session.commit()
            return payload, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def pode_usar(session, usuario, aparelho):
        vinculo = session.scalar(select(DispositivoUsuarios.usuario_id).where(
            DispositivoUsuarios.empresa_id == usuario.empresa_id, DispositivoUsuarios.usuario_id == usuario.id,
            DispositivoUsuarios.dispositivo_id == aparelho.id, DispositivoUsuarios.ativo.is_(True)))
        if vinculo is None:
            return False
        if aparelho.tipo == TipoDispositivo.PESSOAL:
            return usuario.papel == PapelUsuario.FUNCIONARIO and aparelho.usuario_id == usuario.id
        if usuario.papel != PapelUsuario.FUNCIONARIO:
            return False
        return bool(DeviceService.setores_autorizados(session, usuario.empresa_id, usuario.id, aparelho.id))

    @staticmethod
    def validar_dispositivo(empresa_id, usuario_id, device_uuid, claims, *, session=None, setor_solicitado=None):
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
            if not DeviceService.pode_usar(session, usuario, dispositivo):
                raise DeviceError()
        else:
            try:
                setores = DeviceService.setores_autorizados(session, empresa_id, usuario_id, dispositivo.id) if usuario.papel == PapelUsuario.FUNCIONARIO else []
                if usuario.papel != PapelUsuario.USUARIO_SETOR and (usuario.papel != PapelUsuario.FUNCIONARIO or not setores):
                    raise DeviceError()
            except GestaoError as error:
                raise DeviceError(error.codigo, error.mensagem, error.status) from None
            if claims.get("setor_id") is None and usuario.papel == PapelUsuario.FUNCIONARIO:
                raise DeviceError("DISPOSITIVO_MODO_ALTERADO",
                    "O aparelho agora é um relógio compartilhado. Entre novamente no aplicativo.")
            escolhido = _uuid(setor_solicitado if setor_solicitado is not None else claims.get("setor_id"))
            permitidos = {dispositivo.setor_id} if usuario.papel == PapelUsuario.USUARIO_SETOR else {s.id for s in setores}
            if usuario.papel == PapelUsuario.USUARIO_SETOR and _uuid(claims.get("setor_id")) != escolhido:
                raise DeviceError()
            if escolhido not in permitidos:
                raise DeviceError()
        return dispositivo

    @staticmethod
    def registrar_login_pessoal(empresa_id, usuario_id, device_uuid, nome, *, session=None, autorizado_por_id=None):
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
            # O trigger cria o vínculo pessoal também para clientes legados.
            vinculo = session.get(DispositivoUsuarios, (dispositivo.id, empresa_id, usuario_id))
            vinculo.ativo = True
            if autorizado_por_id is not None:
                vinculo.autorizado_por_id = autorizado_por_id
            resultado = {"dispositivo": DeviceService._json(dispositivo, vinculo)}
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
