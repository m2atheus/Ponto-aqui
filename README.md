# Ponto Aqui

Sistema de controle de ponto e jornada com API Flask, banco PostgreSQL no
Supabase e painel administrativo Flutter Web.

Este guia acompanha a primeira instalação e mostra como iniciar o projeto
nas próximas vezes. Os comandos usam **Windows e PowerShell**.

[Primeira execução](#primeira-execução) · [Uso diário](#uso-diário) ·
[Demonstração](#demonstração-opcional) · [Problemas comuns](#problemas-comuns)

## Antes de começar

| Requisito | Para que serve |
| --- | --- |
| Python 3.11 ou superior | Executar a API Flask. |
| Flutter com Dart 3.13 ou superior, disponível no PATH | Executar o painel Web. |
| Google Chrome | Abrir o painel em desenvolvimento. |
| Projeto Supabase e senha do banco | Armazenar os dados no PostgreSQL. |

Abra a pasta do projeto no VS Code. No terminal, confira as instalações:

```powershell
python --version
flutter doctor
```

> **Pasta de trabalho:** os comandos do backend devem ser executados na raiz
> do projeto, onde estão `run.py` e `requirements.txt`. Os comandos do Flutter
> devem ser executados em `admin_web`.

## Primeira execução

### 1. Instalar as dependências da API

Na raiz do projeto:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

A `.venv` mantém as dependências Python deste projeto separadas das demais.
Usaremos seu executável diretamente, sem precisar ativar o ambiente.

### 2. Configurar a conexão e a autenticação

Crie o arquivo de configuração local:

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
```

No Supabase, abra **Connect → Session pooler**. Copie host, porta, banco e
usuário para o `.env`. Use a senha do banco criada no Supabase:

```dotenv
DATABASE_URL=
DATABASE_HOST=HOST_DO_POOLER
DATABASE_PORT=5432
DATABASE_NAME=postgres
DATABASE_USER=postgres.SEU_PROJECT_REF
DATABASE_PASSWORD='SUA_SENHA_DO_BANCO'
JWT_SECRET_KEY=SEU_SEGREDO_JWT
CORS_ORIGINS=http://localhost:3000
```

Substitua os exemplos pelos seus dados. A senha recebe seu valor original
entre aspas; mantenha `DATABASE_URL` vazia para usar os campos separados.
Uma URL PostgreSQL válida já preenchida em `DATABASE_URL` tem prioridade.

Se `JWT_SECRET_KEY` estiver vazia, gere um segredo e copie o resultado para ela:

```powershell
.\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(48))"
```

O segredo assina os tokens de login. Guarde-o no `.env` e mantenha o mesmo
valor nas próximas execuções. O arquivo `.env` não é versionado.

> **Conexão PostgreSQL e SDK:** `SUPABASE_URL` e `SUPABASE_KEY` são opcionais
> para o SDK HTTP. A URL `https://SEU_PROJECT_REF.supabase.co` pertence ao SDK;
> os modelos e migrations usam a conexão PostgreSQL configurada acima.

### 3. Criar ou atualizar as tabelas

Salve o `.env` e execute:

```powershell
.\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade heads
```

As migrations aplicam a estrutura do sistema no banco configurado no `.env`.
O argumento `heads` contempla todas as ramificações existentes neste
repositório. A configuração inicial das migrations já está pronta.

### 4. Criar o primeiro Superadmin

Se você já possui uma conta real, avance para o próximo passo. Caso contrário:

```powershell
.\.venv\Scripts\python.exe -m flask --app app:create_app criar-superadmin --email admin@teste.com --gerar-senha
```

O comando cria a conta e informa o caminho de um arquivo como
`instance/primeiro-acesso-superadmin-*.txt`. Abra o arquivo indicado para
consultar o e-mail e a senha gerada. A pasta `instance` não é versionada.

Use essa senha para entrar no painel. A senha `admin` é exclusiva da
demonstração. Uma conta existente mantém suas credenciais.

### 5. Iniciar a API

No **terminal 1**, na raiz do projeto:

```powershell
.\.venv\Scripts\python.exe run.py
```

Abra **http://localhost:5000/**. Um JSON com informações da API confirma
que o servidor iniciou. Deixe esse terminal aberto.

### 6. Iniciar o painel

Abra o **terminal 2** na raiz do projeto:

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false
```

O painel abre em **http://localhost:3000**. Entre com a conta real do passo 4
ou com uma conta já cadastrada.

O painel usa `http://localhost:5000/api/web/` como endereço padrão da API.
O `CORS_ORIGINS` do `.env` permite que o navegador na porta 3000 acesse a API.

**Para conferir a persistência:** entre como Superadmin, cadastre uma empresa
com os dados e a senha inicial do RH e atualize a página. A empresa deve
continuar na lista: empresa e conta RH são gravadas juntas no Supabase.

## Uso diário

Após a configuração inicial, abra dois terminais na raiz do projeto:

| Terminal | Aplicação | Endereço |
| --- | --- | --- |
| 1 | API Flask | http://localhost:5000 |
| 2 | Painel Flutter Web | http://localhost:3000 |

**Terminal 1:**

```powershell
.\.venv\Scripts\python.exe run.py
```

**Terminal 2:**

```powershell
cd admin_web
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false
```

Use `Ctrl+C` no respectivo terminal para encerrar cada aplicação. Após mudar
o `.env`, reinicie a API. Após atualizar dependências ou migrations, repita
a instalação correspondente e o comando do passo 3.

## Demonstração opcional

Para explorar as telas sem iniciar a API, execute na pasta `admin_web`:

```powershell
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=true
```

| E-mail | Perfil | Senha |
| --- | --- | --- |
| admin@teste.com | Superadmin | admin |
| rh@teste.com | RH | admin |
| gestor@teste.com | Gestor | admin |

O modo de demonstração precisa ser habilitado explicitamente. Ele permite
testar a navegação e as telas, mas o cadastro de empresas exige uma sessão
real. As escalas de demonstração ficam em memória e reiniciam ao atualizar
a página ou trocar de sessão.

## Estado atual do projeto

| Módulo | Disponível |
| --- | --- |
| Login e empresas | Autenticação JWT e cadastro, edição e desativação persistidos no banco. |
| Dashboard e escalas do painel | Interface por perfil; alguns indicadores e a gestão de escalas ainda usam demonstração. |
| Escalas e dispositivos na API | Modelos, projeção noturna, motor de conflitos, revogação pessoal e decorator prontos; integração às rotas e ao login pendente. |
| Ponto offline | API de lotes idempotentes, geofencing e upload de selfies; aplicativo mobile ainda não implementado. |

## Problemas comuns

| Situação | Como resolver |
| --- | --- |
| `python` ou `flutter` não encontrado | Confira a instalação e o PATH; reabra o terminal. |
| Falha ao atualizar o banco | Confira host, usuário e senha no `.env`; use `db upgrade heads` conforme o passo 3. |
| Credenciais de login inválidas | Use a senha da conta real; consulte o arquivo indicado ao criar o Superadmin. |
| Painel não conecta à API | Confira se o terminal 1 está aberto e se `CORS_ORIGINS` permite a porta 3000. |
| Empresas indisponíveis em demonstração | Reinicie o painel com `ENABLE_MOCK_AUTH=false` e entre com uma conta real. |
| Escalas desaparecem ao atualizar | A tela de escalas ainda usa dados em memória; sua persistência será integrada à API. |

Para usar uma API em outro endereço, adicione ao comando Flutter:
`--dart-define=API_BASE_URL=https://SUA_API/api/web/`.

## Testes

**Backend — na raiz do projeto:**

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
```

Os testes PostgreSQL usam `TEST_DATABASE_URL`, com uma conexão de teste
que permita criar schemas e assumir o papel `pg_read_all_data`.
Sem essa variável, os testes que precisam de banco são ignorados.

**Painel — na pasta `admin_web`:**

```powershell
flutter analyze
flutter test
```

## Estrutura e documentação

```text
app/         API: modelos, Services, middleware e rotas
admin_web/   Painel administrativo Flutter
migrations/  Histórico de alterações do banco
tests/       Testes do backend
docs/        Guias técnicos por tarefa
run.py       Inicialização da API em desenvolvimento
```

- [Painel: organização, permissões e compilação](admin_web/README.md).
- [W01–W03: autenticação, empresas e funcionários](docs/W01-auth.md).
- [W04–W07: escalas, conflitos e dispositivos](docs/W04-W07-fundacao.md).
- [W09: marcações offline e selfies](docs/W09.md).
