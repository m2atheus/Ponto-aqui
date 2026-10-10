# W06 — Feriados, afastamentos e espelho histórico

Esta etapa implementa os Services e atualiza os modelos. Os Controllers e as
telas W06 ainda não estão expostos. Cada Service retorna `(payload, status_http)`
e confirma a conta real do RH, o perfil e a empresa ativa antes das consultas.
O `empresa_id` deve vir do JWT do solicitante; não é aceito no corpo do cadastro.

## Atualizar o banco

A migration **0006** acrescenta `afastamentos.usuario_id`, preenche esse vínculo
pelos funcionários existentes e cria FKs compostas para impedir mistura de
usuário, funcionário e empresa. O vínculo principal `funcionario_id` e a
proteção de sobreposição existentes são preservados. `usuario_id` continua
opcional para os funcionários cadastrados antes de receberem uma conta.

Na raiz, com o `.env` já configurado:

```powershell
.\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade
```

Depois reinicie o Flask. A migration foi verificada em PostgreSQL local de teste;
nesta etapa ela não foi executada no Supabase online.

## Feriados e afastamentos

`FeriadoService` e `AfastamentoService` oferecem `listar`, `criar`, `atualizar` e
`remover`. Recebem o ID do RH e a empresa do token, além dos dados ou ID alvo.
O `session` opcional permite testes e integração com transações isoladas.

Exemplos para futuros Controllers:

```python
payload, status = FeriadoService.criar(rh_id, empresa_id, {
    "data": "2026-10-12",
    "descricao": "Feriado da empresa",
    "setor_id": None,
})

payload, status = AfastamentoService.criar(rh_id, empresa_id, {
    "usuario_id": usuario_do_funcionario,
    "tipo": "FERIAS",
    "data_inicio": "2026-10-05",
    "data_fim": "2026-10-09",
    "anexo_url": None,
})
```

Para funcionários sem login, o afastamento aceita `funcionario_id` no lugar de
`usuario_id`. Se ambos forem enviados, devem identificar a mesma pessoa.
Tipos canônicos: `FERIAS`, `ATESTADO`, `LICENCA` e `OUTROS`. URLs de anexo usam
HTTP/HTTPS e são apenas referências; o Service não baixa o arquivo.

Datas são civis ISO `AAAA-MM-DD`. Os extremos de afastamento são inclusivos:
um período até dia 9 conflita com outro que começa dia 9, mas não com dia 10.
O cadastro e a edição verificam sobreposição. Um lock do funcionário e a
exclusion constraint protegem também os envios concorrentes. O erro é HTTP 400:

```json
{
  "erro": {
    "codigo": "AFASTAMENTO_SOBREPOSTO",
    "mensagem": "O funcionário já possui afastamento nesse período."
  }
}
```

Feriados são únicos por empresa, data e escopo. Um feriado geral e outro de um
setor podem coexistir na mesma data; duplicidade no mesmo escopo recebe 409.
Referências a funcionários ou setores de outra empresa recebem 404. Mudanças
de afastamento não permitem transferir o vínculo para outra pessoa.

## Troca de alocação sem apagar histórico

```python
payload, status = AlocacaoService.trocar(rh_id, empresa_id, alocacao_anterior_id, {
    "setor_id": novo_setor_id,
    "escala_id": nova_escala_id,
    "data_inicio": "2026-10-15",
    "data_fim": "2026-12-31",
})
```

A origem deve estar aberta. Somente sua `data_fim` muda, para `2026-10-14`;
funcionário, usuário, setor, escala e início permanecem iguais. O destino recebe
outro ID. Encerramento, validação W03/W05 e cadastro pertencem à mesma transação;
se o destino falhar, o encerramento também é desfeito. Turnos noturnos da origem
podem conflitar com a manhã do destino e são verificados pelo motor W05.

O motor W05 existente exige fim explícito quando há uma escala a validar; não
se usa uma janela curta para afirmar que uma alocação ilimitada não tem conflitos.
Para mudar a definição de uma escala já usada, cadastre uma nova escala e use a
troca; editar os turnos do mesmo registro mudaria os cálculos dos seus períodos
antigos. Esta etapa preserva os vínculos históricos, sem versionar os turnos.

## Base do espelho mensal

```python
payload, status = EspelhoService.gerar_mensal(
    rh_id, empresa_id, usuario_do_funcionario, ano=2026, mes=10,
)
```

Para funcionário sem conta, envie `usuario_alvo_id=None` e `funcionario_id`.
A resposta `payload["espelho"]` contém empresa, funcionário, fuso, mês,
alocações históricas, dias, totais em minutos e `tem_pendencias`.

O relatório consulta todas as alocações que ocupam o período, inclusive a
véspera do mês, e usa os respectivos setor e escala. Funcionários, setores e
escalas inativos continuam disponíveis para consultas históricas. Uma troca
futura não muda os turnos e os totais dos meses anteriores.

Os turnos são projetados no fuso da empresa, incluindo modelos semanais e
cíclicos. As horas são divididas por **dia civil**. Quando o intervalo só possui
duração, ele é distribuído proporcionalmente: um turno 19h–7h com 60 minutos
de pausa prevê 275 minutos no primeiro dia e 385 no segundo. Os cálculos usam
frações exatas e só arredondam na serialização, evitando perdas acumuladas.

Cada segmento de jornada recebe abono quando há afastamento ou feriado geral
ou do seu próprio setor. Um feriado de outro setor não interfere no cálculo.
Um dia inteiramente abonado recebe `ABONADO_JUSTIFICADO`, com descrição
`Abonado/Justificado`, `minutos_faltas: 0` e `minutos_atrasos: 0`.
Em um dia com duas alocações, o feriado de apenas um setor abona somente esse
segmento; a resposta pode indicar `ABONO_PARCIAL`.

Os totais distinguem minutos previstos, abonados, exigíveis, trabalhados,
faltas e atrasos. Trabalho é obtido por pares de batidas aceitas, excluindo as
pausas registradas. A falta básica corresponde ao tempo de presença não
coberto dentro do segmento previsto, ponderado pela jornada líquida; atraso
usa a primeira presença e desconta a tolerância da escala. Atrasos já estão
contidos nas faltas de jornada e não devem ser somados novamente como desconto.
Essa base não calcula excesso de intervalo, horas extras, adicional noturno,
banco de horas ou valores financeiros.

Batidas pendentes/recusadas, pares incompletos, projeções ausentes e conflitos
geram `APURACAO_PENDENTE` e não faltas automáticas. Ajustes W10 não rejeitados
também exigem revisão dos dias envolvidos; esta etapa não aplica seus valores
propostos ao cálculo. Jornadas futuras/em andamento ainda não geram falta.
Os registros de ponto são apenas lidos, nunca editados ou excluídos.

`apuracao_definitiva` permanece `false`: a base deve ser revisada antes de virar
fechamento de folha. Rotas, integração Web e regras finais de apuração não fazem
parte desta etapa de Service Layer.

## Verificação

`tests/test_w06_services.py` cobre sobreposições inclusivas, concorrência,
CRUD isolado, abonos por escopo, turnos noturnos e cíclicos, fronteira de mês,
histórico de vínculos inativos, troca com rollback e migração com dados antigos.
Use `TEST_DATABASE_URL` em um banco isolado conforme o README; os testes criam
schemas aleatórios e não usam automaticamente a conexão de produção.
