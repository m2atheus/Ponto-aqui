"""W06: atestados privados vinculados ao afastamento, sem alterar marcações."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("anexos_afastamento",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("empresa_id", UUID(as_uuid=True), nullable=False),
        sa.Column("afastamento_id", UUID(as_uuid=True), nullable=False),
        sa.Column("nome", sa.String(255), nullable=False),
        sa.Column("content_type", sa.String(80), nullable=False),
        sa.Column("conteudo", sa.LargeBinary(), nullable=False),
        sa.Column("criado_em", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["empresa_id"], ["empresas.id"], name="fk_anexos_afastamento_empresa_id_empresas",
            ondelete="RESTRICT", onupdate="RESTRICT"),
        sa.ForeignKeyConstraint(["afastamento_id", "empresa_id"], ["afastamentos.id", "afastamentos.empresa_id"],
            name="fk_anexos_afastamento_vinculo", ondelete="CASCADE", onupdate="RESTRICT"),
        sa.UniqueConstraint("empresa_id", "afastamento_id", name="uq_anexos_afastamento_vinculo"),
        sa.CheckConstraint("octet_length(conteudo) BETWEEN 1 AND 10485760", name=op.f("ck_anexos_afastamento_tamanho_valido")))
    op.create_index("ix_anexos_afastamento_empresa_id", "anexos_afastamento", ["empresa_id"])
    # Nenhuma policy pública: uploads são servidos pelo Flask após JWT/RBAC.
    op.execute('ALTER TABLE anexos_afastamento ENABLE ROW LEVEL SECURITY')


def downgrade():
    op.drop_table("anexos_afastamento")
