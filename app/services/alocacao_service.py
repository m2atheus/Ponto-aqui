"""W03: vínculos por período, com histórico e bloqueio de sobreposição."""

import re
import uuid
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import or_, select

from app.models import Alocacoes, Empresas, Escalas, Funcionarios, ModeloEscala, Setores
from .check_schedule_conflict_service import CheckScheduleConflictService
from .rh_access import GestaoError, executar_empresa, executar_rh
from .funcionario_service import FuncionarioService
from .setor_service import SetorService


def _uuid(value, campo):
    if not isinstance(value, (str, uuid.UUID)):
        raise GestaoError(f"{campo} deve ser um UUID válido.")
    try:
        return uuid.UUID(str(value))
    except ValueError:
        raise GestaoError(f"{campo} deve ser um UUID válido.") from None


def _data(value, campo):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise GestaoError(f"{campo} deve usar o formato AAAA-MM-DD.")
    try:
        return date.fromisoformat(value)
    except ValueError:
        raise GestaoError(f"{campo} contém uma data inválida.") from None


class AlocacaoService:
    @staticmethod
    def trocar(usuario_id, empresa_id, alvo_id, dados, session=None):
        """Compatibilidade com o serviço anterior, usando a mesma transação de troca."""
        def operacao(session, empresa):
            if (not isinstance(dados, dict) or dados.keys() - {"setor_id", "escala_id", "data_inicio", "data_fim"}
                    or not {"setor_id", "data_inicio"} <= dados.keys()):
                raise GestaoError("Informe setor e início da nova alocação, sem alterar o funcionário.")
            alvo = _uuid(alvo_id, "alocacao_id")
            funcionario_id = session.scalar(select(Alocacoes.funcionario_id).where(
                Alocacoes.id == alvo, Alocacoes.empresa_id == empresa))
            if funcionario_id is None:
                raise GestaoError("Alocação não encontrada nesta empresa.", 404, "ALOCACAO_NAO_ENCONTRADA")
            return AlocacaoService._executar_mudanca(session, empresa, funcionario_id,
                dados.get("escala_id"), dados["setor_id"], dados["data_inicio"],
                alocacao_id=alvo, data_fim=dados.get("data_fim"))
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def mudar_alocacao(usuario_id, empresa_id, funcionario_id, nova_escala_id,
                       novo_setor_id, data_transicao, *, alocacao_id=None, session=None):
        def operacao(session, empresa):
            return AlocacaoService._executar_mudanca(session, empresa, funcionario_id,
                nova_escala_id, novo_setor_id, data_transicao, alocacao_id=alocacao_id)
        return executar_empresa(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def solicitar_mudanca(usuario_id, empresa_id, funcionario_id, dados, session=None):
        def operacao(session, empresa):
            campos = {"novo_setor_id", "nova_escala_id", "data_transicao", "alocacao_id", "data_encerramento"}
            if not isinstance(dados, dict) or dados.keys() - campos or not {"novo_setor_id", "nova_escala_id", "data_transicao"} <= dados.keys():
                raise GestaoError("Informe novo_setor_id, nova_escala_id e data_transicao, sem campos desconhecidos.")
            if "data_encerramento" in dados and dados["data_encerramento"] is None:
                raise GestaoError("data_encerramento deve conter uma data válida.")
            return AlocacaoService._executar_mudanca(session, empresa, funcionario_id,
                dados["nova_escala_id"], dados["novo_setor_id"], dados["data_transicao"],
                alocacao_id=dados.get("alocacao_id"), data_encerramento=dados.get("data_encerramento"))
        return executar_empresa(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def _hoje(session, empresa):
        fuso = session.scalar(select(Empresas.fuso_horario).where(Empresas.id == empresa))
        try:
            return datetime.now(timezone.utc).astimezone(ZoneInfo(fuso)).date()
        except (ZoneInfoNotFoundError, ValueError, TypeError):
            raise GestaoError("Fuso da empresa indisponível.", 503, "FUSO_INVALIDO") from None

    @staticmethod
    def _executar_mudanca(session, empresa, funcionario_id, nova_escala_id, novo_setor_id,
                         data_transicao, *, alocacao_id=None, data_fim=None, data_encerramento=None):
        # A autenticação já iniciou a transação externa. O savepoint evita um
        # segundo begin() sobre autobegin e inclui encerramento + inserção juntos.
        # executar_empresa faz rollback em qualquer erro; há um único commit final.
        with session.begin_nested():
            fid = _uuid(funcionario_id, "funcionario_id")
            sid = _uuid(novo_setor_id, "novo_setor_id")
            eid = _uuid(nova_escala_id, "nova_escala_id") if nova_escala_id is not None else None
            inicio = _data(data_transicao, "data_transicao")
            if data_encerramento is not None:
                fim_anterior = _data(data_encerramento, "data_encerramento")
            elif inicio > date.min:
                fim_anterior = inicio - timedelta(days=1)
            else:
                raise GestaoError("A data da mudança não permite preservar o vínculo anterior.")
            if fim_anterior >= inicio:
                raise GestaoError("O início no novo setor deve ser posterior ao encerramento no setor atual.")
            limite_origem = fim_anterior if data_encerramento is not None else inicio
            hoje = AlocacaoService._hoje(session, empresa)
            pessoa = session.scalar(select(Funcionarios).where(Funcionarios.id == fid,
                Funcionarios.empresa_id == empresa, Funcionarios.ativo.is_(True)).with_for_update())
            if pessoa is None:
                raise GestaoError("Funcionário não encontrado ou inativo nesta empresa.", 404, "FUNCIONARIO_NAO_ENCONTRADO")
            consulta = select(Alocacoes).where(Alocacoes.empresa_id == empresa, Alocacoes.funcionario_id == fid,
                Alocacoes.data_inicio <= limite_origem,
                or_(Alocacoes.data_fim.is_(None), Alocacoes.data_fim >= limite_origem),
                or_(Alocacoes.data_fim.is_(None), Alocacoes.data_fim >= hoje))
            if alocacao_id is not None:
                consulta = consulta.where(Alocacoes.id == _uuid(alocacao_id, "alocacao_id"))
            origens = session.scalars(consulta.order_by(Alocacoes.id).limit(2)
                .with_for_update().execution_options(populate_existing=True)).all()
            if not origens:
                raise GestaoError("Não há alocação vigente para essa mudança. Consulte o histórico novamente.", 409, "ALOCACAO_NAO_VIGENTE")
            if len(origens) > 1:
                raise GestaoError("Há mais de uma alocação vigente. Selecione qual vínculo deve ser alterado.", 409, "ALOCACAO_AMBIGUA")
            antiga = origens[0]
            if inicio <= antiga.data_inicio:
                raise GestaoError("A mudança deve começar depois do início da alocação anterior.")
            if antiga.setor_id == sid and antiga.escala_id == eid:
                raise GestaoError("Selecione um setor ou uma escala diferente da alocação atual.")
            antiga.data_fim = fim_anterior
            session.flush()
            nova = AlocacaoService._nova_alocacao(session, empresa, {
                "funcionario_id": str(fid), "setor_id": str(sid), "escala_id": str(eid) if eid else None,
                "data_inicio": inicio.isoformat(), "data_fim": data_fim})
            payload = {"alocacao_anterior": AlocacaoService._json(antiga), "alocacao": AlocacaoService._json(nova)}
        session.commit()
        return payload, 201

    @staticmethod
    def opcoes_mudanca(usuario_id, empresa_id, tipo, q=None, session=None):
        def operacao(session, empresa):
            if tipo not in {"setor", "escala"} or (q is not None and (not isinstance(q, str) or len(q.strip()) > 150)):
                raise GestaoError("Informe tipo setor/escala e uma busca de até 150 caracteres.")
            modelo = Setores if tipo == "setor" else Escalas
            consulta = select(modelo.id, modelo.nome).where(modelo.empresa_id == empresa, modelo.ativo.is_(True))
            if tipo == "escala":
                consulta = consulta.where(Escalas.modelo != ModeloEscala.LEGADO)
            termo = (q or "").strip().replace("/", "//").replace("%", "/%").replace("_", "/_")
            if termo:
                consulta = consulta.where(modelo.nome.ilike("%" + termo + "%", escape="/"))
            rows = session.execute(consulta.order_by(modelo.nome, modelo.id).limit(20)).all()
            return {"opcoes": [{"id": str(r.id), "nome": r.nome, "empresa_id": str(empresa)} for r in rows]}, 200
        return executar_empresa(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def _json(row):
        return {
            "id": str(row.id), "empresa_id": str(row.empresa_id),
            "funcionario_id": str(row.funcionario_id), "setor_id": str(row.setor_id),
            "escala_id": str(row.escala_id) if row.escala_id else None,
            "data_inicio": row.data_inicio.isoformat(),
            "data_fim": row.data_fim.isoformat() if row.data_fim else None,
        }

    @staticmethod
    def listar(usuario_id, empresa_id, funcionario_id=None, session=None):
        def operacao(session, empresa):
            query = select(Alocacoes, Funcionarios, Setores).join(
                Funcionarios, (Funcionarios.id == Alocacoes.funcionario_id) & (Funcionarios.empresa_id == empresa),
            ).join(Setores, (Setores.id == Alocacoes.setor_id) & (Setores.empresa_id == empresa)
            ).where(Alocacoes.empresa_id == empresa)
            if funcionario_id is not None:
                query = query.where(Alocacoes.funcionario_id == _uuid(funcionario_id, "funcionario_id"))
            rows = session.execute(query.order_by(Alocacoes.data_inicio.desc(), Alocacoes.id)).all()
            # Somente referências das alocações listadas; não carrega o cadastro inteiro.
            funcionarios = {str(f.id): FuncionarioService._json(f) for _, f, _ in rows}
            setores = {str(s.id): SetorService._json(s) for _, _, s in rows}
            return {"alocacoes": [AlocacaoService._json(row) for row, _, _ in rows],
                    "funcionarios": list(funcionarios.values()), "setores": list(setores.values())}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def _sobreposicao(session, empresa, funcionario, setor, inicio, fim):
        query = select(Alocacoes.id).where(
            Alocacoes.empresa_id == empresa, Alocacoes.funcionario_id == funcionario,
            Alocacoes.setor_id == setor,
            or_(Alocacoes.data_fim.is_(None), Alocacoes.data_fim >= inicio),
        )
        if fim is not None:
            query = query.where(Alocacoes.data_inicio <= fim)
        if session.scalar(query.limit(1)) is not None:
            raise GestaoError(
                "Este funcionário já possui alocação nesse setor no período informado.",
                409, "ALOCACAO_SOBREPOSTA",
            )

    @staticmethod
    def _nova_alocacao(session, empresa, dados):
        campos = {"funcionario_id", "setor_id", "data_inicio", "data_fim", "escala_id"}
        if (not isinstance(dados, dict) or dados.keys() - campos
                or not {"funcionario_id", "setor_id", "data_inicio"} <= dados.keys()):
            raise GestaoError("Informe funcionário, setor e data de início, sem campos desconhecidos.")
        funcionario_id = _uuid(dados["funcionario_id"], "funcionario_id")
        setor_id = _uuid(dados["setor_id"], "setor_id")
        inicio = _data(dados["data_inicio"], "data_inicio")
        fim = _data(dados["data_fim"], "data_fim") if dados.get("data_fim") is not None else None
        if fim is not None and fim < inicio:
            raise GestaoError("A data final não pode ser anterior à inicial.")
        # Serializa criações e encerramentos do mesmo funcionário. A
        # exclusion constraint também protege contra outros escritores.
        funcionario = session.scalar(select(Funcionarios).where(
            Funcionarios.id == funcionario_id, Funcionarios.empresa_id == empresa,
            Funcionarios.ativo.is_(True),
        ).with_for_update())
        setor = session.scalar(select(Setores).where(
            Setores.id == setor_id, Setores.empresa_id == empresa, Setores.ativo.is_(True),
        ))
        if funcionario is None or setor is None:
            raise GestaoError("Funcionário ou setor não está ativo nesta empresa.", 404, "VINCULO_NAO_ENCONTRADO")
        AlocacaoService._sobreposicao(session, empresa, funcionario_id, setor_id, inicio, fim)
        escala_id = _uuid(dados["escala_id"], "escala_id") if dados.get("escala_id") is not None else None
        if escala_id is not None:
            escala = session.scalar(select(Escalas.id).where(
                Escalas.id == escala_id, Escalas.empresa_id == empresa, Escalas.ativo.is_(True),
            ))
            if escala is None:
                raise GestaoError("Escala não encontrada nesta empresa.", 404, "ESCALA_NAO_ENCONTRADA")
            payload, status = CheckScheduleConflictService.validar_alocacao_funcionario(
                empresa, funcionario.id, escala_id, inicio.isoformat(),
                fim.isoformat() if fim else None, session=session,
            )
            if status != 200:
                error = payload["erro"]
                raise GestaoError(error["mensagem"], status, error["codigo"], error.get("detalhes"))
        row = Alocacoes(empresa_id=empresa, funcionario_id=funcionario.id,
            usuario_id=funcionario.usuario_id, setor_id=setor.id, escala_id=escala_id,
            data_inicio=inicio, data_fim=fim)
        session.add(row)
        session.flush()
        return row

    @staticmethod
    def criar(usuario_id, empresa_id, dados, session=None):
        def operacao(session, empresa):
            row = AlocacaoService._nova_alocacao(session, empresa, dados)
            result = AlocacaoService._json(row)
            validacao = {}
            if row.escala_id is not None and row.data_fim is None:
                validacao["validacao_escala"] = {
                    "horizonte_anos": CheckScheduleConflictService.HORIZONTE_INDETERMINADO_ANOS,
                    "ate": CheckScheduleConflictService.fim_horizonte_indeterminado(row.data_inicio).isoformat(),
                    "periodo_indeterminado": True,
                }
            session.commit()
            return {"alocacao": result, **validacao}, 201
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def encerrar(usuario_id, empresa_id, alvo_id, dados, session=None):
        def operacao(session, empresa):
            if not isinstance(dados, dict) or dados.keys() != {"data_fim"}:
                raise GestaoError("Para encerrar, informe apenas data_fim; os vínculos históricos não podem ser editados.")
            fim = _data(dados["data_fim"], "data_fim")
            alvo = _uuid(alvo_id, "alocacao_id")
            funcionario_id = session.scalar(select(Alocacoes.funcionario_id).where(
                Alocacoes.id == alvo, Alocacoes.empresa_id == empresa,
            ))
            if funcionario_id is None:
                raise GestaoError("Alocação não encontrada nesta empresa.", 404, "ALOCACAO_NAO_ENCONTRADA")
            # A mesma ordem de locks do cadastro evita corrida no encerramento.
            session.scalar(select(Funcionarios.id).where(
                Funcionarios.id == funcionario_id, Funcionarios.empresa_id == empresa,
            ).with_for_update())
            row = session.scalar(select(Alocacoes).where(
                Alocacoes.id == alvo, Alocacoes.empresa_id == empresa,
            ).with_for_update().execution_options(populate_existing=True))
            if row is None:
                raise GestaoError("Alocação não encontrada nesta empresa.", 404, "ALOCACAO_NAO_ENCONTRADA")
            if fim < row.data_inicio:
                raise GestaoError("A data final não pode ser anterior à inicial.")
            if row.data_fim is not None and row.data_fim != fim:
                raise GestaoError("Esta alocação já tem um fim definido. Crie um novo vínculo para outro período.", 409, "ALOCACAO_ENCERRADA")
            row.data_fim = fim
            session.flush()
            result = AlocacaoService._json(row)
            session.commit()
            return {"alocacao": result}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)
