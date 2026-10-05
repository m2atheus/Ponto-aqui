"""estrutura inicial multi tenant

Revision ID: 0001
Revises: 
Create Date: 2026-10-05 12:53:25.925487

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '0001'
down_revision = None
branch_labels = None
depends_on = None


# Explicit creation avoids creating tipo_ponto twice, as it is shared by
# registros_ponto and justificativas_ajustes. Keep migrations self-contained.
ENUMS = {
    'papel_usuario': postgresql.ENUM(
        'Superadmin', 'RH', 'Gestor', 'Funcionario', 'Relogio',
        name='papel_usuario', create_type=False,
    ),
    'tipo_escala': postgresql.ENUM(
        'Semanal', 'Ciclica', name='tipo_escala', create_type=False,
    ),
    'tipo_ponto': postgresql.ENUM(
        'Entrada', 'InicioIntervalo', 'FimIntervalo', 'Saida',
        name='tipo_ponto', create_type=False,
    ),
    'origem_ponto': postgresql.ENUM(
        'Mobile', 'Web', 'Relogio', name='origem_ponto', create_type=False,
    ),
    'status_ajuste': postgresql.ENUM(
        'Pendente', 'Aprovado', 'Rejeitado', name='status_ajuste', create_type=False,
    ),
}


def upgrade():
    for enum_type in ENUMS.values():
        enum_type.create(op.get_bind(), checkfirst=False)
    op.create_table('empresas',
    sa.Column('razao_social', sa.String(length=200), nullable=False),
    sa.Column('nome_fantasia', sa.String(length=200), nullable=True),
    sa.Column('cnpj', sa.String(length=14), nullable=False),
    sa.Column('fuso_horario', sa.String(length=64), server_default='America/Sao_Paulo', nullable=False),
    sa.Column('ativo', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("cnpj ~ '^[0-9]{14}$'", name=op.f('ck_empresas_cnpj_formato')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_empresas')),
    sa.UniqueConstraint('cnpj', name=op.f('uq_empresas_cnpj'))
    )
    op.create_table('escalas',
    sa.Column('nome', sa.String(length=120), nullable=False),
    sa.Column('tipo', ENUMS['tipo_escala'], nullable=False),
    sa.Column('carga_semanal_minutos', sa.Integer(), nullable=False),
    sa.Column('tolerancia_minutos', sa.Integer(), server_default=sa.text('0'), nullable=False),
    sa.Column('regras', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('ativo', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("jsonb_typeof(regras) = 'object'", name=op.f('ck_escalas_regras_objeto')),
    sa.CheckConstraint('carga_semanal_minutos BETWEEN 0 AND 10080', name=op.f('ck_escalas_carga_semanal_valida')),
    sa.CheckConstraint('tolerancia_minutos >= 0', name=op.f('ck_escalas_tolerancia_valida')),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_escalas_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_escalas')),
    sa.UniqueConstraint('empresa_id', 'nome', name='uq_escalas_empresa_nome'),
    sa.UniqueConstraint('id', 'empresa_id', name='uq_escalas_id_empresa')
    )
    op.create_index(op.f('ix_escalas_empresa_id'), 'escalas', ['empresa_id'], unique=False)
    op.create_table('setores',
    sa.Column('nome', sa.String(length=120), nullable=False),
    sa.Column('latitude_centro', sa.Numeric(precision=10, scale=7), nullable=False),
    sa.Column('longitude_centro', sa.Numeric(precision=10, scale=7), nullable=False),
    sa.Column('raio_metros', sa.Numeric(precision=12, scale=2), nullable=False),
    sa.Column('ativo', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint('latitude_centro BETWEEN -90 AND 90', name=op.f('ck_setores_latitude_centro_valida')),
    sa.CheckConstraint('longitude_centro BETWEEN -180 AND 180', name=op.f('ck_setores_longitude_centro_valida')),
    sa.CheckConstraint('raio_metros > 0', name=op.f('ck_setores_raio_positivo')),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_setores_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_setores')),
    sa.UniqueConstraint('empresa_id', 'nome', name='uq_setores_empresa_nome'),
    sa.UniqueConstraint('id', 'empresa_id', name='uq_setores_id_empresa')
    )
    op.create_index(op.f('ix_setores_empresa_id'), 'setores', ['empresa_id'], unique=False)
    op.create_table('usuarios',
    sa.Column('nome', sa.String(length=150), nullable=False),
    sa.Column('email', sa.String(length=254), nullable=False),
    sa.Column('senha_hash', sa.Text(), nullable=False),
    sa.Column('papel', ENUMS['papel_usuario'], server_default='Funcionario', nullable=False),
    sa.Column('matricula', sa.String(length=50), nullable=True),
    sa.Column('ativo', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint('email = lower(email)', name=op.f('ck_usuarios_email_minusculo')),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_usuarios_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_usuarios')),
    sa.UniqueConstraint('empresa_id', 'email', name='uq_usuarios_empresa_email'),
    sa.UniqueConstraint('empresa_id', 'matricula', name='uq_usuarios_empresa_matricula'),
    sa.UniqueConstraint('id', 'empresa_id', name='uq_usuarios_id_empresa')
    )
    op.create_index(op.f('ix_usuarios_empresa_id'), 'usuarios', ['empresa_id'], unique=False)
    op.create_table('alocacoes',
    sa.Column('usuario_id', sa.UUID(), nullable=False),
    sa.Column('setor_id', sa.UUID(), nullable=False),
    sa.Column('escala_id', sa.UUID(), nullable=False),
    sa.Column('data_inicio', sa.Date(), nullable=False),
    sa.Column('data_fim', sa.Date(), nullable=True),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint('data_fim IS NULL OR data_fim >= data_inicio', name=op.f('ck_alocacoes_vigencia_valida')),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_alocacoes_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['escala_id', 'empresa_id'], ['escalas.id', 'escalas.empresa_id'], name='fk_alocacoes_escala_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['setor_id', 'empresa_id'], ['setores.id', 'setores.empresa_id'], name='fk_alocacoes_setor_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['usuario_id', 'empresa_id'], ['usuarios.id', 'usuarios.empresa_id'], name='fk_alocacoes_usuario_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_alocacoes')),
    sa.UniqueConstraint('id', 'empresa_id', name='uq_alocacoes_id_empresa'),
    sa.UniqueConstraint('id', 'usuario_id', 'setor_id', 'empresa_id', name='uq_alocacoes_identidade')
    )
    op.create_index(op.f('ix_alocacoes_empresa_id'), 'alocacoes', ['empresa_id'], unique=False)
    op.create_index('ix_alocacoes_empresa_usuario_inicio', 'alocacoes', ['empresa_id', 'usuario_id', 'data_inicio'], unique=False)
    op.create_table('registros_ponto',
    sa.Column('usuario_id', sa.UUID(), nullable=False),
    sa.Column('setor_id', sa.UUID(), nullable=False),
    sa.Column('alocacao_id', sa.UUID(), nullable=False),
    sa.Column('enviado_por_id', sa.UUID(), nullable=False),
    sa.Column('evento_cliente_id', sa.UUID(), nullable=False),
    sa.Column('payload_hash', sa.String(length=64), nullable=False),
    sa.Column('tipo', ENUMS['tipo_ponto'], nullable=False),
    sa.Column('origem', ENUMS['origem_ponto'], nullable=False),
    sa.Column('ocorrido_em', sa.DateTime(timezone=True), nullable=False),
    sa.Column('recebido_em', sa.DateTime(timezone=True), server_default=sa.text('clock_timestamp()'), nullable=False),
    sa.Column('offset_original_minutos', sa.SmallInteger(), nullable=False),
    sa.Column('latitude', sa.Numeric(precision=10, scale=7), nullable=False),
    sa.Column('longitude', sa.Numeric(precision=10, scale=7), nullable=False),
    sa.Column('precisao_metros', sa.Numeric(precision=12, scale=2), nullable=True),
    sa.Column('latitude_centro_validada', sa.Numeric(precision=10, scale=7), nullable=False),
    sa.Column('longitude_centro_validada', sa.Numeric(precision=10, scale=7), nullable=False),
    sa.Column('raio_validado_metros', sa.Numeric(precision=12, scale=2), nullable=False),
    sa.Column('distancia_centro_metros', sa.Numeric(precision=12, scale=2), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.CheckConstraint("payload_hash ~ '^[0-9a-f]{64}$'", name=op.f('ck_registros_ponto_payload_hash_formato')),
    sa.CheckConstraint('distancia_centro_metros >= 0 AND distancia_centro_metros <= raio_validado_metros', name=op.f('ck_registros_ponto_distancia_dentro_perimetro')),
    sa.CheckConstraint('latitude BETWEEN -90 AND 90', name=op.f('ck_registros_ponto_latitude_valida')),
    sa.CheckConstraint('latitude_centro_validada BETWEEN -90 AND 90', name=op.f('ck_registros_ponto_latitude_centro_validada')),
    sa.CheckConstraint('longitude BETWEEN -180 AND 180', name=op.f('ck_registros_ponto_longitude_valida')),
    sa.CheckConstraint('longitude_centro_validada BETWEEN -180 AND 180', name=op.f('ck_registros_ponto_longitude_centro_validada')),
    sa.CheckConstraint('offset_original_minutos BETWEEN -840 AND 840', name=op.f('ck_registros_ponto_offset_original_valido')),
    sa.CheckConstraint('precisao_metros IS NULL OR precisao_metros >= 0', name=op.f('ck_registros_ponto_precisao_valida')),
    sa.CheckConstraint('raio_validado_metros > 0', name=op.f('ck_registros_ponto_raio_validado_positivo')),
    sa.ForeignKeyConstraint(['alocacao_id', 'usuario_id', 'setor_id', 'empresa_id'], ['alocacoes.id', 'alocacoes.usuario_id', 'alocacoes.setor_id', 'alocacoes.empresa_id'], name='fk_registros_alocacao_identidade', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_registros_ponto_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['enviado_por_id', 'empresa_id'], ['usuarios.id', 'usuarios.empresa_id'], name='fk_registros_remetente_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_registros_ponto')),
    sa.UniqueConstraint('empresa_id', 'usuario_id', 'evento_cliente_id', name='uq_registros_evento_cliente'),
    sa.UniqueConstraint('id', 'empresa_id', 'usuario_id', name='uq_registros_identidade')
    )
    op.create_index('ix_registros_empresa_usuario_ocorrido', 'registros_ponto', ['empresa_id', 'usuario_id', 'ocorrido_em'], unique=False)
    op.create_index(op.f('ix_registros_ponto_empresa_id'), 'registros_ponto', ['empresa_id'], unique=False)
    op.create_table('justificativas_ajustes',
    sa.Column('usuario_id', sa.UUID(), nullable=False),
    sa.Column('registro_ponto_id', sa.UUID(), nullable=True),
    sa.Column('solicitado_por_id', sa.UUID(), nullable=False),
    sa.Column('justificativa', sa.Text(), nullable=False),
    sa.Column('tipo_proposto', ENUMS['tipo_ponto'], nullable=False),
    sa.Column('ocorrido_em_proposto', sa.DateTime(timezone=True), nullable=False),
    sa.Column('status', ENUMS['status_ajuste'], server_default='Pendente', nullable=False),
    sa.Column('decidido_por_id', sa.UUID(), nullable=True),
    sa.Column('decidido_em', sa.DateTime(timezone=True), nullable=True),
    sa.Column('observacao_decisao', sa.Text(), nullable=True),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("(status = 'Pendente' AND decidido_por_id IS NULL AND decidido_em IS NULL) OR (status IN ('Aprovado', 'Rejeitado') AND decidido_por_id IS NOT NULL AND decidido_em IS NOT NULL)", name=op.f('ck_justificativas_ajustes_decisao_consistente')),
    sa.CheckConstraint('length(trim(justificativa)) > 0', name=op.f('ck_justificativas_ajustes_justificativa_obrigatoria')),
    sa.ForeignKeyConstraint(['decidido_por_id', 'empresa_id'], ['usuarios.id', 'usuarios.empresa_id'], name='fk_ajustes_decisor_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_justificativas_ajustes_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['registro_ponto_id', 'empresa_id', 'usuario_id'], ['registros_ponto.id', 'registros_ponto.empresa_id', 'registros_ponto.usuario_id'], name='fk_ajustes_registro_identidade', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['solicitado_por_id', 'empresa_id'], ['usuarios.id', 'usuarios.empresa_id'], name='fk_ajustes_solicitante_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['usuario_id', 'empresa_id'], ['usuarios.id', 'usuarios.empresa_id'], name='fk_ajustes_usuario_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_justificativas_ajustes')),
    sa.UniqueConstraint('id', 'empresa_id', name='uq_ajustes_id_empresa')
    )
    op.create_index('ix_ajustes_empresa_status_criado', 'justificativas_ajustes', ['empresa_id', 'status', 'criado_em'], unique=False)
    op.create_index('ix_ajustes_empresa_usuario', 'justificativas_ajustes', ['empresa_id', 'usuario_id'], unique=False)
    op.create_index(op.f('ix_justificativas_ajustes_empresa_id'), 'justificativas_ajustes', ['empresa_id'], unique=False)
    op.execute("""
        CREATE OR REPLACE FUNCTION impedir_mutacao_registro_ponto()
        RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            RAISE EXCEPTION
                'Registros de ponto sao imutaveis; utilize justificativas_ajustes';
        END;
        $$;
    """)
    op.execute("""
        CREATE TRIGGER trg_registros_ponto_imutaveis
        BEFORE UPDATE OR DELETE ON registros_ponto
        FOR EACH ROW EXECUTE FUNCTION impedir_mutacao_registro_ponto();
    """)
    op.execute("""
        CREATE TRIGGER trg_registros_ponto_sem_truncate
        BEFORE TRUNCATE ON registros_ponto
        FOR EACH STATEMENT EXECUTE FUNCTION impedir_mutacao_registro_ponto();
    """)
    # Supabase exposes public through PostgREST. Default-deny RLS prevents
    # direct access by anon/authenticated; this API uses a trusted server role.
    # No Supabase JWT policy is created: API JWTs are validated by Flask.
    for table_name in (
        'empresas', 'usuarios', 'setores', 'escalas', 'alocacoes',
        'registros_ponto', 'justificativas_ajustes',
    ):
        op.execute(f'ALTER TABLE "{table_name}" ENABLE ROW LEVEL SECURITY')


def downgrade():
    op.drop_index(op.f('ix_justificativas_ajustes_empresa_id'), table_name='justificativas_ajustes')
    op.drop_index('ix_ajustes_empresa_usuario', table_name='justificativas_ajustes')
    op.drop_index('ix_ajustes_empresa_status_criado', table_name='justificativas_ajustes')
    op.drop_table('justificativas_ajustes')
    op.drop_index(op.f('ix_registros_ponto_empresa_id'), table_name='registros_ponto')
    op.drop_index('ix_registros_empresa_usuario_ocorrido', table_name='registros_ponto')
    op.drop_table('registros_ponto')
    op.drop_index('ix_alocacoes_empresa_usuario_inicio', table_name='alocacoes')
    op.drop_index(op.f('ix_alocacoes_empresa_id'), table_name='alocacoes')
    op.drop_table('alocacoes')
    op.drop_index(op.f('ix_usuarios_empresa_id'), table_name='usuarios')
    op.drop_table('usuarios')
    op.drop_index(op.f('ix_setores_empresa_id'), table_name='setores')
    op.drop_table('setores')
    op.drop_index(op.f('ix_escalas_empresa_id'), table_name='escalas')
    op.drop_table('escalas')
    op.drop_table('empresas')
    op.execute('DROP FUNCTION impedir_mutacao_registro_ponto()')
    for enum_type in reversed(list(ENUMS.values())):
        enum_type.drop(op.get_bind(), checkfirst=False)
