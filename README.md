# Ponto Aqui — API de controle de jornada

Base Flask com Application Factory, PostgreSQL/Supabase e separação entre
transporte HTTP e regras de negócio. Requer Python 3.11 ou superior.

## Etapa implementada

- `app/__init__.py`: factory, SQLAlchemy, Migrate, JWT e CORS.
- `app/supabase_client.py`: SDK oficial Supabase, com cliente por contexto Flask.
- `app/models.py`: Empresas, Usuarios, Setores, Escalas, Alocacoes,
  RegistrosPonto e JustificativasAjustes.
- `app/routes/`: Blueprints web/mobile e endpoints de status da aplicação/Supabase.
- `app/services/`: informações da aplicação e diagnóstico HTTP do Supabase.
- `migrations/`: migration inicial com enums, constraints e triggers.
- `tests/`: configuração da aplicação e testes reais de persistência PostgreSQL.

Services e endpoints do domínio aguardam a próxima etapa. Login, emissão de tokens,
batidas e aprovação de ajustes ainda não estão implementados.

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

**Empresas:** todas as entidades dependentes têm `empresa_id` obrigatório.
Chaves estrangeiras compostas impedem associar usuários, setores, escalas,
alocações, registros e ajustes de empresas diferentes. Os relacionamentos ORM
são somente para leitura; os Services persistirão os IDs explicitamente.
O papel Superadmin permanece vinculado a uma empresa.

Essas constraints protegem os vínculos. O filtro de leitura por `empresa_id`
extraído do JWT será obrigatório nos Services e ainda não foi implementado.

**Supabase:** a migration habilita RLS nas sete tabelas, sem políticas de acesso
para `anon`/`authenticated`, bloqueando acesso direto pelas APIs públicas do
Supabase. Esta etapa pressupõe uma conexão exclusiva do backend com papel
confiável que seja proprietário das tabelas ou tenha `BYPASSRLS`, como a conexão
PostgreSQL de servidor fornecida pelo Supabase. Essa credencial permanece no
backend. A autorização por empresa será feita pelos Services; os tokens emitidos
por Flask-JWT-Extended não serão utilizados como tokens Supabase.

**Escalas:** configurações semanais ou cíclicas ficam em JSONB, com carga semanal
e tolerância em minutos. O banco exige um objeto JSON; o formato de dias, horários,
intervalos e ciclos será validado e versionado no EscalaService. A alocação
identifica funcionário, setor, escala e vigência. Validação de sobreposições e
vigência no horário da batida pertence ao Service.

**Ponto:** uma batida está vinculada a uma alocação do mesmo funcionário, setor e
empresa. `enviado_por_id` identifica o usuário autenticado que enviou o evento,
permitindo o futuro fluxo de relógio compartilhado. A autorização para enviar em
nome de outra pessoa será implementada no Service.

`ocorrido_em` preserva o instante do dispositivo; `recebido_em` é preenchido pelo
PostgreSQL na inserção. Ambos usam timezone, e o offset original é armazenado
separadamente. O Service exigirá timezone explícito no payload e trabalhará em UTC.

`evento_cliente_id` é um UUID criado no dispositivo antes de entrar na fila
offline, e permanece igual em retransmissões. A combinação de empresa, funcionário
e evento é única no banco. O SHA-256 em `payload_hash` será calculado pelo backend
sobre o conteúdo canônico do evento. O Service tratará conflitos da chave única
retornando a batida existente, ou rejeitando a reutilização da chave com outro
conteúdo. Este tratamento e o processamento do lote ainda não estão implementados.

**Perímetro:** setores possuem centro e raio. Cada batida preserva um snapshot do
perímetro e da distância calculada, mantendo a evidência mesmo após alterações no
setor. As constraints verificam os limites das coordenadas e a consistência da
distância declarada. O cálculo geográfico real será feito no GeofencingService.

**Imutabilidade:** os triggers bloqueiam UPDATE, DELETE e TRUNCATE, inclusive por
SQL direto e operações em lote. Eventos ORM também rejeitam alterações e exclusões.
O usuário do banco utilizado em runtime não deve remover/desabilitar triggers;
operações administrativas de DDL têm poderes para alterar essa proteção.

**Ajustes:** `registro_ponto_id` preenchido representa retificação; vazio representa
uma batida esquecida. O vínculo com um ponto existente exige a mesma empresa e
funcionário. A decisão exige autor e horário. O cálculo da jornada combinará os
registros originais com os ajustes aprovados, preservando os originais. Autorização,
transições de aprovação e resolução de ajustes sucessivos pertencem ao Service.

## Testes

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

## Painel administrativo Web

O projeto Flutter está em [`admin_web/`](admin_web/README.md), separado da aplicação
Flask. Inclui Riverpod, Dio com interceptor JWT, Login, controle de acesso por
perfil e `ShellRoute` com menu responsivo. Para testar a navegação em desenvolvimento,
use `admin@teste.com` / `admin`. O mock é desabilitado em builds release.
Os endpoints Flask de autenticação e os CRUDs ficam para etapas posteriores;
o contrato esperado está documentado no README do painel.

Com o backend em execução, inicie o painel em outro terminal:

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=API_BASE_URL=http://localhost:5000/api/web/
```

Consulte o README do painel para testes, compilação e configuração de hospedagem.
