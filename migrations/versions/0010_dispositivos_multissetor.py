"""Autorizações por funcionário/setor; preserva dispositivos e marcações."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("dispositivos_usuarios_setores",
        sa.Column("dispositivo_id", UUID(as_uuid=True), primary_key=True),
        sa.Column("empresa_id", UUID(as_uuid=True), primary_key=True),
        sa.Column("usuario_id", UUID(as_uuid=True), primary_key=True),
        sa.Column("setor_id", UUID(as_uuid=True), primary_key=True),
        sa.Column("ativo", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("autorizado_por_id", UUID(as_uuid=True)),
        sa.Column("criado_em", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["empresa_id"], ["empresas.id"], name="fk_dispositivos_usuarios_setores_empresa_id_empresas", ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["dispositivo_id", "empresa_id", "usuario_id"],
            ["dispositivos_usuarios.dispositivo_id", "dispositivos_usuarios.empresa_id", "dispositivos_usuarios.usuario_id"],
            name="fk_dispositivos_escopos_vinculo", ondelete="RESTRICT", onupdate="RESTRICT"),
        sa.ForeignKeyConstraint(["setor_id", "empresa_id"], ["setores.id", "setores.empresa_id"],
            name="fk_dispositivos_escopos_setor", ondelete="RESTRICT", onupdate="RESTRICT"),
        sa.ForeignKeyConstraint(["autorizado_por_id", "empresa_id"], ["usuarios.id", "usuarios.empresa_id"],
            name="fk_dispositivos_escopos_autor", ondelete="RESTRICT", onupdate="RESTRICT"))
    op.create_index("ix_dispositivos_escopos_empresa_usuario", "dispositivos_usuarios_setores", ["empresa_id", "usuario_id", "ativo"])
    op.execute("""INSERT INTO dispositivos_usuarios_setores
        (dispositivo_id, empresa_id, usuario_id, setor_id, ativo, autorizado_por_id)
        SELECT d.id, d.empresa_id, v.usuario_id, d.setor_id, v.ativo AND d.ativo, v.autorizado_por_id
        FROM dispositivos d JOIN dispositivos_usuarios v ON v.dispositivo_id = d.id AND v.empresa_id = d.empresa_id
        WHERE d.tipo = 'RELOGIO'""")
    op.execute("ALTER TABLE dispositivos_usuarios_setores ENABLE ROW LEVEL SECURITY")


def downgrade():
    # Não reduzir silenciosamente permissões a um setor nem restaurar revogações.
    op.execute("""DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM dispositivos_usuarios_setores s JOIN dispositivos d
            ON d.id = s.dispositivo_id AND d.empresa_id = s.empresa_id
            JOIN dispositivos_usuarios v ON v.dispositivo_id = s.dispositivo_id AND v.empresa_id = s.empresa_id AND v.usuario_id = s.usuario_id
            WHERE s.setor_id <> d.setor_id OR s.ativo <> (v.ativo AND d.ativo))
        THEN RAISE EXCEPTION 'Existem autorizações multissetor ou revogações específicas; downgrade recusado.';
        END IF;
    END $$""")
    op.drop_table("dispositivos_usuarios_setores")
