"""Histórico sequencial de decisões e reaprovação exclusiva do RH."""
from alembic import op
import sqlalchemy as sa

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("justificativas_ajustes", sa.Column("sequencia_decisao", sa.Integer()))
    op.execute("""WITH historico AS (
        SELECT id, row_number() OVER (PARTITION BY empresa_id, registro_ponto_id
            ORDER BY decidido_em NULLS FIRST, criado_em, id) AS sequencia
        FROM justificativas_ajustes WHERE tipo_ocorrencia <> 'AJUSTE'
    ) UPDATE justificativas_ajustes a SET sequencia_decisao = h.sequencia
      FROM historico h WHERE a.id = h.id""")
    op.drop_index("uq_ajustes_invalidacao_aprovada", table_name="justificativas_ajustes")
    op.drop_index("uq_ajustes_aprovacao_gestor", table_name="justificativas_ajustes")
    op.drop_constraint(op.f("ck_justificativas_ajustes_tipo_ocorrencia_valido"), "justificativas_ajustes", type_="check")
    op.create_check_constraint(op.f("ck_justificativas_ajustes_tipo_ocorrencia_valido"), "justificativas_ajustes",
        "tipo_ocorrencia IN ('AJUSTE', 'INVALIDACAO_GESTOR', 'APROVACAO_GESTOR', 'REAPROVACAO_RH')")
    op.create_check_constraint(op.f("ck_justificativas_ajustes_sequencia_decisao_valida"), "justificativas_ajustes",
        "(tipo_ocorrencia = 'AJUSTE' AND sequencia_decisao IS NULL) OR "
        "(tipo_ocorrencia <> 'AJUSTE' AND sequencia_decisao IS NOT NULL AND sequencia_decisao > 0)")
    op.create_index("uq_ajustes_sequencia_decisao", "justificativas_ajustes",
        ["empresa_id", "registro_ponto_id", "sequencia_decisao"], unique=True,
        postgresql_where=sa.text("sequencia_decisao IS NOT NULL"))


def downgrade():
    op.execute("""DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM justificativas_ajustes WHERE tipo_ocorrencia = 'REAPROVACAO_RH')
        OR EXISTS (SELECT 1 FROM justificativas_ajustes WHERE status='Aprovado' AND tipo_ocorrencia <> 'AJUSTE'
            GROUP BY empresa_id, registro_ponto_id, tipo_ocorrencia HAVING count(*) > 1)
        THEN RAISE EXCEPTION 'Existe historico de reanalise; downgrade recusado.';
        END IF;
    END $$""")
    op.drop_index("uq_ajustes_sequencia_decisao", table_name="justificativas_ajustes")
    op.drop_constraint(op.f("ck_justificativas_ajustes_sequencia_decisao_valida"), "justificativas_ajustes", type_="check")
    op.drop_constraint(op.f("ck_justificativas_ajustes_tipo_ocorrencia_valido"), "justificativas_ajustes", type_="check")
    op.create_check_constraint(op.f("ck_justificativas_ajustes_tipo_ocorrencia_valido"), "justificativas_ajustes",
        "tipo_ocorrencia IN ('AJUSTE', 'INVALIDACAO_GESTOR', 'APROVACAO_GESTOR')")
    op.create_index("uq_ajustes_invalidacao_aprovada", "justificativas_ajustes", ["empresa_id", "registro_ponto_id"],
        unique=True, postgresql_where=sa.text("tipo_ocorrencia = 'INVALIDACAO_GESTOR' AND status = 'Aprovado'"))
    op.create_index("uq_ajustes_aprovacao_gestor", "justificativas_ajustes", ["empresa_id", "registro_ponto_id"],
        unique=True, postgresql_where=sa.text("tipo_ocorrencia = 'APROVACAO_GESTOR' AND status = 'Aprovado'"))
    op.drop_column("justificativas_ajustes", "sequencia_decisao")
