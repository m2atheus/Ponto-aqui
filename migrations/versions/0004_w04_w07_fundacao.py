"""w04 w07 escalas turnos feriados afastamentos dispositivos

Revision ID: 0004_w04_w07
Revises: 0003
Create Date: 2026-10-05 21:23:03.637051

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '0004_w04_w07'
down_revision = '0003'
branch_labels = None
depends_on = None

DISPOSITIVO = postgresql.ENUM('PESSOAL', 'RELOGIO', name='tipo_dispositivo', create_type=False)
MODELO = postgresql.ENUM('24x72', '12x36', 'Diurno', '5x2', 'Legado', name='modelo_escala', create_type=False)


def upgrade():
    connection = op.get_bind()
    DISPOSITIVO.create(connection)
    MODELO.create(connection)
    # btree_gist já instalada por 0003 pode estar no schema extensions do Supabase.
    original_path = connection.scalar(sa.text('SHOW search_path'))
    extension_schema = connection.scalar(sa.text('''SELECT n.nspname FROM pg_extension e
        JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'btree_gist' '''))
    quoted_schema = connection.dialect.identifier_preparer.quote(extension_schema)
    connection.execute(sa.text("SELECT set_config('search_path', :path, true)"),
                       {'path': original_path + ', ' + quoted_schema})
    op.create_table('feriados',
    sa.Column('data', sa.Date(), nullable=False),
    sa.Column('descricao', sa.String(length=255), nullable=False),
    sa.Column('setor_id', sa.UUID(), nullable=True),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint('length(trim(descricao)) > 0', name=op.f('ck_feriados_descricao_preenchida')),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_feriados_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['setor_id', 'empresa_id'], ['setores.id', 'setores.empresa_id'], name='fk_feriados_setor_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_feriados')),
    sa.UniqueConstraint('id', 'empresa_id', name='uq_feriados_id_empresa')
    )
    op.create_index('ix_feriados_empresa_data', 'feriados', ['empresa_id', 'data'], unique=False)
    op.create_index(op.f('ix_feriados_empresa_id'), 'feriados', ['empresa_id'], unique=False)
    op.create_index('uq_feriados_empresa_data', 'feriados', ['empresa_id', 'data'], unique=True, postgresql_where=sa.text('setor_id IS NULL'))
    op.create_index('uq_feriados_setor_data', 'feriados', ['empresa_id', 'setor_id', 'data'], unique=True, postgresql_where=sa.text('setor_id IS NOT NULL'))
    op.create_table('turnos',
    sa.Column('escala_id', sa.UUID(), nullable=False),
    sa.Column('ordem', sa.SmallInteger(), server_default=sa.text('0'), nullable=False),
    sa.Column('hora_inicio', sa.Time(), nullable=False),
    sa.Column('hora_fim', sa.Time(), nullable=False),
    sa.Column('tempo_intervalo', sa.Integer(), server_default=sa.text('0'), nullable=False),
    sa.Column('fim_dia_seguinte', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('dias_semana', postgresql.ARRAY(sa.SmallInteger()), server_default=sa.text('ARRAY[1,2,3,4,5]::smallint[]'), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("extract(second FROM hora_inicio) = 0 AND extract(second FROM hora_fim) = 0 AND hora_inicio < TIME '24:00' AND hora_fim < TIME '24:00'", name=op.f('ck_turnos_horas_minutos_validos')),
    sa.CheckConstraint('(hora_inicio <> hora_fim OR fim_dia_seguinte) AND (NOT fim_dia_seguinte OR hora_fim <= hora_inicio)', name=op.f('ck_turnos_virada_valida')),
    sa.CheckConstraint('cardinality(dias_semana) BETWEEN 1 AND 7 AND dias_semana <@ ARRAY[1,2,3,4,5,6,7]::smallint[] AND array_position(dias_semana, NULL) IS NULL AND array_ndims(dias_semana) = 1', name=op.f('ck_turnos_dias_semana_validos')),
    sa.CheckConstraint('ordem >= 0', name=op.f('ck_turnos_ordem_valida')),
    sa.CheckConstraint('tempo_intervalo >= 0 AND tempo_intervalo < (extract(epoch FROM (hora_fim - hora_inicio)) / 60 + CASE WHEN hora_fim < hora_inicio OR fim_dia_seguinte THEN 1440 ELSE 0 END)', name=op.f('ck_turnos_intervalo_valido')),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_turnos_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['escala_id', 'empresa_id'], ['escalas.id', 'escalas.empresa_id'], name='fk_turnos_escala_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_turnos')),
    sa.UniqueConstraint('empresa_id', 'escala_id', 'ordem', name='uq_turnos_escala_ordem'),
    sa.UniqueConstraint('id', 'empresa_id', name='uq_turnos_id_empresa')
    )
    op.create_index(op.f('ix_turnos_empresa_id'), 'turnos', ['empresa_id'], unique=False)
    op.create_table('afastamentos',
    sa.Column('funcionario_id', sa.UUID(), nullable=False),
    sa.Column('tipo', sa.Enum('FERIAS', 'ATESTADO', 'LICENCA', 'OUTROS', name='tipo_afastamento'), nullable=False),
    sa.Column('data_inicio', sa.Date(), nullable=False),
    sa.Column('data_fim', sa.Date(), nullable=False),
    sa.Column('anexo_url', sa.String(length=2048), nullable=True),
    sa.Column('descricao', sa.Text(), nullable=True),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('empresa_id', sa.UUID(), nullable=False),
    sa.Column('criado_em', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    postgresql.ExcludeConstraint((sa.column('empresa_id'), '='), (sa.column('funcionario_id'), '='), (sa.text("daterange(data_inicio, data_fim, '[]')"), '&&'), using='gist', name='ex_afastamentos_periodos_sobrepostos'),
    sa.CheckConstraint('data_fim >= data_inicio', name=op.f('ck_afastamentos_periodo_valido')),
    sa.ForeignKeyConstraint(['empresa_id'], ['empresas.id'], name=op.f('fk_afastamentos_empresa_id_empresas'), onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['funcionario_id', 'empresa_id'], ['funcionarios.id', 'funcionarios.empresa_id'], name='fk_afastamentos_funcionario_empresa', onupdate='RESTRICT', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_afastamentos')),
    sa.UniqueConstraint('id', 'empresa_id', name='uq_afastamentos_id_empresa')
    )
    op.create_index('ix_afastamentos_empresa_funcionario_datas', 'afastamentos', ['empresa_id', 'funcionario_id', 'data_inicio', 'data_fim'], unique=False)
    op.create_index(op.f('ix_afastamentos_empresa_id'), 'afastamentos', ['empresa_id'], unique=False)
    connection.execute(sa.text("SELECT set_config('search_path', :path, true)"), {'path': original_path})
    for table in ('turnos', 'feriados', 'afastamentos'):
        op.execute(f'ALTER TABLE {table} ENABLE ROW LEVEL SECURITY')
    # Preserva aparelhos cadastrados e suas referências nas marcações antigas.
    op.add_column('dispositivos', sa.Column('device_uuid', sa.UUID(), nullable=True))
    op.execute('UPDATE dispositivos SET device_uuid = id')
    op.alter_column('dispositivos', 'device_uuid', existing_type=sa.UUID(), nullable=False)
    op.add_column('dispositivos', sa.Column('tipo', DISPOSITIVO, server_default='PESSOAL', nullable=False))
    op.add_column('dispositivos', sa.Column('setor_id', sa.UUID(), nullable=True))
    op.add_column('dispositivos', sa.Column('ultimo_acesso_em', sa.DateTime(timezone=True), nullable=True))
    op.alter_column('dispositivos', 'usuario_id',
               existing_type=sa.UUID(),
               nullable=True)
    op.create_index('ix_dispositivos_empresa_tipo_ativo', 'dispositivos', ['empresa_id', 'tipo', 'ativo'], unique=False)
    op.create_unique_constraint('uq_dispositivos_device_uuid', 'dispositivos', ['device_uuid'])
    op.create_foreign_key('fk_dispositivos_setor_empresa', 'dispositivos', 'setores', ['setor_id', 'empresa_id'], ['id', 'empresa_id'], onupdate='RESTRICT', ondelete='RESTRICT')
    op.create_check_constraint('vinculo_tipo_valido', 'dispositivos',
        "(tipo = 'PESSOAL' AND usuario_id IS NOT NULL AND setor_id IS NULL) OR "
        "(tipo = 'RELOGIO' AND setor_id IS NOT NULL AND usuario_id IS NULL)")
    op.add_column('escalas', sa.Column('modelo', MODELO, server_default='Legado', nullable=False))
    op.add_column('escalas', sa.Column('data_referencia', sa.Date(), nullable=True))
    op.create_check_constraint('modelo_referencia_valida', 'escalas',
        "modelo = 'Legado' OR "
        "(modelo IN ('24x72', '12x36') AND tipo = 'Ciclica' AND data_referencia IS NOT NULL) OR "
        "(modelo IN ('Diurno', '5x2') AND tipo = 'Semanal')")


def downgrade():
    if op.get_bind().scalar(sa.text('''SELECT EXISTS(SELECT 1 FROM turnos)
        OR EXISTS(SELECT 1 FROM feriados) OR EXISTS(SELECT 1 FROM afastamentos)
        OR EXISTS(SELECT 1 FROM escalas WHERE modelo <> 'Legado' OR data_referencia IS NOT NULL)
        OR EXISTS(SELECT 1 FROM dispositivos WHERE tipo <> 'PESSOAL'
            OR ultimo_acesso_em IS NOT NULL OR device_uuid <> id)''')):
        raise RuntimeError('Downgrade W04/W07 bloqueado: existem dados novos a preservar.')
    op.drop_constraint(op.f('ck_escalas_modelo_referencia_valida'), 'escalas', type_='check')
    op.drop_constraint(op.f('ck_dispositivos_vinculo_tipo_valido'), 'dispositivos', type_='check')
    op.drop_column('escalas', 'data_referencia')
    op.drop_column('escalas', 'modelo')
    op.drop_constraint('fk_dispositivos_setor_empresa', 'dispositivos', type_='foreignkey')
    op.drop_constraint('uq_dispositivos_device_uuid', 'dispositivos', type_='unique')
    op.drop_index('ix_dispositivos_empresa_tipo_ativo', table_name='dispositivos')
    op.alter_column('dispositivos', 'usuario_id',
               existing_type=sa.UUID(),
               nullable=False)
    op.drop_column('dispositivos', 'ultimo_acesso_em')
    op.drop_column('dispositivos', 'setor_id')
    op.drop_column('dispositivos', 'tipo')
    op.drop_column('dispositivos', 'device_uuid')
    op.drop_index(op.f('ix_afastamentos_empresa_id'), table_name='afastamentos')
    op.drop_index('ix_afastamentos_empresa_funcionario_datas', table_name='afastamentos')
    op.drop_table('afastamentos')
    op.drop_index(op.f('ix_turnos_empresa_id'), table_name='turnos')
    op.drop_table('turnos')
    op.drop_index('uq_feriados_setor_data', table_name='feriados', postgresql_where=sa.text('setor_id IS NOT NULL'))
    op.drop_index('uq_feriados_empresa_data', table_name='feriados', postgresql_where=sa.text('setor_id IS NULL'))
    op.drop_index(op.f('ix_feriados_empresa_id'), table_name='feriados')
    op.drop_index('ix_feriados_empresa_data', table_name='feriados')
    op.drop_table('feriados')
    MODELO.drop(op.get_bind())
    DISPOSITIVO.drop(op.get_bind())
    postgresql.ENUM(name='tipo_afastamento').drop(op.get_bind())
