"""Aprovação auditada de marcações; preserva os registros originais."""
from alembic import op
import sqlalchemy as sa

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def upgrade():
    op.drop_constraint(op.f("ck_justificativas_ajustes_tipo_ocorrencia_valido"), "justificativas_ajustes", type_="check")
    op.create_check_constraint(op.f("ck_justificativas_ajustes_tipo_ocorrencia_valido"), "justificativas_ajustes",
        "tipo_ocorrencia IN ('AJUSTE', 'INVALIDACAO_GESTOR', 'APROVACAO_GESTOR')")
    op.drop_constraint(op.f("ck_justificativas_ajustes_invalidacao_com_original"), "justificativas_ajustes", type_="check")
    op.create_check_constraint(op.f("ck_justificativas_ajustes_invalidacao_com_original"), "justificativas_ajustes",
        "tipo_ocorrencia = 'AJUSTE' OR registro_ponto_id IS NOT NULL")
    op.create_index("uq_ajustes_aprovacao_gestor", "justificativas_ajustes", ["empresa_id", "registro_ponto_id"],
        unique=True, postgresql_where=sa.text("tipo_ocorrencia = 'APROVACAO_GESTOR' AND status = 'Aprovado'"))


def downgrade():
    op.execute("""DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM justificativas_ajustes WHERE tipo_ocorrencia = 'APROVACAO_GESTOR')
        THEN RAISE EXCEPTION 'Existem aprovacoes auditadas; downgrade recusado.';
        END IF;
    END $$""")
    op.drop_index("uq_ajustes_aprovacao_gestor", table_name="justificativas_ajustes")
    op.drop_constraint(op.f("ck_justificativas_ajustes_tipo_ocorrencia_valido"), "justificativas_ajustes", type_="check")
    op.create_check_constraint(op.f("ck_justificativas_ajustes_tipo_ocorrencia_valido"), "justificativas_ajustes",
        "tipo_ocorrencia IN ('AJUSTE', 'INVALIDACAO_GESTOR')")
    op.drop_constraint(op.f("ck_justificativas_ajustes_invalidacao_com_original"), "justificativas_ajustes", type_="check")
    op.create_check_constraint(op.f("ck_justificativas_ajustes_invalidacao_com_original"), "justificativas_ajustes",
        "tipo_ocorrencia != 'INVALIDACAO_GESTOR' OR registro_ponto_id IS NOT NULL")
