# Ponto Aqui — Controle de ponto e jornada

Projeto com API Flask/PostgreSQL no Supabase e painel administrativo Flutter Web.
O backend usa Application Factory, Blueprints e Service Layer. O painel usa
Riverpod, Dio e go_router, com navegação por `ShellRoute` e controle de acesso
por perfil.

## Requisitos

| Componente | Requisito |
| --- | --- |
| Painel Web | Flutter 3.47 ou superior, com Dart 3.13 ou superior, no PATH |
| Navegador de desenvolvimento | Google Chrome |
| Backend | Python 3.11 ou superior |
| Banco do backend | PostgreSQL/Supabase com conexão configurada no `.env` |

Os comandos deste guia usam Windows/PowerShell. Abra o terminal na raiz deste
repositório. Para conferir o ambiente Flutter, execute `flutter doctor`.

## Início rápido: testar o painel

O painel de demonstração funciona sem iniciar a API e sem configurar o Supabase.
Na raiz do projeto, execute:

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port=3000
```

Abra `http://localhost:3000`. O Login será exibido; após entrar, você acessa o
Dashboard do seu perfil. Para parar a execução, pressione `Ctrl+C` no terminal.

### Acessos de teste

Todos usam a senha **`admin`**:

| E-mail | Perfil | O que testar |
| --- | --- | --- |
| admin@teste.com | SUPERADMIN | Dashboard global e cadastro, edição e desativação de empresas |
| rh@teste.com | RH | Dashboard da empresa e cadastro, edição e remoção de escalas |
| gestor@teste.com | GESTOR | Dashboard com justificativas pendentes e navegação dos módulos permitidos |

Use **Sair** no canto superior direito para trocar de perfil. Os acessos mockados
funcionam em desenvolvimento e são desabilitados por padrão em builds release.
O JWT fictício não é enviado à API.

Os dados das tabelas ficam em memória: as alterações permanecem durante a
navegação, mas são reiniciadas ao trocar/encerrar a sessão ou recarregar a página.
Cadastrar uma empresa nessa demonstração não cria uma empresa nem um usuário
real no Supabase.

## Executar o backend junto com o painel

Na primeira configuração, siga a seção
[Configuração no Windows / PowerShell](#configuração-no-windows--powershell)
para criar a `.venv`, instalar as dependências, preencher o `.env` e preparar o
banco. Se isso já foi feito, inicie o backend na raiz do repositório:

```powershell
.\.venv\Scripts\python.exe run.py
```

A API fica em `http://localhost:5000`. Mantenha esse terminal aberto e, em outro
terminal na raiz, execute:

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=API_BASE_URL=http://localhost:5000/api/web/
```

`API_BASE_URL` já usa esse endereço por padrão; o argumento acima mostra como
configurá-lo quando o endereço da API mudar. No `.env` do backend, mantenha
`CORS_ORIGINS=http://localhost:3000` para permitir essa origem. Reinicie o Flask
após mudar a configuração. `run.py` inicia somente a API; o painel deve ser
iniciado separadamente com Flutter.

O backend oferece login real; os CRUDs de cadastros ainda estão pendentes.
Iniciá-lo não ativa a persistência das telas de demonstração. Para aplicar a
migration, criar a primeira conta e testar o login real, siga o
[guia W01](docs/W01-auth.md). O contrato está no
[README do painel](admin_web/README.md#contrato-preparado-para-a-api-flask).

## Funcionalidades disponíveis

| Área | Implementado nesta etapa |
| --- | --- |
| Login e navegação | Sessão local, perfis SUPERADMIN/RH/GESTOR, Sidebar responsiva e bloqueio de URLs sem permissão |
| Dashboard | Empresas e atalho de cadastro para Superadmin; funcionários, setores e escalas ativas para RH; alerta de justificativas para Gestor |
| Empresas | `DataTable`, cadastro com razão social/CNPJ/e-mail do RH, edição, desativação confirmada e reativação pelo formulário |
| Escalas | `DataTable`, cadastro/edição de nome, entrada, saída, dias e status; validação de horários e remoção confirmada |
| API | Factory, SDK Supabase, login JWT real, consulta da sessão, status e sincronização W09 com upload separado de selfies |
| Banco | Modelos, migrations, dispositivos, selfies, chaves por empresa, RLS e proteção de imutabilidade dos registros de ponto |

Superadmin gerencia empresas e não acessa seus módulos internos. Escalas são
exclusivas do RH e usam a empresa da sessão. O Gestor acessa Dashboard, Equipe e
Justificativas; as duas últimas ainda possuem páginas provisórias.

Os números são de demonstração. Os totais de empresas e escalas ativas acompanham
as listas locais; funcionários, setores e justificativas usam valores fixos.
Escalas noturnas indicam saída no dia seguinte. O formulário atual é semanal
básico, sem cálculo de intervalos ou escalas cíclicas.

### Próximas etapas

- CRUD de Funcionários e CRUD de Setores com mapa e geofencing.
- Persistência dos cadastros via Services e rotas Flask.
- Aplicativo mobile com fila offline e fluxo de aprovação de ajustes (W10).
- Equipe, justificativas, alocações e relatórios com dados reais.

## Organização do repositório

```text
app/             # API Flask: factory, modelos, rotas e Services
admin_web/       # Painel Flutter Web: models, providers, services, router e views
migrations/      # Histórico do banco PostgreSQL
tests/           # Testes do backend
run.py           # Entrada de desenvolvimento da API
.env.example     # Exemplo das variáveis do backend
```

A estrutura detalhada do Flutter, os formulários e o contrato da API estão no
[README do painel](admin_web/README.md).

## W09: marcações offline

O backend recebe lotes por `POST /api/mobile/marcacoes/lote`, preserva a hora
do aparelho, desvio e indicador offline, e grava a hora de recebimento no banco.
O UUID impede duplicações, inclusive com envios simultâneos. Cada item recebe
a situação Aceita, Pendente de análise ou Recusada e seus motivos.

A distância é calculada no servidor. O setor pode bloquear, deixar pendente
ou ignorar a localização; desvio absoluto acima do limite (120 segundos por
padrão) exige análise. Aparelhos não autorizados geram marcações recusadas.
O upload de selfie usa `POST /api/mobile/marcacoes/{UUID}/selfie` e não altera
o registro original. Marcações e selfies não possuem edição nem exclusão.

Para atualizar uma instalação existente:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade
```

Esses endpoints exigem JWT real de funcionário, contexto de empresa e aparelho
cadastrado. O cadastro confiável de aparelhos e a emissão de tokens de teste,
o JSON do lote, os status por item e as regras de reenvio estão no
[guia W09](docs/W09.md). Os testes foram realizados em PostgreSQL local;
a migration precisa ser aplicada à sua conexão para atualizar o Supabase online.

## Configuração no Windows / PowerShell

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
.\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(48))"
```

Edite `.env`: preencha `DATABASE_URL` com a URL PostgreSQL do Supabase, ou use os
campos separados de conexão descritos abaixo. Preencha também
`JWT_SECRET_KEY` com o segredo gerado e `CORS_ORIGINS` com as origens web permitidas,
separadas por vírgula. A factory carrega o `.env` da raiz do projeto através de
python-dotenv, inclusive quando importada diretamente. Variáveis já definidas
no ambiente têm precedência sobre o arquivo; o dicionário passado a `create_app()`
tem precedência sobre ambos. Credenciais não são versionadas.

A conexão utiliza `psycopg2`. A factory acrescenta `sslmode=require` se a URL não
informar outro modo e preserva opções como `verify-full`. Para PostgreSQL local
sem TLS, informe explicitamente `?sslmode=disable`. Caracteres especiais da senha
devem ser codificados como componente de URL.

```powershell
.\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade
.\.venv\Scripts\python.exe -m flask --app app:create_app run --debug
```

Também é possível iniciar com `.\.venv\Scripts\python.exe run.py`.
O debugger fica desativado nessa entrada, salvo quando `FLASK_DEBUG=1`.

Com a aplicação em execução:

- `GET /` ou `GET /api/web/`: informações públicas da API, sem consultas externas.
- `GET /api/web/supabase/status`: verifica URL/chave no endpoint público de
  configurações do Supabase Auth, retornando JSON e HTTP 200 ou 503. Não autentica
  usuários nem consulta dados das empresas; os JWTs do domínio continuam no Flask.

O diagnóstico HTTP não verifica a conexão PostgreSQL nem a presença das tabelas.
A URL HTTP `https://SEU_PROJECT_REF.supabase.co` pertence a `SUPABASE_URL`.
Para o PostgreSQL, abra **Connect > Session pooler**, porta 5432, e escolha uma
das duas formas de configuração. A primeira usa os campos copiados do painel,
com a senha original entre aspas. Deixe `DATABASE_URL` vazia:

```dotenv
DATABASE_URL=
DATABASE_HOST=HOST_DO_POOLER
DATABASE_PORT=5432
DATABASE_NAME=postgres
DATABASE_USER=postgres.SEU_PROJECT_REF
DATABASE_PASSWORD='SUA_SENHA_ORIGINAL'
```

A factory monta uma URL SQLAlchemy com `URL.create()`, preservando caracteres
especiais na senha sem exigir codificação manual. TLS é habilitado por padrão.

A segunda forma usa a connection string PostgreSQL completa em `DATABASE_URL`,
que tem precedência sobre os campos separados. Substitua `[YOUR-PASSWORD]` pela
senha do banco com codificação de URL e adicione `sslmode=require` aos parâmetros:

```dotenv
DATABASE_URL=postgresql+psycopg2://postgres.SEU_PROJECT_REF:SENHA_CODIFICADA@HOST_DO_POOLER:5432/postgres?sslmode=require
```

A migration inicial já existe; não execute `db init` novamente. Mudanças futuras
nos modelos devem gerar migrations com `db migrate`, seguidas de revisão e
`db upgrade`. Use migrations para preparar o banco: `db.create_all()` não aplica
o histórico de migrations nem a configuração de RLS.

## SDK Supabase: configuração apresentada no painel Flask

A dependência `supabase` já está em `requirements.txt`. Para atualizar um ambiente
virtual existente, execute:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

No painel Supabase, abra **Connect > Flask (Python)** e copie a URL do projeto e
a chave publicável completas para o `.env` local:

```dotenv
SUPABASE_URL=https://SEU_PROJECT_REF.supabase.co
SUPABASE_KEY=sb_publishable_COPIE_O_VALOR_COMPLETO
```

O nome `SUPABASE_PUBLISHABLE_KEY`, usado pela documentação atual, também é aceito e
tem precedência sobre `SUPABASE_KEY`. Preencha um dos dois nomes para a chave.
Os valores de exemplo devem ser substituídos pelos valores do seu próprio projeto.

`SUPABASE_URL` e a chave configuram o SDK HTTP. A conexão PostgreSQL, através de
`DATABASE_URL` ou dos campos separados, continua necessária para os modelos
SQLAlchemy e migrations; `JWT_SECRET_KEY` configura os tokens da API. O projeto
mantém sua Application Factory e os dois Blueprints.

Se URL e chave do SDK estiverem vazias, os recursos PostgreSQL existentes continuam
funcionando. Uma configuração parcial gera uma mensagem indicando os campos
faltantes. Inicializar o SDK não faz uma requisição ao Supabase; as credenciais
online serão verificadas quando uma operação HTTP for executada.

Os Services podem obter o cliente com:

```python
from app.supabase_client import get_supabase_client

client = get_supabase_client()  # Dentro de uma requisição ou app.app_context().
```

O exemplo `supabase.table('todos').select('*')` do painel é uma demonstração de
consulta. Ele exige uma tabela `todos` exposta e permissões apropriadas. O projeto
de ponto usa seus próprios modelos e Services; a página inicial retorna JSON e
não lista dados de empresas com uma chave publicável. Todas as consultas de domínio
exigirão o `empresa_id` do JWT validado. A inicialização do guia foi adaptada para
`create_app()` e as rotas permanecem nos Blueprints.

O cliente é criado no primeiro uso dentro do contexto atual. Cada contexto tem
seu próprio cliente, com persistência e renovação automática de sessão desativadas,
e o transporte HTTP é fechado ao final. Tokens de um contexto não são compartilhados
com outros usuários. Consultas do domínio continuam na camada de Services.

A chave publicável respeita RLS. Nossas tabelas não têm políticas de leitura pública;
uma consulta pelo SDK pode retornar uma lista vazia ou um erro de permissão,
conforme os grants do projeto. Esta integração mantém as proteções existentes e
não cria permissões públicas. Os JWTs Flask não são encaminhados automaticamente
para o Supabase. Referências: [guia Flask](https://supabase.com/docs/guides/getting-started/quickstarts/flask)
e [chaves de API](https://supabase.com/docs/guides/getting-started/api-keys).

## Decisões dos modelos

**Empresas:** as entidades dependentes têm `empresa_id` obrigatório, com a
exceção da conta global de Superadmin.
Chaves estrangeiras compostas impedem associar usuários, setores, escalas,
alocações, registros e ajustes de empresas diferentes. Os relacionamentos ORM
são somente para leitura; os Services persistirão os IDs explicitamente.
Somente Superadmin tem `empresa_id` nulo. O e-mail de usuário é único globalmente.

Essas constraints protegem os vínculos. Os Services W09 filtram as consultas
por `empresa_id` extraído do JWT e pelo funcionário autenticado. Os Services
dos demais cadastros deverão manter esse isolamento.

**Supabase:** as migrations habilitam RLS nas dez tabelas, sem políticas de acesso
para `anon`/`authenticated`, bloqueando acesso direto pelas APIs públicas do
Supabase. Esta etapa pressupõe uma conexão exclusiva do backend com papel
confiável que seja proprietário das tabelas ou tenha `BYPASSRLS`, como a conexão
PostgreSQL de servidor fornecida pelo Supabase. Essa credencial permanece no
backend. Os Services W09 autorizam por empresa e funcionário; os tokens emitidos
por Flask-JWT-Extended não são utilizados como tokens Supabase.

**Escalas:** configurações semanais ou cíclicas ficam em JSONB, com carga semanal
e tolerância em minutos. O banco exige um objeto JSON; o formato de dias, horários,
intervalos e ciclos será validado e versionado no EscalaService. A alocação
identifica funcionário, setor, escala opcional e vigência. O banco impede períodos
sobrepostos para o mesmo funcionário/setor. A resposta HTTP de validação e o
encerramento de alocações serão implementados no AlocacaoService na próxima etapa.

**Funcionários:** nome, matrícula única na empresa, cargo e vínculo opcional com
uma conta. Chaves compostas preservam os vínculos entre funcionário, alocação e
conta usada nas marcações W09. Setores recebem endereço, `exige_selfie`,
`acao_fora_perimetro` e `ignorar_localizacao`; a política efetiva permanece
compatível com o geofencing W09. Os Services de cadastro serão a próxima etapa.

**Ponto:** uma batida está vinculada a uma alocação do mesmo funcionário, setor e
empresa. `enviado_por_id` identifica o usuário autenticado que enviou o evento,
permitindo o futuro fluxo de relógio compartilhado. O lote W09 aceita apenas
marcações do próprio funcionário autenticado; envio por relógio compartilhado
será implementado em outra etapa.

`ocorrido_em` preserva o instante do dispositivo; `recebido_em` é preenchido pelo
PostgreSQL na inserção. Ambos usam timezone, e o offset original é armazenado
separadamente. O Service exige timezone explícito no payload e retorna timestamps
em UTC, preservando o desvio informado e o indicador de registro offline.

`evento_cliente_id` é um UUID criado no dispositivo antes de entrar na fila
offline, e permanece igual em retransmissões. Empresa e evento formam uma chave
única no banco. O backend calcula SHA-256 em `payload_hash` sobre o conteúdo
canônico e trata conflitos retornando a batida existente, ou rejeitando a
reutilização da chave com outro conteúdo ou por outro funcionário. O lote usa
savepoints por item e só confirma recebimentos depois do commit.

**Perímetro:** setores possuem centro e raio. Cada batida preserva um snapshot do
perímetro e da distância calculada, mantendo a evidência mesmo após alterações no
setor. As constraints verificam os limites das coordenadas e a consistência da
distância calculada. O GeofencingService usa Haversine no servidor. A política
do setor e o limite de desvio também ficam preservados na marcação; uma decisão
de pendência/recusa não descarta a evidência enviada pelo aparelho.

**Imutabilidade:** os triggers bloqueiam UPDATE, DELETE e TRUNCATE, inclusive por
SQL direto e operações em lote. Eventos ORM também rejeitam alterações e exclusões.
O usuário do banco utilizado em runtime não deve remover/desabilitar triggers;
operações administrativas de DDL têm poderes para alterar essa proteção.

**Ajustes:** `registro_ponto_id` preenchido representa retificação; vazio representa
uma batida esquecida. O vínculo com um ponto existente exige a mesma empresa e
funcionário. A decisão exige autor e horário. O cálculo da jornada combinará os
registros originais com os ajustes aprovados, preservando os originais. Autorização,
transições de aprovação e resolução de ajustes sucessivos pertencem ao Service.

## Testes do backend

```powershell
.\.venv\Scripts\python.exe -m pytest -q
```

Sem `TEST_DATABASE_URL`, apenas os testes que não precisam de banco são executados;
os testes PostgreSQL ficam marcados como ignorados. Para executar todos, use uma
conexão de teste com permissão de criar schemas e assumir o papel de teste
`pg_read_all_data` (um superusuário local atende a esses requisitos):

```powershell
$env:TEST_DATABASE_URL = 'postgresql://USUARIO:SENHA@localhost:5432/BANCO_TESTE?sslmode=disable'
.\.venv\Scripts\python.exe -m pytest -q
```

Os testes criam um schema com nome aleatório, aplicam a migration nele e removem
apenas esse schema ao terminar. `DATABASE_URL` da aplicação não é reutilizada.
São verificadas as referências entre empresas, chave de idempotência, timestamps,
constraints de perímetro, imutabilidade por SQL/ORM, ajustes, bloqueio por RLS,
compatibilidade entre migration e modelos, e reversão/reaplicação da migration.
Os testes do SDK utilizam o cliente real com transporte HTTP simulado e não acessam
o projeto Supabase online; cobrem headers, isolamento de contextos e aplicações,
configuração opcional, carregamento do `.env` e fechamento das conexões HTTP.
Os campos de conexão PostgreSQL são testados com senhas que contêm caracteres
especiais, portas inválidas e precedência de `DATABASE_URL`.
Os endpoints web também são testados para evitar exposição de respostas externas
e tratar timeouts, falta de configuração e respostas inválidas com JSON estável.
Os testes W09 cobrem classificação, aparelhos, JWT, lotes mistos, isolamento de
empresa, selfies, falhas de commit e seis envios simultâneos do mesmo UUID.
Os testes W01–W03 cobrem senha com hash, erros genéricos, empresa inativa,
expiração, contrato Flutter, perfis, alocações e migração de dados legados.

## Testes e compilação do painel

Na raiz do projeto:

```powershell
cd admin_web
flutter pub get
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=https://SUA_API/api/web/
```

Substitua `https://SUA_API/api/web/` pelo endereço da API ao preparar uma publicação.
A compilação gera `admin_web/build/web/`. O mock de login fica desabilitado em
release. O login real exige banco atualizado, conta cadastrada e API em execução.

Os testes do painel cobrem autenticação, permissões por perfil, navegação,
formulários, confirmações, isolamento de empresa e telas estreitas. Para publicar,
a hospedagem precisa servir `index.html` em rotas como `/dashboard` e `/escalas`.
Veja os detalhes no [README do painel](admin_web/README.md#verificação-e-compilação).
