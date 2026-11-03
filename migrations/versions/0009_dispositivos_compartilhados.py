"""Vínculos individuais de aparelhos, preservando todas as marcações."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade():
    op.create_unique_constraint("uq_dispositivos_id_empresa", "dispositivos", ["id", "empresa_id"])
    op.create_table("dispositivos_usuarios",
        sa.Column("dispositivo_id", UUID(as_uuid=True), primary_key=True),
        sa.Column("empresa_id", UUID(as_uuid=True), primary_key=True),
        sa.Column("usuario_id", UUID(as_uuid=True), primary_key=True),
        sa.Column("ativo", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("autorizado_por_id", UUID(as_uuid=True)),
        sa.Column("criado_em", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["empresa_id"], ["empresas.id"], name="fk_dispositivos_usuarios_empresa_id_empresas", ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["dispositivo_id", "empresa_id"], ["dispositivos.id", "dispositivos.empresa_id"], name="fk_dispositivos_usuarios_dispositivo", ondelete="RESTRICT", onupdate="RESTRICT"),
        sa.ForeignKeyConstraint(["usuario_id", "empresa_id"], ["usuarios.id", "usuarios.empresa_id"], name="fk_dispositivos_usuarios_usuario", ondelete="RESTRICT", onupdate="RESTRICT"),
        sa.ForeignKeyConstraint(["autorizado_por_id", "empresa_id"], ["usuarios.id", "usuarios.empresa_id"], name="fk_dispositivos_usuarios_autor", ondelete="RESTRICT", onupdate="RESTRICT"))
    op.create_index("ix_dispositivos_usuarios_empresa_usuario", "dispositivos_usuarios", ["empresa_id", "usuario_id", "ativo"])
    op.execute("""INSERT INTO dispositivos_usuarios (dispositivo_id, empresa_id, usuario_id, ativo)
        SELECT id, empresa_id, usuario_id, ativo FROM dispositivos WHERE tipo = 'PESSOAL'""")
    # Compatibilidade com inserções pessoais já usadas por serviços/clientes antigos.
    op.execute("""CREATE FUNCTION vincular_dispositivo_pessoal() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
        IF NEW.tipo = 'PESSOAL' THEN
            INSERT INTO dispositivos_usuarios (dispositivo_id, empresa_id, usuario_id, ativo)
            VALUES (NEW.id, NEW.empresa_id, NEW.usuario_id, NEW.ativo) ON CONFLICT DO NOTHING;
        END IF;
        RETURN NEW;
    END $$""")
    op.execute("""CREATE TRIGGER trg_dispositivo_pessoal_vinculo AFTER INSERT ON dispositivos
        FOR EACH ROW EXECUTE FUNCTION vincular_dispositivo_pessoal()""")
    op.drop_constraint("fk_registros_dispositivo_identidade", "registros_ponto", type_="foreignkey")
    op.create_foreign_key("fk_registros_dispositivo_identidade", "registros_ponto", "dispositivos_usuarios",
        ["dispositivo_registrado_id", "empresa_id", "usuario_id"], ["dispositivo_id", "empresa_id", "usuario_id"],
        ondelete="RESTRICT", onupdate="RESTRICT")
    op.execute("ALTER TABLE dispositivos_usuarios ENABLE ROW LEVEL SECURITY")


def downgrade():
    op.execute("""DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM registros_ponto p JOIN dispositivos d
            ON d.id = p.dispositivo_registrado_id AND d.empresa_id = p.empresa_id WHERE d.tipo = 'RELOGIO')
        THEN RAISE EXCEPTION 'Existem marcações de relógios compartilhados; downgrade recusado.';
        END IF;
    END $$""")
    op.drop_constraint("fk_registros_dispositivo_identidade", "registros_ponto", type_="foreignkey")
    op.create_foreign_key("fk_registros_dispositivo_identidade", "registros_ponto", "dispositivos",
        ["dispositivo_registrado_id", "empresa_id", "usuario_id"], ["id", "empresa_id", "usuario_id"],
        ondelete="RESTRICT", onupdate="RESTRICT")
    op.execute("DROP TRIGGER trg_dispositivo_pessoal_vinculo ON dispositivos")
    op.execute("DROP FUNCTION vincular_dispositivo_pessoal()")
    op.drop_table("dispositivos_usuarios")
    op.drop_constraint("uq_dispositivos_id_empresa", "dispositivos", type_="unique")
