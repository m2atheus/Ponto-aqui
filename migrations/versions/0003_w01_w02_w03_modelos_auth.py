"""W01/W02/W03: conta global, políticas de setor e cadastro de funcionários."""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

ACAO = postgresql.ENUM("BLOQUEAR", "PENDENTE", name="acao_fora_perimetro", create_type=False)


def upgrade():
    connection = op.get_bind()
    # Inconsistências legadas exigem revisão; nunca renomeamos contas ou
    # alteramos registros de ponto para forçar uma migration a passar.
    if connection.scalar(sa.text("SELECT EXISTS(SELECT 1 FROM usuarios GROUP BY email HAVING count(*) > 1)")):
        raise RuntimeError("W01: existem e-mails repetidos entre empresas; revise os identificadores antes do upgrade.")
    if connection.scalar(sa.text("""
        SELECT EXISTS(SELECT 1 FROM usuarios u WHERE u.papel = 'Superadmin' AND (
            EXISTS(SELECT 1 FROM alocacoes a WHERE a.usuario_id = u.id) OR
            EXISTS(SELECT 1 FROM dispositivos d WHERE d.usuario_id = u.id) OR
            EXISTS(SELECT 1 FROM registros_ponto p WHERE p.usuario_id = u.id OR p.enviado_por_id = u.id) OR
            EXISTS(SELECT 1 FROM justificativas_ajustes j WHERE j.usuario_id = u.id
                OR j.solicitado_por_id = u.id OR j.decidido_por_id = u.id)))
    """)):
        raise RuntimeError("W01: Superadmin possui vínculos de empresa; revise-os sem alterar as evidências de ponto.")
    if connection.scalar(sa.text("""
        SELECT EXISTS(SELECT 1 FROM alocacoes a JOIN alocacoes b
            ON a.id < b.id AND a.empresa_id = b.empresa_id
            AND a.usuario_id = b.usuario_id AND a.setor_id = b.setor_id
            AND daterange(a.data_inicio, a.data_fim, '[]') && daterange(b.data_inicio, b.data_fim, '[]'))
    """)):
        raise RuntimeError("W03: existem alocações sobrepostas; revise o histórico antes do upgrade.")

    op.execute("ALTER TYPE papel_usuario RENAME VALUE 'Relogio' TO 'UsuarioSetor'")
    op.alter_column("usuarios", "empresa_id", existing_type=sa.UUID(), nullable=True)
    op.execute("UPDATE usuarios SET empresa_id = NULL WHERE papel = 'Superadmin'")
    op.create_unique_constraint("uq_usuarios_email", "usuarios", ["email"])
    op.create_check_constraint("papel_empresa", "usuarios",
        "(papel = 'Superadmin' AND empresa_id IS NULL) OR (papel <> 'Superadmin' AND empresa_id IS NOT NULL)")

    ACAO.create(connection)
    op.add_column("setores", sa.Column("endereco", sa.String(255)))
    op.add_column("setores", sa.Column("exige_selfie", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("setores", sa.Column("acao_fora_perimetro", ACAO, nullable=False, server_default="BLOQUEAR"))
    op.add_column("setores", sa.Column("ignorar_localizacao", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.execute("""UPDATE setores SET
        acao_fora_perimetro = CASE WHEN politica_localizacao = 'Pendente'
            THEN 'PENDENTE'::acao_fora_perimetro ELSE 'BLOQUEAR'::acao_fora_perimetro END,
        ignorar_localizacao = (politica_localizacao = 'Ignorar')""")
    op.drop_column("setores", "politica_localizacao")

    op.create_table("funcionarios",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("empresa_id", sa.UUID(), nullable=False),
        sa.Column("usuario_id", sa.UUID()),
        sa.Column("nome", sa.String(150), nullable=False),
        sa.Column("matricula", sa.String(50), nullable=False),
        sa.Column("cargo", sa.String(120)),
        sa.Column("ativo", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("criado_em", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_funcionarios"),
        sa.ForeignKeyConstraint(["empresa_id"], ["empresas.id"],
            name="fk_funcionarios_empresa_id_empresas", ondelete="RESTRICT", onupdate="RESTRICT"),
        sa.ForeignKeyConstraint(["usuario_id", "empresa_id"], ["usuarios.id", "usuarios.empresa_id"],
            name="fk_funcionarios_usuario_empresa", ondelete="RESTRICT", onupdate="RESTRICT"),
        sa.UniqueConstraint("id", "empresa_id", name="uq_funcionarios_id_empresa"),
        sa.UniqueConstraint("id", "empresa_id", "usuario_id", name="uq_funcionarios_identidade"),
        sa.UniqueConstraint("empresa_id", "matricula", name="uq_funcionarios_empresa_matricula"),
        sa.UniqueConstraint("empresa_id", "usuario_id", name="uq_funcionarios_empresa_usuario"),
        sa.CheckConstraint("length(trim(matricula)) > 0", name=op.f("ck_funcionarios_matricula_preenchida")),
    )
    op.create_index("ix_funcionarios_empresa_id", "funcionarios", ["empresa_id"])
    op.execute("ALTER TABLE funcionarios ENABLE ROW LEVEL SECURITY")
    op.execute("""INSERT INTO funcionarios (id, empresa_id, usuario_id, nome, matricula, ativo, criado_em)
        SELECT u.id, u.empresa_id, u.id, u.nome,
            COALESCE(NULLIF(trim(u.matricula), ''), 'LEGACY-' || u.id::text), u.ativo, u.criado_em
        FROM usuarios u WHERE u.papel = 'Funcionario'
            OR EXISTS(SELECT 1 FROM alocacoes a WHERE a.usuario_id = u.id)""")
    op.add_column("alocacoes", sa.Column("funcionario_id", sa.UUID()))
    op.execute("UPDATE alocacoes SET funcionario_id = usuario_id")
    op.alter_column("alocacoes", "funcionario_id", existing_type=sa.UUID(), nullable=False)
    op.alter_column("alocacoes", "usuario_id", existing_type=sa.UUID(), nullable=True)
    op.alter_column("alocacoes", "escala_id", existing_type=sa.UUID(), nullable=True)
    op.create_foreign_key("fk_alocacoes_funcionario_empresa", "alocacoes", "funcionarios",
        ["funcionario_id", "empresa_id"], ["id", "empresa_id"], ondelete="RESTRICT", onupdate="RESTRICT")
    op.create_foreign_key("fk_alocacoes_funcionario_usuario", "alocacoes", "funcionarios",
        ["funcionario_id", "empresa_id", "usuario_id"], ["id", "empresa_id", "usuario_id"],
        ondelete="RESTRICT", onupdate="RESTRICT")

    # Supabase pode ter btree_gist no schema extensions; respeitamos sua posição.
    # A constraint guarda os OIDs dos operadores, sem depender do search_path runtime.
    op.execute("CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public")
    extension_schema = connection.scalar(sa.text("""SELECT n.nspname FROM pg_extension e
        JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'btree_gist'"""))
    original_path = connection.scalar(sa.text("SHOW search_path"))
    quoted_schema = connection.dialect.identifier_preparer.quote(extension_schema)
    connection.execute(sa.text("SELECT set_config('search_path', :path, true)"),
        {"path": original_path + ", " + quoted_schema})
    op.execute("""ALTER TABLE alocacoes ADD CONSTRAINT ex_alocacoes_periodos_sobrepostos
        EXCLUDE USING gist (empresa_id WITH =, funcionario_id WITH =, setor_id WITH =,
            daterange(data_inicio, data_fim, '[]') WITH &&)""")
    connection.execute(sa.text("SELECT set_config('search_path', :path, true)"), {"path": original_path})


def downgrade():
    if op.get_bind().scalar(sa.text("""SELECT EXISTS(SELECT 1 FROM funcionarios)
        OR EXISTS(SELECT 1 FROM usuarios WHERE empresa_id IS NULL)""")):
        raise RuntimeError("Downgrade W01/W03 bloqueado: existem contas globais ou funcionários a preservar.")
    op.drop_constraint("ex_alocacoes_periodos_sobrepostos", "alocacoes")
    op.drop_constraint("fk_alocacoes_funcionario_usuario", "alocacoes", type_="foreignkey")
    op.drop_constraint("fk_alocacoes_funcionario_empresa", "alocacoes", type_="foreignkey")
    op.drop_column("alocacoes", "funcionario_id")
    op.alter_column("alocacoes", "usuario_id", existing_type=sa.UUID(), nullable=False)
    op.alter_column("alocacoes", "escala_id", existing_type=sa.UUID(), nullable=False)
    op.drop_index("ix_funcionarios_empresa_id", table_name="funcionarios")
    op.drop_table("funcionarios")
    policy = postgresql.ENUM("Bloquear", "Pendente", "Ignorar", name="politica_localizacao", create_type=False)
    op.add_column("setores", sa.Column("politica_localizacao", policy, nullable=False, server_default="Bloquear"))
    op.execute("""UPDATE setores SET politica_localizacao = CASE
        WHEN ignorar_localizacao THEN 'Ignorar'::politica_localizacao
        WHEN acao_fora_perimetro = 'PENDENTE' THEN 'Pendente'::politica_localizacao
        ELSE 'Bloquear'::politica_localizacao END""")
    for column in ("endereco", "exige_selfie", "acao_fora_perimetro", "ignorar_localizacao"):
        op.drop_column("setores", column)
    ACAO.drop(op.get_bind())
    op.drop_constraint(op.f("ck_usuarios_papel_empresa"), "usuarios", type_="check")
    op.drop_constraint("uq_usuarios_email", "usuarios", type_="unique")
    op.alter_column("usuarios", "empresa_id", existing_type=sa.UUID(), nullable=False)
    op.execute("ALTER TYPE papel_usuario RENAME VALUE 'UsuarioSetor' TO 'Relogio'")
    # btree_gist pode ser compartilhada com outros sistemas; não a removemos.
