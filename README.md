# Ponto Aqui

API Flask/PostgreSQL no Supabase e painel administrativo Flutter Web.

## Antes de começar

- Instale Python 3.11+, Flutter com Dart 3.13+ e Google Chrome.
- Tenha um projeto Supabase e a senha do banco PostgreSQL.
- Abra o projeto no VS Code e use o terminal PowerShell na raiz, onde está `run.py`.

<<<<<<< Updated upstream
Os comandos deste guia usam Windows/PowerShell. Abra o terminal na raiz deste
repositório. Para conferir o ambiente Flutter, execute `flutter doctor`.

## Início rápido: usar o banco real

O login e o cadastro de empresas usam a API por padrão. Configure o `.env`
conforme a seção [Configuração no Windows / PowerShell](#configuração-no-windows--powershell).
Na raiz, atualize o banco e inicie a API:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade
.\.venv\Scripts\python.exe run.py
```

Se ainda não existir um Superadmin real, crie-o uma única vez em outro terminal:

```powershell
.\.venv\Scripts\python.exe -m flask --app app:create_app criar-superadmin --email admin@teste.com --gerar-senha
```

O comando informa o caminho `instance/primeiro-acesso-superadmin-*.txt`, com o
e-mail e a senha forte gerada. Essa pasta não é versionada. A senha **não é
`admin`**. Uma conta existente nunca é sobrescrita pelo comando.

Com o Flask em execução, abra outro terminal na raiz:

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false
```

Abra `http://localhost:3000`. O Login será exibido; após entrar, você acessa o
Dashboard do seu perfil. Use a conta real e a senha escolhida/gerada.
Para parar a execução, pressione `Ctrl+C` no terminal. Reinicie Flask e Flutter
depois de atualizar o código; recarregar apenas o navegador não atualiza os processos.

Empresas são gravadas no Supabase e consultadas novamente ao carregar a tela.
O cadastro exige nome, e-mail e senha inicial do RH: a API cria essa conta
junto com a empresa, na mesma transação. A edição e a desativação também são
persistidas. Outras sessões conectadas à mesma API consultam esses dados.

### Demonstração opcional, sem gravação de empresas

Para testar a navegação sem API, habilite explicitamente o mock:

```powershell
cd admin_web
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=true
```

Somente nesse modo, todos os acessos abaixo usam a senha **`admin`**:

| E-mail | Perfil | O que testar |
| --- | --- | --- |
| admin@teste.com | SUPERADMIN | Navegação de Superadmin; gravação de empresas desabilitada |
| rh@teste.com | RH | Dashboard da empresa e cadastro, edição e remoção de escalas |
| gestor@teste.com | GESTOR | Dashboard com justificativas pendentes e navegação dos módulos permitidos |

Use **Sair** no canto superior direito para trocar de perfil. Os acessos mockados
ficam desabilitados por padrão, inclusive em desenvolvimento.
O JWT fictício não é enviado à API.

Escalas ainda usam dados em memória, reiniciados ao trocar/encerrar a sessão
ou recarregar a página. Empresas exigem sessão real; o mock não simula sucesso
de um cadastro no banco.

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

O backend oferece login real e cadastro de empresas/RH. Os CRUDs dos demais
cadastros ainda estão pendentes. Para aplicar a migration, criar a primeira
conta e testar o login real, siga o
[guia W01](docs/W01-auth.md). O contrato está no
[README do painel](admin_web/README.md#contrato-preparado-para-a-api-flask).

## Funcionalidades disponíveis

| Área | Implementado nesta etapa |
| --- | --- |
| Login e navegação | Sessão local, perfis SUPERADMIN/RH/GESTOR, Sidebar responsiva e bloqueio de URLs sem permissão |
| Dashboard | Empresas e atalho de cadastro para Superadmin; funcionários, setores e escalas ativas para RH; alerta de justificativas para Gestor |
| Empresas | `DataTable`, cadastro persistente de empresa e RH via Dio/Flask, edição, desativação confirmada e reativação |
| Escalas | `DataTable`, cadastro/edição de nome, entrada, saída, dias e status; validação de horários e remoção confirmada |
| API | Factory, SDK Supabase, login JWT real, consulta da sessão, status e sincronização W09 com upload separado de selfies |
| Banco | Modelos, migrations, dispositivos, selfies, chaves por empresa, RLS e proteção de imutabilidade dos registros de ponto |

Superadmin gerencia empresas e não acessa seus módulos internos. Escalas são
exclusivas do RH e usam a empresa da sessão. O Gestor acessa Dashboard, Equipe e
Justificativas; as duas últimas ainda possuem páginas provisórias.

O total de empresas vem do banco. Escalas ativas acompanham a lista local;
funcionários, setores e justificativas ainda usam valores de demonstração.
Escalas noturnas indicam saída no dia seguinte. O formulário atual é semanal
básico, sem cálculo de intervalos ou escalas cíclicas.

### Próximas etapas

- CRUD de Funcionários e CRUD de Setores com mapa e geofencing.
- Persistência de Escalas, Setores, Funcionários e Alocações via Services e rotas Flask.
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
=======
Confira as instalações:

```powershell
python --version
flutter doctor
```

## 1. Instalar o backend

Execute uma vez:
>>>>>>> Stashed changes

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Os comandos usam o Python da `.venv`; não é necessário ativá-la.

## 2. Configurar o `.env`

Crie o arquivo sem sobrescrever uma configuração existente:

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
.\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(48))"
```

Copie o segredo gerado para `JWT_SECRET_KEY`. No Supabase, abra **Connect →
Session pooler** e copie host, porta, banco e usuário. Edite o `.env`:

```dotenv
DATABASE_URL=
DATABASE_HOST=HOST_DO_POOLER
DATABASE_PORT=5432
DATABASE_NAME=postgres
DATABASE_USER=postgres.SEU_PROJECT_REF
DATABASE_PASSWORD='SUA_SENHA_DO_BANCO'
JWT_SECRET_KEY=SEGREDO_GERADO
CORS_ORIGINS=http://localhost:3000
```

Substitua os exemplos pelos seus dados. Use a senha original do banco entre
aspas. Deixe `DATABASE_URL` vazia para usar os campos acima. Se ela já estiver
preenchida com uma conexão PostgreSQL válida, terá prioridade.

`SUPABASE_URL` e `SUPABASE_KEY` são opcionais para o SDK HTTP. A URL
`https://SEU_PROJECT_REF.supabase.co` não substitui a conexão PostgreSQL.

## 3. Preparar as tabelas

Com o `.env` salvo, execute:

```powershell
.\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade
```

O comando cria ou atualiza as tabelas no banco configurado no `.env`, aplicando
as migrations existentes. Execute novamente quando houver novas migrations.
Não é necessário executar `db init`.

## 4. Iniciar a API — terminal 1

```powershell
.\.venv\Scripts\python.exe run.py
```

Abra **http://localhost:5000/**: deve aparecer um JSON com informações da API.
Mantenha esse terminal aberto.

## 5. Iniciar o painel — terminal 2

<<<<<<< Updated upstream
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
Os testes de empresas verificam transação empresa/RH, senha com hash, duplicidade,
edição/desativação e consulta por sessões HTTP independentes. O Flutter verifica
consulta após reiniciar os providers, falha da API sem cadastro local e bloqueio
do mock para gravações reais.

## Testes e compilação do painel

Na raiz do projeto:
=======
Abra outro terminal na raiz do projeto:
>>>>>>> Stashed changes

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port=3000
```

O painel abre em **http://localhost:3000** e usa a API em
`http://localhost:5000/api/web/` por padrão.

### Entrar para testar as telas

Todos os acessos abaixo usam a senha **`admin`**:

| E-mail | Perfil |
| --- | --- |
| admin@teste.com | Superadmin |
| rh@teste.com | RH |
| gestor@teste.com | Gestor |

Esses acessos são de demonstração e também funcionam sem API. Os cadastros de
Empresas e Escalas ficam em memória e somem ao recarregar a página.

### Entrar com uma conta real

Se ainda não tiver uma conta, siga o
[passo a passo para criar o primeiro Superadmin](docs/W01-auth.md#criar-a-primeira-conta-para-testar).
Depois, pare o Flutter com `Ctrl+C` e execute na pasta `admin_web`:

```powershell
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false
```

Entre com o e-mail e a senha cadastrados no banco. O login real ainda não
ativa a persistência dos formulários de Empresas e Escalas.

## Nas próximas execuções

Com a instalação pronta, basta abrir dois terminais na raiz do projeto:

**Terminal 1 — API:**

```powershell
.\.venv\Scripts\python.exe run.py
```

**Terminal 2 — painel:**

```powershell
cd admin_web
flutter run -d chrome --web-port=3000
```

Para login real, acrescente `--dart-define=ENABLE_MOCK_AUTH=false` ao comando
Flutter. Para parar cada aplicação, use `Ctrl+C` no respectivo terminal.

## Problemas comuns

| Problema | O que fazer |
| --- | --- |
| `python` ou `flutter` não encontrado | Confira a instalação e o PATH; reabra o terminal. |
| Falha ao executar `db upgrade` | Confira os campos de conexão e a senha do banco no `.env`. |
| Painel não conecta à API | Mantenha o Flask aberto e confira `CORS_ORIGINS=http://localhost:3000`. Reinicie a API após alterar o `.env`. |
| Login real usa o acesso de demonstração | Reinicie o Flutter com `--dart-define=ENABLE_MOCK_AUTH=false`. |
| Cadastro desaparece ao atualizar | Os formulários atuais usam dados em memória; a integração dos CRUDs está pendente. |

## Testes — opcional

Na raiz do projeto:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
```

Para os testes PostgreSQL, configure `TEST_DATABASE_URL` com um banco de teste
com permissão para criar schemas e assumir o papel `pg_read_all_data`.
Sem essa variável, os testes que precisam de banco são ignorados.

Na pasta `admin_web`:

```powershell
flutter analyze
flutter test
```

## Guias técnicos

- [Painel Flutter, organização e compilação](admin_web/README.md).
- [W01–W03: autenticação, empresas e funcionários](docs/W01-auth.md).
- [W04–W07: escalas, conflitos e dispositivos](docs/W04-W07-fundacao.md).
- [W09: marcações offline e selfies](docs/W09.md).

O motor de conflitos, a auto-revogação de aparelhos e o decorator mobile estão
implementados como Services/middleware; a integração às rotas e ao login está
pendente. A API atual oferece autenticação JWT e sincronização de ponto offline.
