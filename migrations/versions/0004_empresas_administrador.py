"""Responsável da empresa vinculado à conta da mesma empresa."""
from alembic import op
import sqlalchemy as sa

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("empresas", sa.Column("admin_email", sa.String(254)))
    op.create_foreign_key("fk_empresas_administrador", "empresas", "usuarios",
        ["id", "admin_email"], ["empresa_id", "email"], ondelete="RESTRICT",
        deferrable=True, initially="DEFERRED")


def downgrade():
    if op.get_bind().scalar(sa.text("SELECT EXISTS(SELECT 1 FROM empresas WHERE admin_email IS NOT NULL)")):
        raise RuntimeError("Downgrade bloqueado: empresas possuem administradores vinculados.")
    op.drop_constraint("fk_empresas_administrador", "empresas", type_="foreignkey")
    op.drop_column("empresas", "admin_email")
