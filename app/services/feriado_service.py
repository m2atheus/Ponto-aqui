"""W06: calendário da empresa ou do setor, com unicidade por data e escopo."""

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.models import Feriados, Setores
from .rh_access import GestaoError, executar_rh, executar_empresa
from .w06_validation import data_civil, identificador, periodo


class FeriadoService:
    @staticmethod
    def _json(row):
        return {"id": str(row.id), "empresa_id": str(row.empresa_id),
            "setor_id": str(row.setor_id) if row.setor_id else None,
            "data": row.data.isoformat(), "descricao": row.descricao}

    @staticmethod
    def _validar(session, empresa, dados):
        if not isinstance(dados, dict) or dados.keys() - {"data", "descricao", "setor_id"}:
            raise GestaoError("Informe data, descrição e setor opcional, sem campos desconhecidos.")
        dia = data_civil(dados.get("data"), "data")
        descricao = dados.get("descricao")
        if not isinstance(descricao, str) or not 1 <= len(descricao.strip()) <= 255:
            raise GestaoError("A descrição deve conter entre 1 e 255 caracteres.")
        setor = identificador(dados["setor_id"], "setor_id") if dados.get("setor_id") is not None else None
        if setor is not None and session.scalar(select(Setores.id).where(
            Setores.id == setor, Setores.empresa_id == empresa)) is None:
            raise GestaoError("Setor não encontrado nesta empresa.", 404, "SETOR_NAO_ENCONTRADO")
        return {"data": dia, "descricao": descricao.strip(), "setor_id": setor}

    @staticmethod
    def _duplicidade(session, empresa, valores, excluir_id=None):
        query = select(Feriados.id).where(Feriados.empresa_id == empresa,
            Feriados.data == valores["data"], Feriados.setor_id == valores["setor_id"])
        if excluir_id is not None:
            query = query.where(Feriados.id != excluir_id)
        if session.scalar(query.limit(1)) is not None:
            raise GestaoError("Já existe um feriado nessa data para o mesmo escopo.", 409, "FERIADO_DUPLICADO")

    @staticmethod
    def _salvar(session):
        try:
            session.flush()
            session.commit()
        except IntegrityError as error:
            if getattr(error.orig, "pgcode", None) == "23505":
                raise GestaoError("Já existe um feriado nessa data para o mesmo escopo.", 409, "FERIADO_DUPLICADO") from None
            raise

    @staticmethod
    def listar(usuario_id, empresa_id, filtros=None, session=None):
        def operacao(session, empresa):
            filtros_ = {} if filtros is None else filtros
            if not isinstance(filtros_, dict) or filtros_.keys() - {"setor_id", "data_inicio", "data_fim"}:
                raise GestaoError("Filtros de feriados inválidos.")
            query = select(Feriados).where(Feriados.empresa_id == empresa)
            if "setor_id" in filtros_:
                setor = identificador(filtros_["setor_id"], "setor_id") if filtros_["setor_id"] is not None else None
                query = query.where(Feriados.setor_id == setor)
            if "data_inicio" in filtros_ or "data_fim" in filtros_:
                inicio, fim = periodo(filtros_)
                query = query.where(Feriados.data.between(inicio, fim))
            rows = session.scalars(query.order_by(Feriados.data, Feriados.id)).all()
            return {"feriados": [FeriadoService._json(row) for row in rows]}, 200
        return executar_empresa(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def criar(usuario_id, empresa_id, dados, session=None):
        def operacao(session, empresa):
            valores = FeriadoService._validar(session, empresa, dados)
            FeriadoService._duplicidade(session, empresa, valores)
            row = Feriados(empresa_id=empresa, **valores)
            session.add(row)
            FeriadoService._salvar(session)
            return {"feriado": FeriadoService._json(row)}, 201
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def atualizar(usuario_id, empresa_id, alvo_id, dados, session=None):
        def operacao(session, empresa):
            target = identificador(alvo_id, "feriado_id")
            row = session.scalar(select(Feriados).where(Feriados.id == target,
                Feriados.empresa_id == empresa).with_for_update().execution_options(populate_existing=True))
            if row is None:
                raise GestaoError("Feriado não encontrado nesta empresa.", 404, "FERIADO_NAO_ENCONTRADO")
            if not isinstance(dados, dict) or not dados:
                raise GestaoError("Informe os campos do feriado a atualizar.")
            valores = FeriadoService._validar(session, empresa, {
                "data": row.data, "descricao": row.descricao, "setor_id": row.setor_id, **dados})
            FeriadoService._duplicidade(session, empresa, valores, row.id)
            for campo, valor in valores.items():
                setattr(row, campo, valor)
            FeriadoService._salvar(session)
            return {"feriado": FeriadoService._json(row)}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def remover(usuario_id, empresa_id, alvo_id, session=None):
        def operacao(session, empresa):
            target = identificador(alvo_id, "feriado_id")
            row = session.scalar(select(Feriados).where(Feriados.id == target,
                Feriados.empresa_id == empresa).with_for_update())
            if row is None:
                raise GestaoError("Feriado não encontrado nesta empresa.", 404, "FERIADO_NAO_ENCONTRADO")
            session.delete(row)
            session.commit()
            return {"id": str(target), "removido": True}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)
