"""Indicadores reais, sem números de demonstração."""
from sqlalchemy import func, select
from app.models import Funcionarios, Setores, Escalas, JustificativasAjustes, StatusAjuste
from .rh_access import executar_empresa


class DashboardService:
    @staticmethod
    def consultar(usuario_id, empresa_id, session=None):
        def operacao(session, empresa):
            def contar(model, *filtros):
                return session.scalar(select(func.count()).select_from(model)
                    .where(model.empresa_id == empresa, *filtros))
            return {"empresa_id": str(empresa), "indicadores": {
                "funcionarios": contar(Funcionarios, Funcionarios.ativo.is_(True)),
                "setores": contar(Setores, Setores.ativo.is_(True)),
                "escalas_ativas": contar(Escalas, Escalas.ativo.is_(True)),
                "justificativas_pendentes": contar(JustificativasAjustes, JustificativasAjustes.status == StatusAjuste.PENDENTE),
            }}, 200
        return executar_empresa(usuario_id, empresa_id, operacao, session)
