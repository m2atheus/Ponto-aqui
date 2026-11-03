"""Aprovação, projeção de ajustes e excedente diário sem mutar batidas."""
import uuid
from datetime import datetime, timedelta, timezone, time

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import event, select
from sqlalchemy.exc import IntegrityError

from app.models import JustificativasAjustes, PapelUsuario, RegistrosPonto, Turnos, Usuarios
from app.services.ajuste_ponto_service import AjustePontoService
from test_ajustes_rh import contexto, headers, snapshot
from test_w06_services import contexto as contexto_espelho, dia, espelho, ponto


def path(registro):
    return f"/api/v1/admin/pontos/{registro}/aprovar"


@pytest.mark.parametrize("modo", ["ausente", "vencido", "invalido"])
def test_aprovacao_exige_jwt(app, modo):
    h = {}
    if modo != "ausente":
        with app.app_context():
            token = create_access_token(identity=str(uuid.uuid4()), expires_delta=timedelta(seconds=-1))
        h["Authorization"] = "Bearer " + (token if modo == "vencido" else "invalido")
    assert app.test_client().post(path(uuid.uuid4()), headers=h, json={"motivo_texto": "Teste"}).status_code == 401


@pytest.mark.postgres
@pytest.mark.parametrize("papel", [PapelUsuario.RH, PapelUsuario.GESTOR])
@pytest.mark.parametrize("situacao", ["Recusada", "PendenteAnalise"])
def test_aprovacao_auditada_e_unica_sem_alterar_original(contexto, session, point_values, papel, situacao):
    ctx = contexto
    ctx.rh.papel = papel
    registro = RegistrosPonto(**{**point_values, "evento_cliente_id": uuid.uuid4(), "tipo": "Saida", "situacao": situacao,
        "motivos": ["FORA_DO_PERIMETRO"],
        "ocorrido_em": ctx.original.ocorrido_em + timedelta(hours=10)})
    session.add(registro)
    session.commit()
    antes = snapshot(session)
    writes = []
    def capturar(conn, cursor, statement, parameters, context, many):
        if statement.lstrip().upper().startswith(("INSERT", "UPDATE", "DELETE")):
            writes.append(statement)
    connection = session.connection()
    event.listen(connection, "before_cursor_execute", capturar)
    try:
        response = ctx.client.post(path(registro.id), headers=headers(ctx.rh), json={"motivo_texto": "  Horário conferido com o funcionário  "})
    finally:
        event.remove(connection, "before_cursor_execute", capturar)
    assert response.status_code == 201, response.json
    ajuste = response.json["ajuste"]
    assert ajuste["tipo_ocorrencia"] == "APROVACAO_GESTOR"
    assert ajuste["status_analise"] == "APROVADO" and ajuste["gestor_aprovador_id"] == str(ctx.rh.id)
    assert ajuste["registro_original_id"] == str(registro.id)
    assert ajuste["motivo_texto"] == "Horário conferido com o funcionário"
    assert writes and all("INSERT INTO justificativas_ajustes" in w for w in writes)
    assert snapshot(session) == antes
    duplicate = ctx.client.post(path(registro.id), headers=headers(ctx.rh), json={"motivo_texto": "Outra tentativa"})
    assert duplicate.status_code == 409 and duplicate.json["erro"]["codigo"] == "PONTO_JA_APROVADO"
    salvo = session.scalar(select(JustificativasAjustes))
    with pytest.raises(IntegrityError), session.begin_nested():
        session.add(JustificativasAjustes(empresa_id=salvo.empresa_id, usuario_id=salvo.usuario_id,
            registro_ponto_id=salvo.registro_ponto_id, solicitado_por_id=salvo.solicitado_por_id,
            justificativa="Duplicada", tipo_ocorrencia="APROVACAO_GESTOR", tipo_proposto=salvo.tipo_proposto,
            ocorrido_em_proposto=salvo.ocorrido_em_proposto, status=salvo.status,
            decidido_por_id=salvo.decidido_por_id, decidido_em=salvo.decidido_em,
            sequencia_decisao=salvo.sequencia_decisao))
        session.flush()


@pytest.mark.postgres
@pytest.mark.parametrize("dados", [None, {}, [], {"motivo_texto": " "}, {"motivo_texto": 1},
    {"motivo_texto": "a" * 5001}, {"motivo_texto": "Teste", "empresa_id": "forjada"}])
def test_aprovacao_valida_motivo_e_nao_aceita_injecao(contexto, session, dados):
    assert contexto.client.post(path(contexto.original.id), headers=headers(contexto.rh), json=dados).status_code == 400
    assert session.scalars(select(JustificativasAjustes)).all() == []


@pytest.mark.postgres
def test_aprovacao_respeita_empresa_status_e_papel_atual(contexto, session):
    ctx = contexto
    for alvo in [ctx.other_point.id, uuid.uuid4()]:
        assert ctx.client.post(path(alvo), headers=headers(ctx.rh), json={"motivo_texto": "Teste"}).status_code == 404
    assert ctx.client.post(path(ctx.original.id), headers=headers(ctx.rh), json={"motivo_texto": "Teste"}).json["erro"]["codigo"] == "PONTO_JA_ACEITO"
    ctx.rh.papel = PapelUsuario.FUNCIONARIO
    session.commit()
    assert ctx.client.post(path(ctx.original.id), headers=headers(ctx.rh, role="RH"), json={"motivo_texto": "Teste"}).status_code == 403


def jornada(ctx, session, point_values, *, saida_situacao="Recusada", sem_entrada=False):
    rows = []
    for tipo, hora in [("Entrada", "08:00"), ("InicioIntervalo", "12:00"), ("FimIntervalo", "13:00"), ("Saida", "19:00")]:
        if sem_entrada and tipo == "Entrada":
            continue
        rows.append(ponto(session, ctx.own, point_values, tipo, f"2026-10-01T{hora}:00-03:00",
            situacao=saida_situacao if tipo == "Saida" else "Aceita",
            motivos=["FORA_DO_PERIMETRO"] if tipo == "Saida" and saida_situacao != "Aceita" else []))
    session.commit()
    return rows


@pytest.mark.postgres
def test_aprovacao_recalcula_horas_extras_e_invalidacao_prevalece(contexto_espelho, session, point_values):
    ctx = contexto_espelho
    ctx.rh.papel = PapelUsuario.GESTOR
    rows = jornada(ctx, session, point_values)
    antes = snapshot(session)
    assert dia(espelho(ctx, session), "2026-10-01")["minutos_extras"] == 0
    payload, status = AjustePontoService.aprovar_marcacao(ctx.rh.id, ctx.own.company.id, rows[-1].id,
        {"motivo_texto": "Saída conferida; jornada estendida"}, session=session)
    assert status == 201, payload
    result = espelho(ctx, session)
    row = dia(result, "2026-10-01")
    assert row["minutos_trabalhados"] == 600 and row["minutos_previstos"] == 480
    assert row["minutos_extras"] == result["totais"]["minutos_extras"] == 120
    assert row["pendencias"] == []
    saida = next(p for p in row["marcacoes"] if p["id"] == str(rows[-1].id))
    assert saida["situacao"] == "Recusada" and saida["aprovado_gestor"] is True
    assert AjustePontoService.invalidar_marcacao(ctx.rh.id, ctx.own.company.id, rows[-1].id,
        {"motivo_texto": "Constatada inconsistência"}, session=session)[1] == 201
    assert dia(espelho(ctx, session), "2026-10-01")["minutos_extras"] == 0
    assert AjustePontoService.aprovar_marcacao(ctx.rh.id, ctx.own.company.id, rows[-1].id,
        {"motivo_texto": "Não pode restaurar"}, session=session)[1] == 409
    assert snapshot(session) == antes


@pytest.mark.postgres
def test_aprovar_saida_isolada_nao_inventa_horas(contexto_espelho, session, point_values):
    ctx = contexto_espelho
    saida = ponto(session, ctx.own, point_values, "Saida", "2026-10-01T19:00:00-03:00", situacao="Recusada", motivos=["FORA_DO_PERIMETRO"])
    session.commit()
    assert AjustePontoService.aprovar_marcacao(ctx.rh.id, ctx.own.company.id, saida.id,
        {"motivo_texto": "Horário confirmado"}, session=session)[1] == 201
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["minutos_trabalhados"] == row["minutos_extras"] == 0
    assert "SEQUENCIA_INCOMPLETA_OU_INVALIDA" in row["pendencias"]


@pytest.mark.postgres
def test_inclusao_manual_e_correcao_aprovadas_completam_e_retificam_jornada(contexto_espelho, session, point_values):
    ctx = contexto_espelho
    rows = jornada(ctx, session, point_values, saida_situacao="Aceita", sem_entrada=True)
    antes = snapshot(session)
    assert AjustePontoService.inserir_ponto_manual_rh(ctx.rh.id, ctx.own.company.id,
        {"usuario_id": str(ctx.own.user.id), "tipo": "ENTRADA", "nova_data_hora": "2026-10-01T08:00:00-03:00",
            "motivo_texto": "Esqueceu a entrada"}, session=session)[1] == 201
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["minutos_trabalhados"] == 600 and row["minutos_extras"] == 120
    assert any(p["origem"] == "MANUAL_RH" for p in row["marcacoes"])
    assert AjustePontoService.corrigir_ponto_existente_rh(ctx.rh.id, ctx.own.company.id,
        {"registro_original_id": str(rows[-1].id), "nova_data_hora": "2026-10-01T17:00:00-03:00",
            "motivo_texto": "A saída correta foi às 17h"}, session=session)[1] == 201
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["minutos_trabalhados"] == 480 and row["minutos_extras"] == 0
    assert row["pendencias"] == [] and snapshot(session) == antes


@pytest.mark.postgres
def test_extras_na_virada_do_mes(contexto_espelho, session, point_values):
    ctx = contexto_espelho
    shift = session.scalar(select(Turnos).where(Turnos.escala_id == ctx.own.schedule.id))
    ctx.own.schedule.modelo = "Diurno"
    shift.hora_inicio, shift.hora_fim, shift.tempo_intervalo, shift.dias_semana = time(19), time(7), 0, [3]
    ponto(session, ctx.own, point_values, "Entrada", "2026-09-30T19:00:00-03:00")
    saida = ponto(session, ctx.own, point_values, "Saida", "2026-10-01T09:00:00-03:00", situacao="PendenteAnalise", motivos=["FORA_DO_PERIMETRO"])
    session.commit()
    assert AjustePontoService.aprovar_marcacao(ctx.rh.id, ctx.own.company.id, saida.id,
        {"motivo_texto": "Plantão estendido"}, session=session)[1] == 201
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["minutos_trabalhados"] == 540 and row["minutos_previstos"] == 420
    assert row["minutos_extras"] == 120


@pytest.mark.postgres
def test_horas_trabalhadas_em_feriado_nao_geram_falta_e_excedente_fica_separado(contexto_espelho, session, point_values):
    from app.services.feriado_service import FeriadoService
    ctx = contexto_espelho
    jornada(ctx, session, point_values, saida_situacao="Aceita")
    assert FeriadoService.criar(ctx.rh.id, ctx.own.company.id,
        {"data": "2026-10-01", "descricao": "Feriado"}, session=session)[1] == 201
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["minutos_exigiveis"] == row["minutos_faltas"] == 0
    assert row["minutos_abonados"] == 480 and row["minutos_extras"] == 600


@pytest.mark.postgres
def test_correcao_entre_meses_nao_duplica_original_e_invalidacao_prevalece(contexto_espelho, session, point_values):
    ctx = contexto_espelho
    for tipo, hora in [("Entrada", "08:00"), ("InicioIntervalo", "12:00"), ("FimIntervalo", "13:00")]:
        ponto(session, ctx.own, point_values, tipo, f"2026-10-01T{hora}:00-03:00")
    errado = ponto(session, ctx.own, point_values, "Saida", "2026-08-01T17:00:00-03:00")
    session.commit()
    assert AjustePontoService.corrigir_ponto_existente_rh(ctx.rh.id, ctx.own.company.id,
        {"registro_original_id": str(errado.id), "nova_data_hora": "2026-10-01T17:00:00-03:00",
            "motivo_texto": "Data digitada incorretamente"}, session=session)[1] == 201
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["minutos_trabalhados"] == 480 and row["minutos_extras"] == 0
    assert len(row["marcacoes"]) == 4
    assert AjustePontoService.invalidar_marcacao(ctx.rh.id, ctx.own.company.id, errado.id,
        {"motivo_texto": "Correção indevida"}, session=session)[1] == 201
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["minutos_trabalhados"] == 240 and row["minutos_extras"] == 0


@pytest.mark.postgres
def test_ajuste_pendente_nao_aprova_batida_nem_gera_extras(contexto_espelho, session, point_values):
    ctx = contexto_espelho
    rows = jornada(ctx, session, point_values)
    session.add(JustificativasAjustes(empresa_id=ctx.own.company.id, usuario_id=ctx.own.user.id,
        registro_ponto_id=rows[-1].id, solicitado_por_id=ctx.own.user.id,
        justificativa="Aguardando análise", tipo_proposto="Saida", ocorrido_em_proposto=rows[-1].ocorrido_em))
    session.commit()
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["minutos_extras"] == 0 and "AJUSTE_W10_REQUER_APURACAO" in row["pendencias"]


@pytest.mark.postgres
def test_futuro_nao_gera_horas_extras(contexto_espelho, session, point_values, monkeypatch):
    ctx = contexto_espelho
    jornada(ctx, session, point_values, saida_situacao="Aceita")
    monkeypatch.setattr("app.services.espelho_service._agora_utc", lambda: datetime(2026, 9, 30, tzinfo=timezone.utc))
    row = dia(espelho(ctx, session), "2026-10-01")
    assert row["minutos_trabalhados"] == row["minutos_extras"] == 0
    assert "MARCACAO_FUTURA" in row["pendencias"]
