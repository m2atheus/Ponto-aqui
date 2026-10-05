"""W09: recepção offline, classificação imutável, dispositivos e selfies privadas."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

ENUMS = (
    postgresql.ENUM("Bloquear", "Pendente", "Ignorar", name="politica_localizacao", create_type=False),
    postgresql.ENUM("Aceita", "PendenteAnalise", "Recusada", name="situacao_ponto", create_type=False),
)
CHECKS = {
    "posicao_consistente": "(latitude IS NULL AND longitude IS NULL AND distancia_centro_metros IS NULL) OR "
        "(latitude IS NOT NULL AND longitude IS NOT NULL AND distancia_centro_metros IS NOT NULL AND distancia_centro_metros >= 0)",
    "motivos_array": "jsonb_typeof(motivos) = 'array'",
    "motivos_situacao": "(situacao = 'Aceita' AND jsonb_array_length(motivos) = 0) OR "
        "(situacao <> 'Aceita' AND jsonb_array_length(motivos) > 0)",
    "dispositivo_consistente": "dispositivo_registrado_id IS NULL OR dispositivo_registrado_id = dispositivo_cliente_id",
    "dispositivo_situacao": "dispositivo_cliente_id IS NULL OR situacao = 'Recusada' OR dispositivo_registrado_id IS NOT NULL",
    "limite_desvio_validado": "limite_desvio_validado_segundos >= 0",
    "aceita_consistente": "situacao <> 'Aceita' OR ((politica_localizacao_validada = 'Ignorar' OR "
        "(distancia_centro_metros IS NOT NULL AND distancia_centro_metros <= raio_validado_metros)) "
        "AND desvio_relogio_segundos BETWEEN -limite_desvio_validado_segundos AND limite_desvio_validado_segundos)",
}


def upgrade():
    for enum in ENUMS:
        enum.create(op.get_bind(), checkfirst=False)
    op.create_table('dispositivos',
    sa.Column('usuario_id', sa.UUID(), nullable=False),
    sa.Column('nome', sa.String(length=120), nullable=False),
    sa.Column('ativo', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_dispositivos_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['usuario_id', 'empresa_id'], ['usuarios.id', 'usuarios.empresa_id'], name='fk_dispositivos_usuario_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_dispositivos')),
    sa.UniqueConstraint('id', 'empresa_id', 'usuario_id', name='uq_dispositivos_identidade')
    )
    op.create_index(op.f('ix_dispositivos_empresa_id'), 'dispositivos', ['empresa_id'], unique=False)
    op.create_table('selfies_ponto',
    sa.Column('usuario_id', sa.UUID(), nullable=False),
    sa.Column('evento_cliente_id', sa.UUID(), nullable=False),
    sa.Column('conteudo', sa.LargeBinary(), nullable=False),
    sa.Column('content_type', sa.String(length=32), nullable=False),
    sa.Column('sha256', sa.String(length=64), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("content_type IN ('image/jpeg', 'image/png')", name=op.f('ck_selfies_ponto_tipo_imagem_valido')),
    sa.CheckConstraint("sha256 ~ '^[0-9a-f]{64}$'", name=op.f('ck_selfies_ponto_sha256_formato')),
    sa.CheckConstraint('octet_length(conteudo) BETWEEN 1 AND 2097152', name=op.f('ck_selfies_ponto_tamanho_imagem_valido')),
    sa.ForeignKeyConstraint(['empresa_id', 'usuario_id', 'evento_cliente_id'], ['registros_ponto.empresa_id', 'registros_ponto.usuario_id', 'registros_ponto.evento_cliente_id'], name='fk_selfies_registro_identidade', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_selfies_ponto_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_selfies_ponto')),
    sa.UniqueConstraint('empresa_id', 'evento_cliente_id', name='uq_selfies_evento_empresa')
    )
    op.create_index(op.f('ix_selfies_ponto_empresa_id'), 'selfies_ponto', ['empresa_id'], unique=False)
    op.add_column('registros_ponto', sa.Column('desvio_relogio_segundos', sa.BigInteger(), server_default=sa.text('0'), nullable=False))
    op.add_column('registros_ponto', sa.Column('registrado_offline', sa.Boolean(), server_default=sa.text('false'), nullable=False))
    op.add_column('registros_ponto', sa.Column('dados_dispositivo', postgresql.JSONB(astext_type=sa.Text()), nullable=True))
    op.add_column('registros_ponto', sa.Column('dispositivo_cliente_id', sa.UUID(), nullable=True))
    op.add_column('registros_ponto', sa.Column('dispositivo_registrado_id', sa.UUID(), nullable=True))
    op.add_column('registros_ponto', sa.Column('situacao', sa.Enum('Aceita', 'PendenteAnalise', 'Recusada', name='situacao_ponto'), server_default='Aceita', nullable=False))
    op.add_column('registros_ponto', sa.Column('motivos', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'[]'::jsonb"), nullable=False))
    op.add_column('registros_ponto', sa.Column('politica_localizacao_validada', sa.Enum('Bloquear', 'Pendente', 'Ignorar', name='politica_localizacao'), server_default='Bloquear', nullable=False))
    op.add_column('registros_ponto', sa.Column('limite_desvio_validado_segundos', sa.Integer(), server_default=sa.text('120'), nullable=False))
    op.alter_column('registros_ponto', 'latitude',
               existing_type=sa.NUMERIC(precision=10, scale=7),
               nullable=True)
    op.alter_column('registros_ponto', 'longitude',
               existing_type=sa.NUMERIC(precision=10, scale=7),
               nullable=True)
    op.alter_column('registros_ponto', 'distancia_centro_metros',
               existing_type=sa.NUMERIC(precision=12, scale=2),
               nullable=True)
    op.create_unique_constraint('uq_registros_evento_empresa', 'registros_ponto', ['empresa_id', 'evento_cliente_id'])
    op.create_foreign_key('fk_registros_dispositivo_identidade', 'registros_ponto', 'dispositivos', ['dispositivo_registrado_id', 'empresa_id', 'usuario_id'], ['id', 'empresa_id', 'usuario_id'], onupdate='RESTRICT', ondelete='RESTRICT')
    op.add_column('setores', sa.Column('politica_localizacao', sa.Enum('Bloquear', 'Pendente', 'Ignorar', name='politica_localizacao'), server_default='Bloquear', nullable=False))
    op.add_column('setores', sa.Column('limite_desvio_relogio_segundos', sa.Integer(), server_default=sa.text('120'), nullable=False))
    op.drop_constraint(op.f("ck_registros_ponto_distancia_dentro_perimetro"), "registros_ponto", type_="check")
    for name, condition in CHECKS.items():
        op.create_check_constraint(name, "registros_ponto", condition)
    op.create_check_constraint("limite_desvio_valido", "setores", "limite_desvio_relogio_segundos >= 0")
    for table in ("dispositivos", "selfies_ponto"):
        op.execute(f'ALTER TABLE "{table}" ENABLE ROW LEVEL SECURITY')
    op.execute("""
        CREATE TRIGGER trg_selfies_ponto_imutaveis
        BEFORE UPDATE OR DELETE ON selfies_ponto
        FOR EACH ROW EXECUTE FUNCTION impedir_mutacao_registro_ponto();
    """)
    op.execute("""
        CREATE TRIGGER trg_selfies_ponto_sem_truncate
        BEFORE TRUNCATE ON selfies_ponto
        FOR EACH STATEMENT EXECUTE FUNCTION impedir_mutacao_registro_ponto();
    """)


def downgrade():
    # Nunca elimina silenciosamente as evidências recebidas pela W09.
    has_data = op.get_bind().scalar(sa.text(
        "SELECT EXISTS(SELECT 1 FROM registros_ponto WHERE dispositivo_cliente_id IS NOT NULL) "
        "OR EXISTS(SELECT 1 FROM selfies_ponto) OR EXISTS(SELECT 1 FROM dispositivos)"
    ))
    if has_data:
        raise RuntimeError("Downgrade W09 bloqueado: existem dispositivos ou evidências imutáveis.")
    for name in CHECKS:
        op.drop_constraint(op.f("ck_registros_ponto_" + name), "registros_ponto", type_="check")
    op.drop_constraint(op.f("ck_setores_limite_desvio_valido"), "setores", type_="check")
    op.drop_column('setores', 'limite_desvio_relogio_segundos')
    op.drop_column('setores', 'politica_localizacao')
    op.drop_constraint('fk_registros_dispositivo_identidade', 'registros_ponto', type_='foreignkey')
    op.drop_constraint('uq_registros_evento_empresa', 'registros_ponto', type_='unique')
    op.alter_column('registros_ponto', 'distancia_centro_metros',
               existing_type=sa.NUMERIC(precision=12, scale=2),
               nullable=False)
    op.alter_column('registros_ponto', 'longitude',
               existing_type=sa.NUMERIC(precision=10, scale=7),
               nullable=False)
    op.alter_column('registros_ponto', 'latitude',
               existing_type=sa.NUMERIC(precision=10, scale=7),
               nullable=False)
    op.drop_column('registros_ponto', 'limite_desvio_validado_segundos')
    op.drop_column('registros_ponto', 'politica_localizacao_validada')
    op.drop_column('registros_ponto', 'motivos')
    op.drop_column('registros_ponto', 'situacao')
    op.drop_column('registros_ponto', 'dispositivo_registrado_id')
    op.drop_column('registros_ponto', 'dispositivo_cliente_id')
    op.drop_column('registros_ponto', 'dados_dispositivo')
    op.drop_column('registros_ponto', 'registrado_offline')
    op.drop_column('registros_ponto', 'desvio_relogio_segundos')
    op.drop_index(op.f('ix_selfies_ponto_empresa_id'), table_name='selfies_ponto')
    op.drop_table('selfies_ponto')
    op.drop_index(op.f('ix_dispositivos_empresa_id'), table_name='dispositivos')
    op.drop_table('dispositivos')
    op.create_check_constraint("distancia_dentro_perimetro", "registros_ponto",
        "distancia_centro_metros >= 0 AND distancia_centro_metros <= raio_validado_metros")
    for enum in reversed(ENUMS):
        enum.drop(op.get_bind(), checkfirst=False)
