"""W06: afastamentos com datas inclusivas, isolamento e proteção concorrente."""

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.models import Afastamentos, TipoAfastamento
from .rh_access import GestaoError, executar_rh, executar_empresa
from .w06_validation import anexo_url, funcionario, identificador, periodo


class AfastamentoService:
    @staticmethod
    def _json(row):
        return {"id": str(row.id), "empresa_id": str(row.empresa_id),
            "funcionario_id": str(row.funcionario_id),
            "usuario_id": str(row.usuario_id) if row.usuario_id else None,
            "tipo": TipoAfastamento(row.tipo).value, "data_inicio": row.data_inicio.isoformat(),
            "data_fim": row.data_fim.isoformat(), "anexo_url": row.anexo_url,
            "descricao": row.descricao}

    @staticmethod
    def _validar(dados):
        campos = {"usuario_id", "funcionario_id", "tipo", "data_inicio", "data_fim", "anexo_url", "descricao"}
        if not isinstance(dados, dict) or dados.keys() - campos:
            raise GestaoError("Informe os dados do afastamento, sem campos desconhecidos.")
        inicio, fim = periodo(dados)
        try:
            tipo = TipoAfastamento(dados.get("tipo"))
        except (ValueError, TypeError):
            raise GestaoError("Tipo inválido. Use FERIAS, ATESTADO, LICENCA ou OUTROS.") from None
        descricao = dados.get("descricao")
        if descricao is not None and (not isinstance(descricao, str) or len(descricao) > 5000):
            raise GestaoError("A descrição deve ter até 5000 caracteres.")
        return {"data_inicio": inicio, "data_fim": fim, "tipo": tipo,
            "anexo_url": anexo_url(dados.get("anexo_url")), "descricao": descricao}

    @staticmethod
    def _sobreposicao(session, empresa, funcionario_id, inicio, fim, excluir_id=None):
        query = select(Afastamentos.id).where(Afastamentos.empresa_id == empresa,
            Afastamentos.funcionario_id == funcionario_id,
            Afastamentos.data_inicio <= fim, Afastamentos.data_fim >= inicio)
        if excluir_id is not None:
            query = query.where(Afastamentos.id != excluir_id)
        if session.scalar(query.limit(1)) is not None:
            raise GestaoError("O funcionário já possui afastamento nesse período.", 400, "AFASTAMENTO_SOBREPOSTO")

    @staticmethod
    def _salvar(session):
        try:
            session.flush()
            session.commit()
        except IntegrityError as error:
            if getattr(error.orig, "pgcode", None) == "23P01":
                raise GestaoError("O funcionário já possui afastamento nesse período.", 400, "AFASTAMENTO_SOBREPOSTO") from None
            raise

    @staticmethod
    def listar(usuario_id, empresa_id, filtros=None, session=None):
        def operacao(session, empresa):
            filtros_ = {} if filtros is None else filtros
            if not isinstance(filtros_, dict) or filtros_.keys() - {"usuario_id", "funcionario_id", "data_inicio", "data_fim"}:
                raise GestaoError("Filtros de afastamento inválidos.")
            query = select(Afastamentos).where(Afastamentos.empresa_id == empresa)
            if filtros_.get("funcionario_id") is not None or filtros_.get("usuario_id") is not None:
                alvo = funcionario(session, empresa, funcionario_id=filtros_.get("funcionario_id"),
                    usuario_id=filtros_.get("usuario_id"))
                query = query.where(Afastamentos.funcionario_id == alvo.id)
            if "data_inicio" in filtros_ or "data_fim" in filtros_:
                inicio, fim = periodo(filtros_)
                query = query.where(Afastamentos.data_inicio <= fim, Afastamentos.data_fim >= inicio)
            rows = session.scalars(query.order_by(Afastamentos.data_inicio, Afastamentos.id)).all()
            return {"afastamentos": [AfastamentoService._json(row) for row in rows]}, 200
        return executar_empresa(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def criar(usuario_id, empresa_id, dados, session=None, *, arquivo=None, base_url=None):
        def operacao(session, empresa):
            valores = AfastamentoService._validar(dados)
            alvo = funcionario(session, empresa, funcionario_id=dados.get("funcionario_id"),
                usuario_id=dados.get("usuario_id"), lock=True, ativo=True)
            AfastamentoService._sobreposicao(session, empresa, alvo.id, valores["data_inicio"], valores["data_fim"])
            row = Afastamentos(empresa_id=empresa, funcionario_id=alvo.id, usuario_id=alvo.usuario_id, **valores)
            session.add(row)
            if arquivo is not None:
                from .anexo_afastamento_service import AnexoAfastamentoService
                session.flush()
                AnexoAfastamentoService.anexar(session, empresa, row, arquivo, base_url)
            AfastamentoService._salvar(session)
            return {"afastamento": AfastamentoService._json(row)}, 201
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def atualizar(usuario_id, empresa_id, alvo_id, dados, session=None, *, arquivo=None, base_url=None):
        def operacao(session, empresa):
            target = identificador(alvo_id, "afastamento_id")
            fid = session.scalar(select(Afastamentos.funcionario_id).where(
                Afastamentos.id == target, Afastamentos.empresa_id == empresa))
            if fid is None:
                raise GestaoError("Afastamento não encontrado nesta empresa.", 404, "AFASTAMENTO_NAO_ENCONTRADO")
            funcionario(session, empresa, funcionario_id=fid, lock=True)
            row = session.scalar(select(Afastamentos).where(Afastamentos.id == target,
                Afastamentos.empresa_id == empresa).with_for_update().execution_options(populate_existing=True))
            if row is None:
                raise GestaoError("Afastamento não encontrado nesta empresa.", 404, "AFASTAMENTO_NAO_ENCONTRADO")
            if not isinstance(dados, dict) or not dados or dados.keys() - {"tipo", "data_inicio", "data_fim", "anexo_url", "descricao"}:
                raise GestaoError("Edite somente período, tipo, anexo e descrição do afastamento.")
            valores = AfastamentoService._validar({
                "tipo": TipoAfastamento(row.tipo).value, "data_inicio": row.data_inicio, "data_fim": row.data_fim,
                "anexo_url": row.anexo_url, "descricao": row.descricao, **dados})
            AfastamentoService._sobreposicao(session, empresa, fid, valores["data_inicio"], valores["data_fim"], row.id)
            for campo, valor in valores.items():
                setattr(row, campo, valor)
            from .anexo_afastamento_service import AnexoAfastamentoService
            if arquivo is not None:
                AnexoAfastamentoService.anexar(session, empresa, row, arquivo, base_url)
            elif "anexo_url" in dados and dados["anexo_url"] is None:
                AnexoAfastamentoService.remover_anexo(session, empresa, row.id)
            AfastamentoService._salvar(session)
            return {"afastamento": AfastamentoService._json(row)}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def remover(usuario_id, empresa_id, alvo_id, session=None):
        def operacao(session, empresa):
            target = identificador(alvo_id, "afastamento_id")
            row = session.scalar(select(Afastamentos).where(Afastamentos.id == target,
                Afastamentos.empresa_id == empresa).with_for_update())
            if row is None:
                raise GestaoError("Afastamento não encontrado nesta empresa.", 404, "AFASTAMENTO_NAO_ENCONTRADO")
            session.delete(row)
            session.commit()
            return {"id": str(target), "removido": True}, 200
        return executar_rh(usuario_id, empresa_id, operacao, session)
