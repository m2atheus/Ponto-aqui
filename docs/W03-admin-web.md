# Funcionários e alocações no painel

O conteúdo de `/funcionarios` e `/alocacoes` usa Riverpod e repositórios injetados com o
mesmo Dio do painel. A tela recebe dados da API; não mantém cadastros mockados.
O layout global e suas permissões permanecem sob o roteador existente.

**Funcionários:** GET, POST e PUT/PATCH estão implementados no Flask, com
validação no `FuncionarioService`, matrícula única por empresa e desativação
sem exclusão. Os retornos seguem o contrato do frontend. O OPTIONS automático
responde HTTP 200 para a verificação CORS anterior às chamadas com JWT.

**Alocações:** a tela, GET/POST e PUT/PATCH estão implementados. O modal de
cadastro consulta funcionários e setores da empresa, oferece dois Dropdowns
e recebe início obrigatório e fim opcional. As datas aparecem em DD/MM/AAAA,
com entrada manual ou calendário; o JSON usa AAAA-MM-DD.

O encerramento de um vínculo em aberto permite definir somente `data_fim`.
Funcionário, setor, escala e início ficam preservados. A linha permanece na
tabela; não há exclusão nem reabertura. Repetir o mesmo encerramento retorna
sucesso; tentar alterar um fim já definido retorna HTTP 409.

O GET de setores é uma consulta para alimentar essa tela, com `id`, `nome`,
`empresa_id` e `ativo`. O histórico usa todos os funcionários e setores, mas
o cadastro oferece apenas os ativos. Sem opções ativas, a tela informa o
que falta cadastrar. O CRUD completo de Setores continua em outra etapa.

## Executar após atualizar o backend

Pare a API com `Ctrl+C` no terminal onde ela está rodando e inicie novamente
na raiz do projeto para carregar as novas rotas:

```powershell
.\.venv\Scripts\python.exe run.py
```

Mantenha esse terminal aberto. No painel, entre com uma conta real de RH e
clique em **Tentar novamente** ou atualize a página. O painel padrão roda em
`http://localhost:3000`, origem configurada no `CORS_ORIGINS` do `.env`.
Se usar outra origem, configure o endereço exato e reinicie o Flask.
Os modelos existentes já possuem os campos utilizados; esta correção não
introduz uma migration.

## Contrato HTTP

`API_BASE_URL` mantém o padrão `http://localhost:5000/api/web/`.
O interceptor existente injeta `Authorization: Bearer <JWT>`.
É necessária uma conta **real de RH**, vinculada à empresa; o acesso de
demonstração permite apenas navegação. O backend deve extrair `empresa_id`
do JWT e validar perfil e isolamento em todas as operações.

| Método | Caminho | Corpo | Resposta de sucesso |
| --- | --- | --- | --- |
| GET | `/api/web/funcionarios` | — | `{"funcionarios": [...]}` |
| POST | `/api/web/funcionarios` | `nome`, `matricula`, `cargo` | `{"funcionario": {...}}` |
| PUT | `/api/web/funcionarios/<id>` | `nome`, `matricula`, `cargo` | `{"funcionario": {...}}` |
| PUT | `/api/web/funcionarios/<id>` | `{"ativo": false}` | `{"funcionario": {...}}` |
| GET | `/api/web/setores` | — | `{"setores": [...]}` |
| GET | `/api/web/alocacoes` | — | `{"alocacoes": [...]}` |
| POST | `/api/web/alocacoes` | `funcionario_id`, `setor_id`, `data_inicio`, `data_fim`; `escala_id` opcional | `{"alocacao": {...}}` |
| PUT | `/api/web/alocacoes/<id>` | `{"data_fim": "2026-10-31"}` | `{"alocacao": {...}}` |

As consultas também aceitam um array diretamente; as escritas aceitam o objeto
diretamente. O GET de alocações permite o filtro opcional `funcionario_id`.
O frontend exige o registro completo nas respostas de escrita; não trata uma
resposta vazia como confirmação de cadastro ou desativação.

Períodos W03 incluem a data final: uma alocação até 31/10 só permite outra
no mesmo setor a partir de 01/11. Vínculos em aberto também bloqueiam
períodos sobrepostos futuros. A API trava o funcionário durante o cadastro
e utiliza a constraint de exclusão do banco para proteger chamadas concorrentes.
A validação usa somente dados e políticas do servidor.

A tela atual cria vínculos com o setor, sem selecionar uma escala. Quando
`escala_id` é enviado por outro consumidor, a API também consulta o motor W05:
exige funcionário com conta vinculada e período finito, conforme o contrato
desse motor, e verifica horários conflitantes em qualquer setor.

Funcionario:

```json
{
  "id": "uuid-do-funcionario",
  "nome": "Ana Silva",
  "matricula": "001",
  "cargo": null,
  "empresa_id": "uuid-da-empresa",
  "ativo": true
}
```

Alocacao:

```json
{
  "id": "uuid-da-alocacao",
  "funcionario_id": "uuid-do-funcionario",
  "setor_id": "uuid-do-setor",
  "data_inicio": "2026-10-01",
  "data_fim": null,
  "empresa_id": "uuid-da-empresa",
  "escala_id": "uuid-da-escala"
}
```

`cargo` é opcional conforme o modelo Flask atual. Nome e matrícula são
obrigatórios, com limites de 150 e 50 caracteres; cargo admite 120 caracteres.
Datas são civis no formato `AAAA-MM-DD`, sem conversão de fuso no navegador.
O DTO de alocação também aceita respostas sem `empresa_id` e `escala_id`,
conforme os campos mínimos solicitados; se a empresa vier informada, deve
coincidir com a sessão. O ID do próprio registro e `empresa_id` não são enviados
no corpo do cadastro; os IDs de funcionário, setor e escala são seus vínculos.

## Erros e histórico

Erros de negócio HTTP 400/409/422 seguem o envelope usado pela API existente:

```json
{
  "erro": {
    "codigo": "matricula_duplicada",
    "mensagem": "Esta matrícula já está cadastrada na empresa."
  }
}
```

O repositório converte falhas em `RepositoryFailure`. A UI exibe a mensagem em
um SnackBar vermelho e conserva o formulário preenchido. Falhas de rede,
autenticação, servidor e JSON inválido recebem mensagens próprias, sem mostrar
HTML ou detalhes de banco.

A API continua responsável por matrícula única na empresa e sobreposição de
alocações. O frontend só atualiza a lista após confirmação do servidor e
descarta atualizações de estado se a sessão mudar durante a requisição.
Desativar envia `ativo: false`, preservando o funcionário. Encerrar alocação
envia apenas `data_fim`; trocar setor ou escala exige criar outra alocação,
preservando os vínculos históricos. Não há chamada DELETE nesses repositórios.

## Verificação

Na pasta `admin_web`:

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

Os testes Flutter cobrem o contrato HTTP com adaptadores de teste, isolamento
por empresa, erros 400/409, datas, cadastro, edição, confirmação de desativação,
carregamento, logout durante uma escrita e layout de 320 pixels. Eles não
comprovam persistência no Supabase. O backend também possui testes PostgreSQL
em `tests/test_funcionarios_api.py`, cobrindo persistência entre sessões HTTP,
desativação com histórico, permissões, isolamento, duplicidade e preflight.
`tests/test_alocacoes_api.py` cobre setores, alocações, limites de datas,
encerramento, concorrência e integração com os conflitos de escala W05.
Execute-os com `TEST_DATABASE_URL` apontando para um banco de teste isolado,
conforme o [README principal](../README.md#testes).
