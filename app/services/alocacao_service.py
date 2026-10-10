"""W03: vínculos por período, com histórico e bloqueio de sobreposição."""

import re
import uuid
from datetime import date, timedelta

from sqlalchemy import or_, select

from app.models import Alocacoes, Escalas, Funcionarios, Setores
from .check_schedule_conflict_service import CheckScheduleConflictService
from .rh_access import GestaoError, executar_rh


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
        """Encerra a origem e cria o destino na MESMA transação (datas inclusivas)."""
        def operacao(session, empresa):
            if (not isinstance(dados, dict) or dados.keys() - {"setor_id", "escala_id", "data_inicio", "data_fim"}
                    or not {"setor_id", "data_inicio"} <= dados.keys()):
                raise GestaoError("Informe setor e início da nova alocação, sem alterar o funcionário.")
            alvo = _uuid(alvo_id, "alocacao_id")
            inicio = _data(dados["data_inicio"], "data_inicio")
            funcionario_id = session.scalar(select(Alocacoes.funcionario_id).where(
                Alocacoes.id == alvo, Alocacoes.empresa_id == empresa))
            if funcionario_id is None:
                raise GestaoError("Alocação não encontrada nesta empresa.", 404, "ALOCACAO_NAO_ENCONTRADA")
            session.scalar(select(Funcionarios.id).where(Funcionarios.id == funcionario_id,
                Funcionarios.empresa_id == empresa).with_for_update())
            antiga = session.scalar(select(Alocacoes).where(Alocacoes.id == alvo,
                Alocacoes.empresa_id == empresa).with_for_update().execution_options(populate_existing=True))
            if antiga is None:
                raise GestaoError("Alocação não encontrada nesta empresa.", 404, "ALOCACAO_NAO_ENCONTRADA")
            if antiga.data_fim is not None:
                raise GestaoError("Esta alocação já está encerrada.", 409, "ALOCACAO_ENCERRADA")
            if inicio <= antiga.data_inicio:
                raise GestaoError("A troca deve começar depois do início da alocação anterior.")
            # Nenhum ID, setor, escala, funcionário ou data_inicio é sobrescrito.
            antiga.data_fim = inicio - timedelta(days=1)
            session.flush()
            nova = AlocacaoService._nova_alocacao(session, empresa, {
                "funcionario_id": str(funcionario_id), **dados})
            result = {"alocacao_anterior": AlocacaoService._json(antiga),
                "alocacao": AlocacaoService._json(nova)}
            session.commit()
            return result, 201
        return executar_rh(usuario_id, empresa_id, operacao, session)

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
            query = select(Alocacoes).where(Alocacoes.empresa_id == empresa)
            if funcionario_id is not None:
                query = query.where(Alocacoes.funcionario_id == _uuid(funcionario_id, "funcionario_id"))
            rows = session.scalars(query.order_by(Alocacoes.data_inicio.desc(), Alocacoes.id)).all()
            return {"alocacoes": [AlocacaoService._json(row) for row in rows]}, 200
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
            if funcionario.usuario_id is None:
                raise GestaoError("O funcionário precisa de uma conta vinculada para validar sua escala.")
            payload, status = CheckScheduleConflictService.validar_alocacao(
                empresa, funcionario.usuario_id, escala_id, inicio.isoformat(),
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
            session.commit()
            return {"alocacao": result}, 201
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
