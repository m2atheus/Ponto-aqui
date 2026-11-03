"""Contra-registro de invalidação; nenhuma alteração em registros_ponto."""
from alembic import op
import sqlalchemy as sa

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("justificativas_ajustes", sa.Column("tipo_ocorrencia", sa.String(32),
        nullable=False, server_default="AJUSTE"))
    op.create_check_constraint(op.f("ck_justificativas_ajustes_tipo_ocorrencia_valido"),
        "justificativas_ajustes", "tipo_ocorrencia IN ('AJUSTE', 'INVALIDACAO_GESTOR')")
    op.create_check_constraint(op.f("ck_justificativas_ajustes_invalidacao_com_original"),
        "justificativas_ajustes", "tipo_ocorrencia != 'INVALIDACAO_GESTOR' OR registro_ponto_id IS NOT NULL")
    op.create_index("uq_ajustes_invalidacao_aprovada", "justificativas_ajustes",
        ["empresa_id", "registro_ponto_id"], unique=True,
        postgresql_where=sa.text("tipo_ocorrencia = 'INVALIDACAO_GESTOR' AND status = 'Aprovado'"))


def downgrade():
    # Não apaga a distinção de invalidações que já integram a auditoria.
    op.execute("""DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM justificativas_ajustes WHERE tipo_ocorrencia = 'INVALIDACAO_GESTOR')
        THEN RAISE EXCEPTION 'Existem invalidações auditadas; downgrade recusado.';
        END IF;
    END $$""")
    op.drop_index("uq_ajustes_invalidacao_aprovada", table_name="justificativas_ajustes")
    op.drop_constraint(op.f("ck_justificativas_ajustes_invalidacao_com_original"), "justificativas_ajustes", type_="check")
    op.drop_constraint(op.f("ck_justificativas_ajustes_tipo_ocorrencia_valido"), "justificativas_ajustes", type_="check")
    op.drop_column("justificativas_ajustes", "tipo_ocorrencia")
