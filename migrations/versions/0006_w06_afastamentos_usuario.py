"""W06: vincula afastamentos à conta sem perder funcionários sem login."""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("afastamentos", sa.Column("usuario_id", UUID(as_uuid=True)))
    op.execute("""UPDATE afastamentos AS a SET usuario_id = f.usuario_id
        FROM funcionarios AS f
        WHERE a.funcionario_id = f.id AND a.empresa_id = f.empresa_id""")
    op.create_foreign_key("fk_afastamentos_usuario_empresa", "afastamentos", "usuarios",
        ["usuario_id", "empresa_id"], ["id", "empresa_id"], ondelete="RESTRICT", onupdate="RESTRICT")
    op.create_foreign_key("fk_afastamentos_funcionario_usuario", "afastamentos", "funcionarios",
        ["funcionario_id", "empresa_id", "usuario_id"], ["id", "empresa_id", "usuario_id"],
        ondelete="RESTRICT", onupdate="RESTRICT")
    op.create_index("ix_afastamentos_empresa_usuario_datas", "afastamentos",
        ["empresa_id", "usuario_id", "data_inicio", "data_fim"])


def downgrade():
    op.drop_index("ix_afastamentos_empresa_usuario_datas", table_name="afastamentos")
    op.drop_constraint("fk_afastamentos_funcionario_usuario", "afastamentos", type_="foreignkey")
    op.drop_constraint("fk_afastamentos_usuario_empresa", "afastamentos", type_="foreignkey")
    op.drop_column("afastamentos", "usuario_id")
