# W06 — Feriados, afastamentos e espelho histórico

Os Services retornam `(payload, status_http)` e confirmam a conta real,
o perfil e a empresa ativa. O espelho está exposto no painel para RH e Gestor;
cadastros de feriados, afastamentos e ajustes manuais continuam exclusivos do RH.
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

A origem deve estar aberta ou ter fim não passado, incluindo a data da transição. Somente sua `data_fim` muda, para `2026-10-14`;
funcionário, usuário, setor, escala e início permanecem iguais. O destino recebe
outro ID. Encerramento, validação W03/W05 e cadastro pertencem à mesma transação;
se o destino falhar, o encerramento também é desfeito. Turnos noturnos da origem
podem conflitar com a manhã do destino e são verificados pelo motor W05.

O painel usa o método `mudar_alocacao` pelo endpoint descrito em
[Alocações](ALOCACOES.md), autorizado para RH e Gestor. A assinatura anterior
`trocar` continua disponível para integrações do RH. No painel, a nova alocação
nasce com fim nulo e o Gestor recebe um aviso fixo sobre o impacto na apuração.

Alocações podem ter fim nulo; o motor usa o horizonte explícito de dez anos
documentado em [Alocações](ALOCACOES.md), preservando a vigência aberta no banco.
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
faltas, atrasos e extras. Trabalho é obtido por pares de batidas efetivamente aceitas, excluindo as
pausas registradas. A falta básica corresponde ao tempo de presença não
coberto dentro do segmento previsto, ponderado pela jornada líquida; atraso
usa a primeira presença e desconta a tolerância da escala. Atrasos já estão
contidos nas faltas de jornada e não devem ser somados novamente como desconto.
O excedente diário é descrito abaixo. Essa base não calcula adicional noturno,
banco de horas ou valores financeiros.

Batidas pendentes/recusadas, pares incompletos, projeções ausentes e conflitos
geram `APURACAO_PENDENTE` e não faltas automáticas. Ajustes pendentes também
exigem revisão; ajustes aprovados são projetados conforme a regra abaixo.
Jornadas futuras/em andamento ainda não geram falta.
Os registros de ponto são apenas lidos, nunca editados ou excluídos.

## Invalidar uma marcação

A migration **0008** adiciona `justificativas_ajustes.tipo_ocorrencia`, com
`AJUSTE` para os registros existentes e `INVALIDACAO_GESTOR` para invalidações.
Execute o comando `db upgrade` acima antes de iniciar a API atualizada.
Esta migration não modifica `registros_ponto`.

RH e Gestor podem executar `POST /api/v1/admin/pontos/<registro_id>/invalidar`,
com JWT e corpo `{"motivo_texto": "Foto não corresponde ao funcionário"}`.
A API verifica a empresa e o papel atuais no banco, grava um contra-registro
aprovado com o autor e a data da decisão, e retorna `201 {"ajuste": {...}}`.
Não permite definir autor/status pelo payload. Motivo vazio retorna `400`;
ponto inexistente ou de outra empresa retorna `404`; invalidar uma marcação
atualmente invalidada retorna `409 PONTO_JA_INVALIDADO`. Um bloqueio de leitura
e um índice de sequência impedem duplicações concorrentes.

O espelho mantém a situação original e acrescenta `invalidado` e
`invalidacao: {id, motivo_texto, gestor_aprovador_id, decidido_em}` na marcação.
Batidas invalidadas ficam fora do cálculo de pares e horas. Se isso deixar uma
sequência incompleta, o dia exige análise em vez de inventar uma entrada/saída.
Enquanto vigente, a invalidação retira a batida e suas correções da apuração.
O RH pode revertê-la pelo fluxo de reaprovação abaixo.
No painel, o horário fica riscado e a situação indica a invalidação; o motivo
fica disponível ao passar sobre a situação. Não há correção de batida invalidada.

## Aprovar marcações e apurar horas extras

A migration **0011** permite `APROVACAO_GESTOR`. A **0012** evolui os índices
para manter decisões sucessivas, com uma sequência única por marcação.
Nenhuma delas modifica a tabela de pontos.

RH e Gestor podem enviar:

```http
POST /api/v1/admin/pontos/<registro_id>/aprovar
Authorization: Bearer JWT
Content-Type: application/json

{"motivo_texto": "Foto e horário conferidos; permanência autorizada"}
```

Retorna `201 {"ajuste": {...}}`. Motivo vazio ou campos extras retornam `400`;
outra empresa/inexistente retorna `404`. Ponto já aceito, aprovado, corrigido ou
invalidado retorna `409`. O papel e a empresa são revalidados no banco.
Uma aprovação não altera horário, tipo, selfie, motivos nem situação do original.
Se o horário estiver errado, use a correção do RH; aprovar conserva o horário.

O espelho acrescenta `aprovado_gestor` e `aprovacao` com ID, motivo, autor e
timestamp. A situação original continua disponível. A tabela e o modal da selfie
oferecem **Aprovar Marcação**, com confirmação e justificativa obrigatória.
Após a decisão, o painel consulta novamente o relatório.

Na projeção do relatório:

- Uma aprovação considera a batida na formação dos pares.
- Uma correção `AJUSTE` aprovada substitui horário/tipo apenas na projeção;
  a correção aprovada mais recente prevalece, com auditoria no DTO.
- Inclusões manuais aprovadas participam dos pares e aparecem como `MANUAL_RH`.
  A data deve identificar uma única alocação histórica; ambiguidade gera
  `AJUSTE_SEM_ALOCACAO_UNIVOCA`, sem adivinhar o setor.
- Um ajuste ainda pendente não é aplicado. Uma invalidação vigente retira o
  original e suas correções da formação dos pares até uma reaprovação do RH.

`minutos_extras` existe em cada dia e nos totais, e representa:

```text
max(0, minutos_trabalhados - minutos_exigiveis)
minutos_exigiveis = minutos_previstos - minutos_abonados
```

O cálculo só disponibiliza extras em dias sem pendências e com os turnos
previstos encerrados. Não compensa faltas de outros dias. Feriados e afastamentos
mantêm seus abonos; trabalho efetivo além das horas exigíveis aparece separado.
A virada de dia/mês mantém o rateio por dia civil no fuso da empresa.
Trabalho futuro não é computado.

**Uma saída isolada não determina duração.** Aprovar essa batida mantém a
pendência de sequência e não cria horas extras. O RH precisa conferir e
inserir/corrigir a entrada faltante, mantendo a justificativa de auditoria.

Esse é um excedente preliminar em horas, sem percentuais, pagamento, adicional
noturno ou banco de horas. `apuracao_definitiva` continua `false`.

## Aceite automático e reaprovação pelo RH

Batidas que passam pelas validações de aparelho, localização e desvio de relógio
recebem `Aceita` e entram automaticamente na apuração, sem aprovação manual.
O horário da escala serve à projeção da jornada e ao cálculo do excedente;
atualmente, estar fora do turno por si só não torna a marcação pendente.

Uma marcação invalidada por RH ou Gestor pode ser reaprovada **somente pelo RH**,
na tabela ou no modal da selfie. O motivo da invalidação atual é exibido antes
da confirmação, e a reaprovação exige uma nova justificativa.

```http
POST /api/v1/admin/pontos/<registro_id>/reaprovar
Authorization: Bearer JWT_DO_RH
Content-Type: application/json

{"motivo_texto": "Identidade e horário conferidos", "invalidacao_id": "UUID_DA_INVALIDACAO_ATUAL"}
```

A rota retorna `201 {"ajuste": {...}}`, com `tipo_ocorrencia: REAPROVACAO_RH`.
Gestor/Funcionário/Superadmin recebem `403`. Motivo ou referência inválidos
retornam `400`. Ponto de outra empresa/inexistente retorna `404`. Se a decisão
mudou desde a consulta, retorna `409 DECISAO_DESATUALIZADA`, orientando recarregar.
A referência obrigatória impede que uma confirmação antiga reverta outra decisão.

A migration **0012** adiciona `sequencia_decisao`, numera as decisões existentes
sem mudar seus motivos, autores, datas ou status, e substitui os índices antigos
por unicidade de empresa/marcação/sequência. Novas decisões são inseridas com lock
na marcação original; nenhuma decisão anterior é sobrescrita. O downgrade é
recusado quando há reaprovação ou ciclos de análise incompatíveis com o modelo antigo.

O relatório usa a decisão aprovada de maior sequência, permitindo invalidar,
reaprovar e invalidar novamente sem apagar o histórico. `historico_decisoes`
preserva todas as decisões aprovadas, e `reaprovado_rh` identifica o estado atual.
A reaprovação volta a considerar os pares e recalcula trabalhadas/extras.
Sequências incompletas continuam pendentes; reaprovar não fabrica horas.

### Revisar a selfie da marcação

O espelho inclui `foto_url` e `foto_recebida_em` somente quando há selfie
associada ao evento; sem foto, ambos são nulos. O campo `geofence` contém
`raio_metros`, `distancia_metros` (opcional) e `politica`, obtidos do snapshot
imutável da batida. A consulta mensal busca apenas metadados das fotos,
sem carregar o conteúdo binário ou realizar uma consulta por linha.

`GET /api/v1/admin/pontos/<registro_id>/selfie` exige JWT de RH/Gestor,
revalida a empresa e devolve JPEG/PNG com `Cache-Control: private, no-store`.
Foto ausente ou de outra empresa retorna `404`; perfil sem permissão, `403`.
Nenhuma migration adicional é necessária para a leitura das selfies.

No painel, o botão de câmera só é renderizado quando há foto. O modal faz o
download com o Dio autenticado no mesmo servidor, oferece zoom, carregamento,
nova tentativa em caso de erro e a ação de invalidar com motivo obrigatório.
A imagem permanece em memória durante a visualização; downloads pendentes
são cancelados e a entrada do cache de imagem é removida ao fechar.

O modal distingue o horário da marcação do recebimento da foto: o contrato
atual não fornece um timestamp separado para a captura da selfie. Depois de
invalidar, a situação muda imediatamente no modal e o espelho é recarregado
quando ele é fechado, mantendo a foto e a marcação para auditoria.

`apuracao_definitiva` permanece `false`: a base deve ser revisada antes de virar
fechamento de folha. As regras finais de folha ainda não fazem parte da apuração.

## Verificação

`tests/test_w06_services.py` cobre sobreposições inclusivas, concorrência,
CRUD isolado, abonos por escopo, turnos noturnos e cíclicos, fronteira de mês,
histórico de vínculos inativos, troca com rollback e migração com dados antigos.
Use `TEST_DATABASE_URL` em um banco isolado conforme o README; os testes criam
schemas aleatórios e não usam automaticamente a conexão de produção.
