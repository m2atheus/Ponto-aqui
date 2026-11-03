"""Troca atômica de vínculos W03, via RH/Gestor, em PostgreSQL isolado."""
from datetime import date, time
from types import SimpleNamespace
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest
from flask_jwt_extended import create_access_token
from sqlalchemy import func, select

from app import db
from app.models import Alocacoes, Empresas, Escalas, Funcionarios, PapelUsuario, RegistrosPonto, Setores, Turnos, Usuarios
from app.services.alocacao_service import AlocacaoService

pytestmark = pytest.mark.postgres


@pytest.fixture
def mudanca(session, tenants, monkeypatch):
    own, foreign = tenants
    actors = [Usuarios(empresa_id=own.company.id, nome=papel.name, papel=papel,
        email=f"{papel.name.lower()}@mudanca.example", senha_hash="hash") for papel in (PapelUsuario.RH, PapelUsuario.GESTOR)]
    novo_setor = Setores(empresa_id=own.company.id, nome="Novo setor", latitude_centro=-8,
        longitude_centro=-35, raio_metros=100)
    nova_escala = Escalas(empresa_id=own.company.id, nome="Nova escala", modelo="5x2", tipo="Semanal",
        carga_semanal_minutos=2400, regras={"versao": 1, "dias": []})
    own.schedule.modelo = "5x2"
    session.add_all([*actors, novo_setor, nova_escala])
    session.flush()
    for escala in (own.schedule, nova_escala):
        session.add(Turnos(empresa_id=own.company.id, escala_id=escala.id,
            hora_inicio=time(8), hora_fim=time(17), tempo_intervalo=60))
    session.commit()
    monkeypatch.setattr(AlocacaoService, "_hoje", staticmethod(lambda s, e: date(2026, 11, 3)))
    return SimpleNamespace(own=own, foreign=foreign, rh=actors[0], gestor=actors[1],
        setor=novo_setor, escala=nova_escala)


def trocar(ctx, session, actor=None, **changes):
    args = dict(usuario_id=(actor or ctx.rh).id, empresa_id=ctx.own.company.id,
        funcionario_id=ctx.own.employee.id, nova_escala_id=ctx.escala.id,
        novo_setor_id=ctx.setor.id, data_transicao="2026-11-04",
        alocacao_id=ctx.own.assignment.id, session=session)
    return AlocacaoService.mudar_alocacao(**{**args, **changes})


@pytest.mark.parametrize("papel", ["rh", "gestor"])
@pytest.mark.parametrize("fim", [None, date(2026, 12, 31)])
def test_troca_preserva_historico_e_pontos(session, mudanca, point_values, papel, fim):
    ctx = mudanca
    old = ctx.own.assignment
    old.data_fim = fim
    ponto = RegistrosPonto(**point_values)
    session.add(ponto)
    session.commit()
    snapshot = (ponto.id, ponto.alocacao_id, ponto.ocorrido_em, ponto.situacao)
    original = AlocacaoService._json(old)
    payload, status = trocar(ctx, session, getattr(ctx, papel))
    assert status == 201, payload
    assert payload["alocacao_anterior"] == {**original, "data_fim": "2026-11-03"}
    nova = payload["alocacao"]
    assert nova["id"] != original["id"] and nova["data_inicio"] == "2026-11-04"
    assert nova["data_fim"] is None and nova["setor_id"] == str(ctx.setor.id)
    assert nova["escala_id"] == str(ctx.escala.id)
    assert nova["funcionario_id"] == str(ctx.own.employee.id)
    session.expire_all()
    assert (ponto.id, ponto.alocacao_id, ponto.ocorrido_em, ponto.situacao) == snapshot
    assert session.scalar(select(func.count()).select_from(Alocacoes)) == 3
    # Repetição sobre o vínculo antigo não encerra/cria registros adicionais.
    assert trocar(ctx, session)[1] == 409
    assert session.scalar(select(func.count()).select_from(Alocacoes)) == 3


@pytest.mark.parametrize("changes,status", [
    ({"data_transicao": "2020-01-01"}, 400),
    ({"data_transicao": "2026-02-30"}, 400),
    ({"data_transicao": None}, 400),
    ({"novo_setor_id": "invalido"}, 400),
    ({"alocacao_id": str(uuid.uuid4())}, 409),
])
def test_validacoes_nao_encerram_origem(session, mudanca, changes, status):
    assert trocar(mudanca, session, **changes)[1] == status
    assert session.get(Alocacoes, mudanca.own.assignment.id).data_fim is None
    assert session.scalar(select(func.count()).select_from(Alocacoes)) == 2


@pytest.mark.parametrize("field", ["funcionario_id", "novo_setor_id", "nova_escala_id", "empresa_id"])
def test_multi_tenant(session, mudanca, field):
    foreign = mudanca.foreign
    values = dict(funcionario_id=foreign.employee.id, novo_setor_id=foreign.sector.id,
        nova_escala_id=foreign.schedule.id, empresa_id=foreign.company.id)
    payload, status = trocar(mudanca, session, **{field: values[field]})
    assert status in (401, 403, 404, 409), payload
    assert session.get(Alocacoes, mudanca.own.assignment.id).data_fim is None


def test_funcionario_nao_pode_trocar(session, mudanca):
    assert trocar(mudanca, session, actor=mudanca.own.user)[1] == 403


def test_ambiguidade_exige_origem_e_rollback_conflito(session, mudanca):
    ctx = mudanca
    outra = Alocacoes(empresa_id=ctx.own.company.id, funcionario_id=ctx.own.employee.id,
        usuario_id=ctx.own.user.id, setor_id=ctx.setor.id, escala_id=ctx.escala.id,
        data_inicio=date(2026, 11, 1))
    session.add(outra)
    session.commit()
    payload, status = trocar(ctx, session, alocacao_id=None)
    assert status == 409 and payload["erro"]["codigo"] == "ALOCACAO_AMBIGUA"
    payload, status = trocar(ctx, session)
    assert status == 409 and payload["erro"]["codigo"] == "ALOCACAO_SOBREPOSTA"
    assert session.get(Alocacoes, ctx.own.assignment.id).data_fim is None


@pytest.mark.parametrize("hora", [6, 7])
def test_virada_noturna_e_limite_contiguo(session, mudanca, hora):
    ctx = mudanca
    oldturn = session.scalar(select(Turnos).where(Turnos.escala_id == ctx.own.schedule.id))
    newturn = session.scalar(select(Turnos).where(Turnos.escala_id == ctx.escala.id))
    ctx.own.schedule.modelo = "Diurno"
    ctx.escala.modelo = "Diurno"
    oldturn.hora_inicio, oldturn.hora_fim = time(19), time(7)
    oldturn.tempo_intervalo, oldturn.dias_semana = 0, [1, 2, 3, 4, 5, 6, 7]
    newturn.hora_inicio, newturn.hora_fim = time(hora), time(12)
    newturn.tempo_intervalo, newturn.dias_semana = 0, [1, 2, 3, 4, 5, 6, 7]
    session.commit()
    payload, status = trocar(ctx, session)
    if hora == 6:
        assert status == 409 and payload["erro"]["codigo"] == "CONFLITO_ESCALA"
        assert "inicio" in payload["erro"]["detalhes"]
        assert session.get(Alocacoes, ctx.own.assignment.id).data_fim is None
    else:
        assert status == 201, payload


def test_sem_alteracao_ou_vinculo_encerrado(session, mudanca):
    ctx = mudanca
    assert trocar(ctx, session, novo_setor_id=ctx.own.sector.id, nova_escala_id=ctx.own.schedule.id)[1] == 400
    ctx.own.assignment.data_fim = date(2026, 10, 31)
    session.commit()
    assert trocar(ctx, session)[1] == 409


def test_rotas_jwt_papeis_e_opcoes_limitadas(session, pg_app, mudanca, monkeypatch):
    ctx = mudanca
    solicitar, opcoes = AlocacaoService.solicitar_mudanca, AlocacaoService.opcoes_mudanca
    monkeypatch.setattr(AlocacaoService, "solicitar_mudanca", staticmethod(
        lambda uid, eid, fid, data: solicitar(uid, eid, fid, data, session=session)))
    monkeypatch.setattr(AlocacaoService, "opcoes_mudanca", staticmethod(
        lambda uid, eid, tipo, q: opcoes(uid, eid, tipo, q, session=session)))
    client = pg_app.test_client()
    path = f"/api/web/funcionarios/{ctx.own.employee.id}/mudar-alocacao"
    options = "/api/web/alocacoes/opcoes-mudanca"
    assert client.post(path, json={}).status_code == 401
    assert client.get(options + "?tipo=setor").status_code == 401
    for i in range(25):
        session.add(Setores(empresa_id=ctx.own.company.id, nome=f"Setor {i:02}",
            latitude_centro=-8, longitude_centro=-35, raio_metros=100))
    session.commit()
    token = create_access_token(identity=str(ctx.gestor.id), additional_claims={"empresa_id": str(ctx.own.company.id)})
    headers = {"Authorization": "Bearer " + token}
    result = client.get(options + "?tipo=setor", headers=headers)
    assert result.status_code == 200 and len(result.json["opcoes"]) == 20
    assert all(row["empresa_id"] == str(ctx.own.company.id) for row in result.json["opcoes"])
    assert len(client.get(options + "?tipo=setor&q=24", headers=headers).json["opcoes"]) == 1
    assert client.get(options + "?tipo=invalido", headers=headers).status_code == 400
    body = {"alocacao_id": str(ctx.own.assignment.id), "novo_setor_id": str(ctx.setor.id),
        "nova_escala_id": str(ctx.escala.id), "data_transicao": "2026-11-04"}
    assert client.post(path, json={**body, "empresa_id": str(ctx.foreign.company.id)}, headers=headers).status_code == 400
    result = client.post(path, json=body, headers=headers)
    assert result.status_code == 201, result.json


def test_trocas_simultaneas_encerram_e_criam_uma_unica_vez():
    from test_mobile_w09 import concurrent_app
    with concurrent_app() as application, application.app_context():
        empresa = Empresas(razao_social="Corrida de mudança", cnpj="55332211000100")
        db.session.add(empresa)
        db.session.flush()
        rh = Usuarios(empresa_id=empresa.id, nome="RH", email="rh@race-mudanca.example", senha_hash="hash", papel=PapelUsuario.RH)
        pessoa = Funcionarios(empresa_id=empresa.id, nome="Maria", matricula="001")
        setores = [Setores(empresa_id=empresa.id, nome=nome, latitude_centro=0, longitude_centro=0, raio_metros=100)
            for nome in ("Origem", "Destino")]
        db.session.add_all([rh, pessoa, *setores])
        db.session.flush()
        atual = Alocacoes(empresa_id=empresa.id, funcionario_id=pessoa.id, setor_id=setores[0].id, data_inicio=date(2020, 1, 1))
        db.session.add(atual)
        db.session.commit()
        data = {"alocacao_id": str(atual.id), "novo_setor_id": str(setores[1].id), "nova_escala_id": None,
            "data_transicao": "2030-01-01"}
        path = f"/api/web/funcionarios/{pessoa.id}/mudar-alocacao"
        token = create_access_token(identity=str(rh.id), additional_claims={"empresa_id": str(empresa.id)})
        headers = {"Authorization": "Bearer " + token}
        db.session.remove()
        def worker(_):
            return application.test_client().post(path, json=data, headers=headers).status_code
        with ThreadPoolExecutor(max_workers=2) as pool:
            assert sorted(pool.map(worker, range(2))) == [201, 409]
        rows = application.test_client().get("/api/web/alocacoes", headers=headers).json["alocacoes"]
        assert len(rows) == 2
        assert sorted(r["data_inicio"] for r in rows) == ["2020-01-01", "2030-01-01"]
        assert {r["data_fim"] for r in rows} == {"2029-12-31", None}
        db.session.remove()


@pytest.mark.parametrize("data_fim", [None, date(2026, 11, 5)])
def test_transferencia_respeita_datas_independentes_e_intervalo(session, mudanca, data_fim):
    ctx = mudanca
    ctx.own.assignment.data_fim = data_fim
    session.commit()
    original = AlocacaoService._json(ctx.own.assignment)
    body = {"alocacao_id": str(ctx.own.assignment.id), "novo_setor_id": str(ctx.setor.id),
        "nova_escala_id": str(ctx.escala.id), "data_encerramento": "2026-11-04", "data_transicao": "2026-11-10"}
    payload, status = AlocacaoService.solicitar_mudanca(ctx.rh.id, ctx.own.company.id, ctx.own.employee.id, body, session=session)
    assert status == 201, payload
    assert payload["alocacao_anterior"] == {**original, "data_fim": "2026-11-04"}
    assert payload["alocacao"]["data_inicio"] == "2026-11-10"
    assert payload["alocacao"]["data_fim"] is None


@pytest.mark.parametrize("fim,inicio", [(None, "2026-11-04"), ("", "2026-11-04"),
    ("2026-11-04", "2026-11-04"), ("2026-11-05", "2026-11-04"), ("2026-02-30", "2026-11-04")])
def test_transferencia_datas_invalidas_nao_encerram_origem(session, mudanca, fim, inicio):
    ctx = mudanca
    body = {"alocacao_id": str(ctx.own.assignment.id), "novo_setor_id": str(ctx.setor.id),
        "nova_escala_id": str(ctx.escala.id), "data_encerramento": fim, "data_transicao": inicio}
    payload, status = AlocacaoService.solicitar_mudanca(ctx.rh.id, ctx.own.company.id, ctx.own.employee.id, body, session=session)
    assert status == 400, payload
    assert session.get(Alocacoes, ctx.own.assignment.id).data_fim is None
