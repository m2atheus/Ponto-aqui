"""Provisionamento explícito e relógio multiusuário sem revogação cruzada."""
import uuid
from datetime import date
from types import SimpleNamespace

import pytest
from flask_jwt_extended import decode_token
from sqlalchemy import func, select

from app.models import Alocacoes, DispositivoUsuarios, DispositivoUsuarioSetores, Dispositivos, Funcionarios, PapelUsuario, RegistrosPonto, Setores, Usuarios
from app.services.auth_service import AuthService
from test_ajustes_rh import contexto, headers, snapshot
from test_mobile_w09 import payload as marcacao


def caminho(funcionario_id):
    return f"/api/v1/admin/funcionarios/{funcionario_id}/dispositivos"


def autorizar(ctx, pessoa=None, codigo=None, tipo="PESSOAL", **campos):
    return ctx.client.post(caminho((pessoa or ctx.own.employee).id), headers=headers(ctx.rh),
        json={"device_uuid": str(codigo or uuid.uuid4()), "tipo": tipo, **campos})


def colega(ctx, session):
    conta = Usuarios(empresa_id=ctx.own.company.id, nome="Colega", email="colega-app@example.com",
        senha_hash=AuthService.hash_senha("Teste12345!"))
    session.add(conta)
    session.flush()
    pessoa = Funcionarios(empresa_id=ctx.own.company.id, usuario_id=conta.id, nome="Colega", matricula="COLEGA-001")
    session.add(pessoa)
    session.flush()
    alocacao = Alocacoes(empresa_id=ctx.own.company.id, funcionario_id=pessoa.id, usuario_id=conta.id,
        setor_id=ctx.own.sector.id, escala_id=ctx.own.schedule.id, data_inicio=date(2020, 1, 1))
    session.add(alocacao)
    session.commit()
    return SimpleNamespace(user=conta, employee=pessoa, assignment=alocacao)


def login(ctx, usuario, codigo):
    resposta = ctx.client.post("/api/mobile/auth/login", json={"email": usuario.email,
        "senha": "Teste12345!", "device_uuid": str(codigo)})
    assert resposta.status_code == 200, resposta.json
    return {"Authorization": "Bearer " + resposta.json["access_token"], "X-Device-UUID": str(codigo)}


@pytest.mark.parametrize("metodo,sufixo", [("get", ""), ("post", ""), ("post", f"/{uuid.uuid4()}/revogar")])
def test_rotas_exigem_jwt(app, metodo, sufixo):
    assert getattr(app.test_client(), metodo)(caminho(uuid.uuid4()) + sufixo).status_code == 401


@pytest.mark.postgres
def test_pessoal_autorizado_manual_lista_e_revoga_anterior(contexto, session):
    ctx = contexto
    primeiro = autorizar(ctx)
    assert primeiro.status_code == 201, primeiro.json
    primeiro_id = uuid.UUID(primeiro.json["dispositivo"]["id"])
    segundo = autorizar(ctx, nome_identificador="Meu celular")
    assert segundo.status_code == 201
    assert session.get(Dispositivos, primeiro_id).ativo is False
    dto = segundo.json["dispositivo"]
    assert dto["tipo"] == "PESSOAL" and dto["status"] == "Ativo"
    lista = ctx.client.get(caminho(ctx.own.employee.id), headers=headers(ctx.rh))
    assert lista.status_code == 200 and len(lista.json["dispositivos"]) == 2
    revogar = caminho(ctx.own.employee.id) + f"/{dto['id']}/revogar"
    assert ctx.client.post(revogar, headers=headers(ctx.rh)).json["dispositivo"]["ativo"] is False
    assert session.scalar(select(func.count()).select_from(Dispositivos)) == 2


@pytest.mark.postgres
def test_relogio_mesmo_uuid_login_sync_e_pontos_de_duas_pessoas(contexto, session):
    ctx = contexto
    ctx.own.user.senha_hash = AuthService.hash_senha("Teste12345!")
    session.commit()
    outro = colega(ctx, session)
    pessoal = autorizar(ctx).json["dispositivo"]
    codigo = uuid.uuid4()
    um = autorizar(ctx, codigo=codigo, tipo="RELOGIO")
    dois = autorizar(ctx, pessoa=outro.employee, codigo=codigo, tipo="RELOGIO")
    assert um.status_code == dois.status_code == 201, (um.json, dois.json)
    dispositivo_id = um.json["dispositivo"]["id"]
    assert dispositivo_id == dois.json["dispositivo"]["id"]
    assert session.scalar(select(func.count()).select_from(Dispositivos).where(Dispositivos.device_uuid == codigo)) == 1
    antes = snapshot(session)
    h1 = login(ctx, ctx.own.user, codigo)
    h2 = login(ctx, outro.user, codigo)
    assert decode_token(h1["Authorization"][7:])["dispositivo_id"] == dispositivo_id
    for pessoa, cabecalhos in [(ctx.own, h1), (outro, h2)]:
        sync = ctx.client.get("/api/v1/mobile/sync", headers=cabecalhos)
        assert sync.status_code == 200 and sync.json["modo_operacao"] == "RELOGIO", sync.json
        batida = ctx.client.post("/api/mobile/marcacoes/lote", headers=cabecalhos,
            json={"marcacoes": [marcacao(pessoa, dispositivo_id)]})
        assert batida.status_code == 200 and batida.json["resultados"][0]["situacao"] == "Aceita", batida.json
    assert session.get(Dispositivos, uuid.UUID(pessoal["id"])).ativo is True
    # Revogar um vínculo não desativa o relógio nem a sessão do colega.
    revogar = caminho(ctx.own.employee.id) + f"/{dispositivo_id}/revogar"
    assert ctx.client.post(revogar, headers=headers(ctx.rh)).status_code == 200
    assert ctx.client.get("/api/v1/mobile/sync", headers=h1).status_code == 403
    assert ctx.client.get("/api/v1/mobile/sync", headers=h2).status_code == 200
    assert session.get(Dispositivos, uuid.UUID(dispositivo_id)).ativo is True
    por_id = {p["id"]: p for p in snapshot(session)}
    assert all(por_id[p["id"]] == p for p in antes)
    # O primeiro funcionário pode voltar a ser autorizado, sem duplicar o aparelho.
    assert autorizar(ctx, codigo=codigo, tipo="RELOGIO").status_code == 201
    assert ctx.client.get("/api/v1/mobile/sync", headers=h1).status_code == 200


@pytest.mark.postgres
def test_nao_autoriza_ou_lista_funcionario_de_outra_empresa(contexto, session):
    ctx = contexto
    assert autorizar(ctx, pessoa=ctx.foreign.employee).status_code == 404
    assert ctx.client.get(caminho(ctx.foreign.employee.id), headers=headers(ctx.rh)).status_code == 404
    codigo = uuid.uuid4()
    response = ctx.client.post(caminho(ctx.foreign.employee.id), headers=headers(ctx.foreign.user),
        json={"device_uuid": str(codigo), "tipo": "PESSOAL"})
    assert response.status_code == 403


@pytest.mark.postgres
@pytest.mark.parametrize("dados", [{}, {"device_uuid": "invalido", "tipo": "PESSOAL"},
    {"device_uuid": str(uuid.uuid4()), "tipo": "ADMIN"},
    {"device_uuid": str(uuid.uuid4()), "tipo": "PESSOAL", "empresa_id": str(uuid.uuid4())},
    {"device_uuid": str(uuid.uuid4()), "tipo": "PESSOAL", "nome_identificador": []}])
def test_campos_invalidos_nao_provisionam(contexto, session, dados):
    ctx = contexto
    assert ctx.client.post(caminho(ctx.own.employee.id), headers=headers(ctx.rh), json=dados).status_code == 400
    assert session.scalar(select(func.count()).select_from(Dispositivos)) == 0


@pytest.mark.postgres
def test_gestor_consulta_mas_nao_provisiona_e_vinculo_exige_conta(contexto, session):
    ctx = contexto
    ctx.rh.papel = PapelUsuario.GESTOR
    session.commit()
    assert ctx.client.get(caminho(ctx.own.employee.id), headers=headers(ctx.rh)).status_code == 200
    assert autorizar(ctx).status_code == 403
    ctx.rh.papel = PapelUsuario.RH
    pessoa = Funcionarios(empresa_id=ctx.own.company.id, nome="Sem conta", matricula="SEM-CONTA")
    session.add(pessoa)
    session.commit()
    resposta = autorizar(ctx, pessoa=pessoa)
    assert resposta.status_code == 400 and resposta.json["erro"]["codigo"] == "FUNCIONARIO_SEM_USUARIO"


@pytest.mark.postgres
def test_relogio_requer_setor_alocado_e_autorizacao_por_usuario(contexto, session):
    ctx = contexto
    codigo = uuid.uuid4()
    assert autorizar(ctx, codigo=codigo, tipo="RELOGIO", setor_id=str(ctx.foreign.sector.id)).status_code == 400
    assert autorizar(ctx, codigo=codigo, tipo="RELOGIO").status_code == 201
    outro = colega(ctx, session)
    resposta = ctx.client.post("/api/mobile/auth/login", json={"email": outro.user.email,
        "senha": "Teste12345!", "device_uuid": str(codigo)})
    assert resposta.status_code == 401
    assert resposta.json["erro"]["mensagem"] == "Usuário ou senha inválidos"


@pytest.mark.postgres
def test_converter_pessoal_em_relogio_exige_confirmacao_e_preserva_pontos(contexto, session, point_values):
    ctx = contexto
    ctx.own.user.senha_hash = AuthService.hash_senha("Teste12345!")
    session.commit()
    outro = colega(ctx, session)
    codigo = uuid.uuid4()
    pessoal = autorizar(ctx, codigo=codigo).json["dispositivo"]
    dispositivo_id = uuid.UUID(pessoal["id"])
    token_pessoal = login(ctx, ctx.own.user, codigo)
    session.add(RegistrosPonto(**{**point_values, "evento_cliente_id": uuid.uuid4(),
        "dispositivo_cliente_id": dispositivo_id, "dispositivo_registrado_id": dispositivo_id}))
    session.commit()
    antes = snapshot(session)
    tentativa = autorizar(ctx, pessoa=outro.employee, codigo=codigo, tipo="RELOGIO")
    assert tentativa.status_code == 409
    assert tentativa.json["erro"]["codigo"] == "CONVERSAO_RELOGIO_NECESSARIA"
    assert session.get(Dispositivos, dispositivo_id).tipo.value == "PESSOAL"
    assert snapshot(session) == antes
    convertido = autorizar(ctx, pessoa=outro.employee, codigo=codigo, tipo="RELOGIO", converter_para_relogio=True)
    assert convertido.status_code == 201, convertido.json
    assert convertido.json["dispositivo"]["id"] == pessoal["id"]
    assert convertido.json["dispositivo"]["setor_id"] == str(ctx.own.sector.id)
    for pessoa in [ctx.own, outro]:
        cabecalhos = login(ctx, pessoa.user, codigo)
        sync = ctx.client.get("/api/v1/mobile/sync", headers=cabecalhos)
        assert sync.status_code == 200 and sync.json["modo_operacao"] == "RELOGIO"
    # O token antigo não contém o novo contexto de setor: o app deve entrar novamente.
    antigo = ctx.client.get("/api/v1/mobile/sync", headers=token_pessoal)
    assert antigo.status_code == 403 and antigo.json["erro"]["codigo"] == "DISPOSITIVO_MODO_ALTERADO"
    assert snapshot(session) == antes
    assert session.scalar(select(func.count()).select_from(Dispositivos)) == 1
    assert session.scalar(select(func.count()).select_from(DispositivoUsuarios)) == 2


@pytest.mark.postgres
def test_conversao_adiciona_outro_setor_e_preserva_o_setor_do_titular(contexto, session):
    ctx = contexto
    ctx.own.user.senha_hash = AuthService.hash_senha("Teste12345!")
    session.commit()
    outro = colega(ctx, session)
    codigo = uuid.uuid4()
    pessoal = autorizar(ctx, codigo=codigo).json["dispositivo"]
    setor = Setores(empresa_id=ctx.own.company.id, nome="Outro setor", latitude_centro=0,
        longitude_centro=0, raio_metros=100)
    session.add(setor)
    session.flush()
    session.add(Alocacoes(empresa_id=ctx.own.company.id, funcionario_id=outro.employee.id,
        usuario_id=outro.user.id, setor_id=setor.id, data_inicio=date(2020, 1, 1)))
    session.commit()
    tentativa = autorizar(ctx, pessoa=outro.employee, codigo=codigo, tipo="RELOGIO",
        setor_id=str(setor.id), converter_para_relogio=True)
    assert tentativa.status_code == 201, tentativa.json
    aparelho = session.get(Dispositivos, uuid.UUID(pessoal["id"]))
    assert aparelho.tipo.value == "RELOGIO" and aparelho.usuario_id is None
    for pessoa, esperado in [(ctx.own, ctx.own.sector.id), (outro, setor.id)]:
        cabecalhos = login(ctx, pessoa.user, codigo)
        sync = ctx.client.get("/api/v1/mobile/sync", headers=cabecalhos)
        assert sync.status_code == 200 and sync.json["setor"]["id"] == str(esperado), sync.json
    lista = ctx.client.get(caminho(ctx.own.employee.id), headers=headers(ctx.rh)).json["dispositivos"]
    assert lista[0]["setores"] == [{"id": str(ctx.own.sector.id), "nome": ctx.own.sector.nome, "ativo": True}]


@pytest.mark.postgres
def test_conversao_nao_restaura_acesso_que_ja_estava_revogado(contexto, session):
    ctx = contexto
    ctx.own.user.senha_hash = AuthService.hash_senha("Teste12345!")
    session.commit()
    outro = colega(ctx, session)
    codigo = uuid.uuid4()
    pessoal = autorizar(ctx, codigo=codigo).json["dispositivo"]
    assert ctx.client.post(caminho(ctx.own.employee.id) + f"/{pessoal['id']}/revogar",
        headers=headers(ctx.rh)).status_code == 200
    assert autorizar(ctx, pessoa=outro.employee, codigo=codigo, tipo="RELOGIO", converter_para_relogio=True).status_code == 201
    resposta = ctx.client.post("/api/mobile/auth/login", json={"email": ctx.own.user.email,
        "senha": "Teste12345!", "device_uuid": str(codigo)})
    assert resposta.status_code == 401
    assert login(ctx, outro.user, codigo)["Authorization"].startswith("Bearer ")


@pytest.mark.postgres
@pytest.mark.parametrize("tipo,flag", [("PESSOAL", True), ("RELOGIO", "true"), ("RELOGIO", 1)])
def test_conversao_nao_aceita_flag_invalida(contexto, session, tipo, flag):
    assert autorizar(contexto, tipo=tipo, converter_para_relogio=flag).status_code == 400
    assert session.scalar(select(func.count()).select_from(Dispositivos)) == 0


def alocar_outro_setor(ctx, session, pessoa):
    setor = Setores(empresa_id=ctx.own.company.id, nome="Portaria", latitude_centro=-8,
        longitude_centro=-35, raio_metros=100)
    session.add(setor)
    session.flush()
    alocacao = Alocacoes(empresa_id=ctx.own.company.id, funcionario_id=pessoa.employee.id,
        usuario_id=pessoa.user.id, setor_id=setor.id, data_inicio=date(2020, 1, 1))
    session.add(alocacao)
    session.commit()
    return setor, alocacao


@pytest.mark.postgres
def test_mesmo_usuario_aparelho_em_dois_setores_e_revogacao_independente(contexto, session):
    ctx = contexto
    ctx.own.user.senha_hash = AuthService.hash_senha("Teste12345!")
    session.commit()
    codigo = uuid.uuid4()
    primeiro = autorizar(ctx, codigo=codigo, tipo="RELOGIO").json["dispositivo"]
    setor_b, alocacao_b = alocar_outro_setor(ctx, session, ctx.own)
    segundo = autorizar(ctx, codigo=codigo, tipo="RELOGIO", setor_id=str(setor_b.id))
    assert segundo.status_code == 201
    assert primeiro["id"] == segundo.json["dispositivo"]["id"]
    assert len(segundo.json["dispositivo"]["setores"]) == 2
    cabecalhos = login(ctx, ctx.own.user, codigo)
    inicial = ctx.client.get("/api/v1/mobile/sync", headers=cabecalhos)
    assert inicial.status_code == 200 and len(inicial.json["setores_disponiveis"]) == 2
    mudar = ctx.client.get("/api/v1/mobile/sync", headers=cabecalhos, query_string={"setor_id": str(setor_b.id)})
    assert mudar.status_code == 200 and mudar.json["setor"]["id"] == str(setor_b.id)
    assert ctx.client.get("/api/v1/mobile/sync", headers=cabecalhos,
        query_string={"setor_id": str(ctx.foreign.sector.id)}).status_code == 403
    aparelho_id = uuid.UUID(primeiro["id"])
    antes = snapshot(session)
    for alocacao in [ctx.own.assignment, alocacao_b]:
        response = ctx.client.post("/api/mobile/marcacoes/lote", headers=cabecalhos,
            json={"marcacoes": [marcacao(SimpleNamespace(assignment=alocacao), aparelho_id)]})
        assert response.json["resultados"][0]["situacao"] == "Aceita", response.json
    escopo_a = session.get(DispositivoUsuarioSetores, (aparelho_id, ctx.own.company.id, ctx.own.user.id, ctx.own.sector.id))
    escopo_a.ativo = False
    session.commit()
    assert autorizar(ctx, codigo=codigo, tipo="RELOGIO", setor_id=str(setor_b.id)).status_code == 201
    assert session.get(DispositivoUsuarioSetores, (aparelho_id, ctx.own.company.id, ctx.own.user.id, ctx.own.sector.id)).ativo is False
    assert ctx.client.get("/api/v1/mobile/sync", headers=cabecalhos,
        query_string={"setor_id": str(setor_b.id)}).status_code == 200
    for alocacao, esperado in [(ctx.own.assignment, "Recusada"), (alocacao_b, "Aceita")]:
        response = ctx.client.post("/api/mobile/marcacoes/lote", headers=cabecalhos,
            json={"marcacoes": [marcacao(SimpleNamespace(assignment=alocacao), aparelho_id)]})
        assert response.json["resultados"][0]["situacao"] == esperado
    atuais = {p["id"]: p for p in snapshot(session)}
    assert all(atuais[p["id"]] == p for p in antes)
    assert session.scalar(select(func.count()).select_from(Dispositivos)) == 1


@pytest.mark.postgres
def test_aparelho_revogado_pode_ser_autorizado_em_outro_setor_sem_reativar_titular(contexto, session):
    ctx = contexto
    ctx.own.user.senha_hash = AuthService.hash_senha("Teste12345!")
    session.commit()
    outro = colega(ctx, session)
    setor_b, _ = alocar_outro_setor(ctx, session, outro)
    codigo = uuid.uuid4()
    pessoal = autorizar(ctx, codigo=codigo).json["dispositivo"]
    assert ctx.client.post(caminho(ctx.own.employee.id) + f"/{pessoal['id']}/revogar", headers=headers(ctx.rh)).status_code == 200
    convertido = autorizar(ctx, pessoa=outro.employee, codigo=codigo, tipo="RELOGIO",
        setor_id=str(setor_b.id), converter_para_relogio=True)
    assert convertido.status_code == 201, convertido.json
    assert convertido.json["dispositivo"]["id"] == pessoal["id"]
    assert convertido.json["dispositivo"]["setores"] == [{"id": str(setor_b.id), "nome": setor_b.nome, "ativo": True}]
    cabecalhos = login(ctx, outro.user, codigo)
    sync = ctx.client.get("/api/v1/mobile/sync", headers=cabecalhos)
    assert sync.status_code == 200 and sync.json["setor"]["id"] == str(setor_b.id)
    assert ctx.client.post("/api/mobile/auth/login", json={"email": ctx.own.user.email,
        "senha": "Teste12345!", "device_uuid": str(codigo)}).status_code == 401


@pytest.mark.postgres
@pytest.mark.parametrize("desativacao_fisica", [False, True])
def test_relogio_inativo_reutilizado_em_outro_setor_nao_restaura_acessos(contexto, session, desativacao_fisica):
    ctx = contexto
    outro = colega(ctx, session)
    setor_b, _ = alocar_outro_setor(ctx, session, outro)
    codigo = uuid.uuid4()
    antigo = autorizar(ctx, codigo=codigo, tipo="RELOGIO").json["dispositivo"]
    if desativacao_fisica:
        session.get(Dispositivos, uuid.UUID(antigo["id"])).ativo = False
        session.commit()
    else:
        assert ctx.client.post(caminho(ctx.own.employee.id) + f"/{antigo['id']}/revogar", headers=headers(ctx.rh)).status_code == 200
    novo = autorizar(ctx, pessoa=outro.employee, codigo=codigo, tipo="RELOGIO", setor_id=str(setor_b.id))
    assert novo.status_code == 201, novo.json
    assert novo.json["dispositivo"]["id"] == antigo["id"]
    assert novo.json["dispositivo"]["setores"] == [{"id": str(setor_b.id), "nome": setor_b.nome, "ativo": True}]
    cabecalhos = login(ctx, outro.user, codigo)
    assert ctx.client.get("/api/v1/mobile/sync", headers=cabecalhos).json["setor"]["id"] == str(setor_b.id)
    anterior = session.get(DispositivoUsuarios, (uuid.UUID(antigo["id"]), ctx.own.company.id, ctx.own.user.id))
    assert anterior.ativo is False


@pytest.mark.postgres
def test_migration_0010_preserva_status_dos_relogios_existentes(contexto, session):
    import importlib.util
    from pathlib import Path
    from alembic.migration import MigrationContext
    from alembic.operations import Operations
    from app.models import TipoDispositivo

    ctx = contexto
    path = Path(__file__).resolve().parents[1] / "migrations/versions/0010_dispositivos_multissetor.py"
    spec = importlib.util.spec_from_file_location("migration_multissetor", path)
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    antes = snapshot(session)
    connection = session.connection()
    with Operations.context(MigrationContext.configure(connection)):
        migration.downgrade()
        aparelhos = []
        for fisico, vinculo in [(True, True), (True, False), (False, True)]:
            aparelho = Dispositivos(empresa_id=ctx.own.company.id, device_uuid=uuid.uuid4(),
                tipo=TipoDispositivo.RELOGIO, setor_id=ctx.own.sector.id, nome="Legado", ativo=fisico)
            session.add(aparelho)
            session.flush()
            session.add(DispositivoUsuarios(empresa_id=ctx.own.company.id, dispositivo_id=aparelho.id,
                usuario_id=ctx.own.user.id, ativo=vinculo))
            session.flush()
            aparelhos.append((aparelho.id, fisico and vinculo))
        migration.upgrade()
    for aparelho_id, esperado in aparelhos:
        escopo = session.get(DispositivoUsuarioSetores,
            (aparelho_id, ctx.own.company.id, ctx.own.user.id, ctx.own.sector.id))
        assert escopo.ativo is esperado
    assert snapshot(session) == antes
