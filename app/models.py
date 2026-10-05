"""Modelos de persistência; regras de negócio pertencem aos Services."""

import enum
import uuid

from sqlalchemy import (
    CheckConstraint, DDL, ForeignKeyConstraint, Index, UniqueConstraint, event,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import object_session

from . import db


class PapelUsuario(str, enum.Enum):
    SUPERADMIN = "Superadmin"
    RH = "RH"
    GESTOR = "Gestor"
    FUNCIONARIO = "Funcionario"
    RELOGIO = "Relogio"


class TipoEscala(str, enum.Enum):
    SEMANAL = "Semanal"
    CICLICA = "Ciclica"


class TipoPonto(str, enum.Enum):
    ENTRADA = "Entrada"
    INICIO_INTERVALO = "InicioIntervalo"
    FIM_INTERVALO = "FimIntervalo"
    SAIDA = "Saida"


class OrigemPonto(str, enum.Enum):
    MOBILE = "Mobile"
    WEB = "Web"
    RELOGIO = "Relogio"


class StatusAjuste(str, enum.Enum):
    PENDENTE = "Pendente"
    APROVADO = "Aprovado"
    REJEITADO = "Rejeitado"


def enum_column_type(enum_class, name):
    return db.Enum(
        enum_class, name=name, native_enum=True, validate_strings=True,
        values_callable=lambda members: [member.value for member in members],
    )


class IdentificadorMixin:
    id = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)


class EmpresaMixin:
    empresa_id = db.Column(
        UUID(as_uuid=True),
        db.ForeignKey("empresas.id", ondelete="RESTRICT", onupdate="RESTRICT"),
        nullable=False, index=True,
    )


class CriacaoMixin:
    criado_em = db.Column(
        db.DateTime(timezone=True), nullable=False, server_default=db.func.now(),
    )


class Empresas(IdentificadorMixin, CriacaoMixin, db.Model):
    __tablename__ = "empresas"

    razao_social = db.Column(db.String(200), nullable=False)
    nome_fantasia = db.Column(db.String(200))
    cnpj = db.Column(db.String(14), nullable=False, unique=True)
    fuso_horario = db.Column(
        db.String(64), nullable=False, default="America/Sao_Paulo",
        server_default="America/Sao_Paulo",
    )
    ativo = db.Column(db.Boolean, nullable=False, default=True, server_default=db.true())

    __table_args__ = (
        CheckConstraint("cnpj ~ '^[0-9]{14}$'", name="cnpj_formato"),
    )


class Usuarios(IdentificadorMixin, EmpresaMixin, CriacaoMixin, db.Model):
    __tablename__ = "usuarios"

    nome = db.Column(db.String(150), nullable=False)
    email = db.Column(db.String(254), nullable=False)
    senha_hash = db.Column(db.Text, nullable=False)
    papel = db.Column(
        enum_column_type(PapelUsuario, "papel_usuario"), nullable=False,
        default=PapelUsuario.FUNCIONARIO,
        server_default=PapelUsuario.FUNCIONARIO.value,
    )
    matricula = db.Column(db.String(50))
    ativo = db.Column(db.Boolean, nullable=False, default=True, server_default=db.true())

    # Relacionamentos somente para leitura. Services persistem os IDs.
    empresa = db.relationship("Empresas", viewonly=True)

    __table_args__ = (
        UniqueConstraint("id", "empresa_id", name="uq_usuarios_id_empresa"),
        UniqueConstraint("empresa_id", "email", name="uq_usuarios_empresa_email"),
        UniqueConstraint("empresa_id", "matricula", name="uq_usuarios_empresa_matricula"),
        CheckConstraint("email = lower(email)", name="email_minusculo"),
    )


class Setores(IdentificadorMixin, EmpresaMixin, CriacaoMixin, db.Model):
    __tablename__ = "setores"

    nome = db.Column(db.String(120), nullable=False)
    latitude_centro = db.Column(db.Numeric(10, 7), nullable=False)
    longitude_centro = db.Column(db.Numeric(10, 7), nullable=False)
    raio_metros = db.Column(db.Numeric(12, 2), nullable=False)
    ativo = db.Column(db.Boolean, nullable=False, default=True, server_default=db.true())

    __table_args__ = (
        UniqueConstraint("id", "empresa_id", name="uq_setores_id_empresa"),
        UniqueConstraint("empresa_id", "nome", name="uq_setores_empresa_nome"),
        CheckConstraint("latitude_centro BETWEEN -90 AND 90", name="latitude_centro_valida"),
        CheckConstraint("longitude_centro BETWEEN -180 AND 180", name="longitude_centro_valida"),
        CheckConstraint("raio_metros > 0", name="raio_positivo"),
    )


class Escalas(IdentificadorMixin, EmpresaMixin, CriacaoMixin, db.Model):
    __tablename__ = "escalas"

    nome = db.Column(db.String(120), nullable=False)
    tipo = db.Column(enum_column_type(TipoEscala, "tipo_escala"), nullable=False)
    carga_semanal_minutos = db.Column(db.Integer, nullable=False)
    tolerancia_minutos = db.Column(
        db.Integer, nullable=False, default=0, server_default=db.text("0"),
    )
    # Formato validado pelo Service. Alterações exigem atribuir novo objeto.
    regras = db.Column(JSONB, nullable=False)
    ativo = db.Column(db.Boolean, nullable=False, default=True, server_default=db.true())

    __table_args__ = (
        UniqueConstraint("id", "empresa_id", name="uq_escalas_id_empresa"),
        UniqueConstraint("empresa_id", "nome", name="uq_escalas_empresa_nome"),
        CheckConstraint("carga_semanal_minutos BETWEEN 0 AND 10080", name="carga_semanal_valida"),
        CheckConstraint("tolerancia_minutos >= 0", name="tolerancia_valida"),
        CheckConstraint("jsonb_typeof(regras) = 'object'", name="regras_objeto"),
    )


class Alocacoes(IdentificadorMixin, EmpresaMixin, CriacaoMixin, db.Model):
    __tablename__ = "alocacoes"

    usuario_id = db.Column(UUID(as_uuid=True), nullable=False)
    setor_id = db.Column(UUID(as_uuid=True), nullable=False)
    escala_id = db.Column(UUID(as_uuid=True), nullable=False)
    data_inicio = db.Column(db.Date, nullable=False)
    data_fim = db.Column(db.Date)

    usuario = db.relationship("Usuarios", viewonly=True)
    setor = db.relationship("Setores", viewonly=True)
    escala = db.relationship("Escalas", viewonly=True)

    __table_args__ = (
        UniqueConstraint("id", "empresa_id", name="uq_alocacoes_id_empresa"),
        UniqueConstraint(
            "id", "usuario_id", "setor_id", "empresa_id",
            name="uq_alocacoes_identidade",
        ),
        ForeignKeyConstraint(
            ["usuario_id", "empresa_id"], ["usuarios.id", "usuarios.empresa_id"],
            name="fk_alocacoes_usuario_empresa", ondelete="RESTRICT", onupdate="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["setor_id", "empresa_id"], ["setores.id", "setores.empresa_id"],
            name="fk_alocacoes_setor_empresa", ondelete="RESTRICT", onupdate="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["escala_id", "empresa_id"], ["escalas.id", "escalas.empresa_id"],
            name="fk_alocacoes_escala_empresa", ondelete="RESTRICT", onupdate="RESTRICT",
        ),
        CheckConstraint("data_fim IS NULL OR data_fim >= data_inicio", name="vigencia_valida"),
        Index("ix_alocacoes_empresa_usuario_inicio", "empresa_id", "usuario_id", "data_inicio"),
    )


class RegistrosPonto(IdentificadorMixin, EmpresaMixin, db.Model):
    __tablename__ = "registros_ponto"

    usuario_id = db.Column(UUID(as_uuid=True), nullable=False)
    setor_id = db.Column(UUID(as_uuid=True), nullable=False)
    alocacao_id = db.Column(UUID(as_uuid=True), nullable=False)
    enviado_por_id = db.Column(UUID(as_uuid=True), nullable=False)
    # Gerado no dispositivo e mantido em todas as retransmissões.
    evento_cliente_id = db.Column(UUID(as_uuid=True), nullable=False)
    # SHA-256 calculado pelo Service sobre o conteúdo canônico original.
    payload_hash = db.Column(db.String(64), nullable=False)
    tipo = db.Column(enum_column_type(TipoPonto, "tipo_ponto"), nullable=False)
    origem = db.Column(enum_column_type(OrigemPonto, "origem_ponto"), nullable=False)
    ocorrido_em = db.Column(db.DateTime(timezone=True), nullable=False)
    recebido_em = db.Column(
        db.DateTime(timezone=True), nullable=False,
        server_default=db.func.clock_timestamp(),
    )
    offset_original_minutos = db.Column(db.SmallInteger, nullable=False)
    latitude = db.Column(db.Numeric(10, 7), nullable=False)
    longitude = db.Column(db.Numeric(10, 7), nullable=False)
    precisao_metros = db.Column(db.Numeric(12, 2))
    # Evidência imutável do perímetro utilizado na validação.
    latitude_centro_validada = db.Column(db.Numeric(10, 7), nullable=False)
    longitude_centro_validada = db.Column(db.Numeric(10, 7), nullable=False)
    raio_validado_metros = db.Column(db.Numeric(12, 2), nullable=False)
    distancia_centro_metros = db.Column(db.Numeric(12, 2), nullable=False)

    alocacao = db.relationship("Alocacoes", viewonly=True)
    enviado_por = db.relationship("Usuarios", viewonly=True)

    __table_args__ = (
        UniqueConstraint("id", "empresa_id", "usuario_id", name="uq_registros_identidade"),
        UniqueConstraint(
            "empresa_id", "usuario_id", "evento_cliente_id", name="uq_registros_evento_cliente",
        ),
        ForeignKeyConstraint(
            ["alocacao_id", "usuario_id", "setor_id", "empresa_id"],
            ["alocacoes.id", "alocacoes.usuario_id", "alocacoes.setor_id", "alocacoes.empresa_id"],
            name="fk_registros_alocacao_identidade", ondelete="RESTRICT", onupdate="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["enviado_por_id", "empresa_id"], ["usuarios.id", "usuarios.empresa_id"],
            name="fk_registros_remetente_empresa", ondelete="RESTRICT", onupdate="RESTRICT",
        ),
        CheckConstraint("payload_hash ~ '^[0-9a-f]{64}$'", name="payload_hash_formato"),
        CheckConstraint("offset_original_minutos BETWEEN -840 AND 840", name="offset_original_valido"),
        CheckConstraint("latitude BETWEEN -90 AND 90", name="latitude_valida"),
        CheckConstraint("longitude BETWEEN -180 AND 180", name="longitude_valida"),
        CheckConstraint("precisao_metros IS NULL OR precisao_metros >= 0", name="precisao_valida"),
        CheckConstraint("latitude_centro_validada BETWEEN -90 AND 90", name="latitude_centro_validada"),
        CheckConstraint("longitude_centro_validada BETWEEN -180 AND 180", name="longitude_centro_validada"),
        CheckConstraint("raio_validado_metros > 0", name="raio_validado_positivo"),
        CheckConstraint(
            "distancia_centro_metros >= 0 AND distancia_centro_metros <= raio_validado_metros",
            name="distancia_dentro_perimetro",
        ),
        Index("ix_registros_empresa_usuario_ocorrido", "empresa_id", "usuario_id", "ocorrido_em"),
    )


class JustificativasAjustes(IdentificadorMixin, EmpresaMixin, CriacaoMixin, db.Model):
    __tablename__ = "justificativas_ajustes"

    usuario_id = db.Column(UUID(as_uuid=True), nullable=False)
    # NULL significa inclusão de batida esquecida; preenchido, retificação.
    registro_ponto_id = db.Column(UUID(as_uuid=True))
    solicitado_por_id = db.Column(UUID(as_uuid=True), nullable=False)
    justificativa = db.Column(db.Text, nullable=False)
    tipo_proposto = db.Column(enum_column_type(TipoPonto, "tipo_ponto"), nullable=False)
    ocorrido_em_proposto = db.Column(db.DateTime(timezone=True), nullable=False)
    status = db.Column(
        enum_column_type(StatusAjuste, "status_ajuste"), nullable=False,
        default=StatusAjuste.PENDENTE, server_default=StatusAjuste.PENDENTE.value,
    )
    decidido_por_id = db.Column(UUID(as_uuid=True))
    decidido_em = db.Column(db.DateTime(timezone=True))
    observacao_decisao = db.Column(db.Text)

    registro_ponto = db.relationship("RegistrosPonto", viewonly=True)
    usuario = db.relationship(
        "Usuarios", viewonly=True,
        foreign_keys=lambda: [JustificativasAjustes.usuario_id, JustificativasAjustes.empresa_id],
    )
    solicitado_por = db.relationship(
        "Usuarios", viewonly=True,
        foreign_keys=lambda: [JustificativasAjustes.solicitado_por_id, JustificativasAjustes.empresa_id],
    )
    decidido_por = db.relationship(
        "Usuarios", viewonly=True,
        foreign_keys=lambda: [JustificativasAjustes.decidido_por_id, JustificativasAjustes.empresa_id],
    )

    __table_args__ = (
        UniqueConstraint("id", "empresa_id", name="uq_ajustes_id_empresa"),
        ForeignKeyConstraint(
            ["usuario_id", "empresa_id"], ["usuarios.id", "usuarios.empresa_id"],
            name="fk_ajustes_usuario_empresa", ondelete="RESTRICT", onupdate="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["registro_ponto_id", "empresa_id", "usuario_id"],
            ["registros_ponto.id", "registros_ponto.empresa_id", "registros_ponto.usuario_id"],
            name="fk_ajustes_registro_identidade", ondelete="RESTRICT", onupdate="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["solicitado_por_id", "empresa_id"], ["usuarios.id", "usuarios.empresa_id"],
            name="fk_ajustes_solicitante_empresa", ondelete="RESTRICT", onupdate="RESTRICT",
        ),
        ForeignKeyConstraint(
            ["decidido_por_id", "empresa_id"], ["usuarios.id", "usuarios.empresa_id"],
            name="fk_ajustes_decisor_empresa", ondelete="RESTRICT", onupdate="RESTRICT",
        ),
        CheckConstraint("length(trim(justificativa)) > 0", name="justificativa_obrigatoria"),
        CheckConstraint(
            "(status = 'Pendente' AND decidido_por_id IS NULL AND decidido_em IS NULL) "
            "OR (status IN ('Aprovado', 'Rejeitado') "
            "AND decidido_por_id IS NOT NULL AND decidido_em IS NOT NULL)",
            name="decisao_consistente",
        ),
        Index("ix_ajustes_empresa_status_criado", "empresa_id", "status", "criado_em"),
        Index("ix_ajustes_empresa_usuario", "empresa_id", "usuario_id"),
    )


@event.listens_for(RegistrosPonto, "before_update")
def impedir_update_ponto(mapper, connection, target):
    session = object_session(target)
    if session is not None and session.is_modified(target, include_collections=False):
        raise RuntimeError("Registros de ponto são imutáveis; utilize JustificativasAjustes.")


@event.listens_for(RegistrosPonto, "before_delete")
def impedir_delete_ponto(mapper, connection, target):
    raise RuntimeError("Registros de ponto não podem ser excluídos.")


# A migration inicial contém uma cópia literal destes comandos. Eventos de
# metadata não são usados por Alembic para criar a proteção em produção.
PONTO_IMUTAVEL_DDL = (
    """
    CREATE OR REPLACE FUNCTION impedir_mutacao_registro_ponto()
    RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
        RAISE EXCEPTION
            'Registros de ponto sao imutaveis; utilize justificativas_ajustes';
    END;
    $$;
    """,
    """
    CREATE TRIGGER trg_registros_ponto_imutaveis
    BEFORE UPDATE OR DELETE ON registros_ponto
    FOR EACH ROW EXECUTE FUNCTION impedir_mutacao_registro_ponto();
    """,
    """
    CREATE TRIGGER trg_registros_ponto_sem_truncate
    BEFORE TRUNCATE ON registros_ponto
    FOR EACH STATEMENT EXECUTE FUNCTION impedir_mutacao_registro_ponto();
    """,
)

for statement in PONTO_IMUTAVEL_DDL:
    event.listen(
        RegistrosPonto.__table__, "after_create",
        DDL(statement).execute_if(dialect="postgresql"),
    )
