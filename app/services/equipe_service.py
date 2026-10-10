"""Consultas administrativas com histórico completo, inclusive vínculos encerrados."""
from sqlalchemy import select

from app.models import Alocacoes, Funcionarios, Escalas, Setores
from .funcionario_service import FuncionarioService
from .rh_access import executar_empresa


class EquipeService:
    @staticmethod
    def listar(usuario_id, empresa_id, session=None):
        def operacao(session, empresa):
            funcionarios = session.scalars(select(Funcionarios).where(
                Funcionarios.empresa_id == empresa).order_by(Funcionarios.nome, Funcionarios.id)).all()
            setores = session.scalars(select(Setores).where(Setores.empresa_id == empresa)
                .order_by(Setores.nome, Setores.id)).all()
            rows = session.execute(select(Alocacoes, Escalas.nome).outerjoin(Escalas,
                (Alocacoes.escala_id == Escalas.id) & (Escalas.empresa_id == empresa))
                .where(Alocacoes.empresa_id == empresa).order_by(Alocacoes.data_inicio, Alocacoes.id)).all()
            return {"funcionarios": [FuncionarioService._json(f) for f in funcionarios],
                "setores": [{"id": str(s.id), "empresa_id": str(empresa), "nome": s.nome, "ativo": s.ativo} for s in setores],
                "historico": [{"id": str(a.id), "empresa_id": str(empresa),
                    "funcionario_id": str(a.funcionario_id), "setor_id": str(a.setor_id),
                    "escala_id": str(a.escala_id) if a.escala_id else None,
                    "escala_nome": nome, "data_inicio": a.data_inicio.isoformat(),
                    "data_fim": a.data_fim.isoformat() if a.data_fim else None} for a, nome in rows]}, 200
        return executar_empresa(usuario_id, empresa_id, operacao, session)
