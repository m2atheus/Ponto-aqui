<div align="center">

  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="admin_web/assets/brand/ponto_aqui_logo_dark.png">
    <img src="admin_web/assets/brand/ponto_aqui_logo_transparent.png" alt="Logo Ponto Aqui" width="360">
  </picture>

  <h1>Ponto Aqui</h1>

  <p><strong>Sua equipe. Seu tempo. Tudo no lugar.</strong></p>
  <p>Controle de ponto e jornada com operação offline, histórico preservado e gestão de múltiplas empresas.</p>

  <!-- Badges de build e licença são placeholders; não representam CI ou licença já publicados. -->
  <p>
    <img src="https://img.shields.io/badge/build-n%C3%A3o%20configurado-lightgrey" alt="Build: placeholder">
    <img src="https://img.shields.io/badge/license-MIT%20(proposta)-lightgrey" alt="Licença MIT: proposta pendente de formalização">
    <img src="https://img.shields.io/badge/Flutter-Web%20%26%20Mobile-02569B?logo=flutter&amp;logoColor=white" alt="Flutter Web e Mobile">
    <img src="https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python&amp;logoColor=white" alt="Python 3.11 ou superior">
    <img src="https://img.shields.io/badge/PostgreSQL-Supabase-4169E1?logo=postgresql&amp;logoColor=white" alt="PostgreSQL no Supabase">
  </p>

  <p>
    <a href="#installation">Começar agora</a> ·
    <a href="#features">Regras de negócio</a> ·
    <a href="docs/PROMPT-MOBILE.md">Integração mobile</a>
  </p>

</div>

## The problem

Uma jornada de trabalho não deveria se perder por falta de sinal. Ainda assim, equipes em campo enfrentam conexões instáveis, registros dispersos e processos manuais de fechamento.

Para o RH, conferir horários, investigar uma marcação suspeita e reconstruir mudanças de escala torna-se difícil quando o histórico pode ser sobrescrito. Em operações com várias empresas, também é essencial impedir que dados de uma organização apareçam para outra.

O Ponto Aqui enfrenta esses desafios: continuidade da operação offline, evidências de localização e foto, decisões auditáveis e isolamento dos dados de cada empresa.

## This solution

O sistema conecta três frentes por uma API central. Web e mobile consomem a API; o acesso ao PostgreSQL e as decisões de negócio ficam no backend.

| Frente | Responsabilidade | Tecnologias |
| --- | --- | --- |
| **Backend** | Autenticar, isolar empresas, validar políticas e jornadas, persistir marcações e preservar o histórico. | Flask, SQLAlchemy, Flask-Migrate, JWT e PostgreSQL no Supabase. |
| **Mobile** | Registrar ponto, capturar localização e selfie, manter a fila offline e sincronizar com idempotência. Suporta aparelho pessoal e modo relógio compartilhado. | Flutter, armazenamento local e integração HTTP com a API. |
| **Web Admin** | Administrar empresas, funcionários, setores e escalas; realizar transferências; acompanhar a equipe e analisar o espelho de ponto. | Flutter Web, Riverpod, Dio, go_router e flutter_map. |

**Organização dos repositórios:** esta base contém a API Flask e o painel em `admin_web/`. O aplicativo mobile é desenvolvido em um repositório separado; seus contratos de integração estão em [docs/PROMPT-MOBILE.md](docs/PROMPT-MOBILE.md).

No backend, `create_app()` inicializa a aplicação, Blueprints separam os canais e a **Service Layer** concentra consultas, validações e regras de negócio. As rotas recebem a requisição e devolvem JSON com o status HTTP.

```text
app/          API: modelos, serviços, rotas e middleware
admin_web/    Painel administrativo Flutter Web
migrations/   Evolução versionada do banco
tests/        Testes do backend
docs/         Contratos e guias técnicos
run.py        Entrada da API em desenvolvimento
```

## Table of Contents

- [The problem — O problema](#the-problem)
- [This solution — A solução](#this-solution)
- [Installation — Instalação](#installation)
  - [Pré-requisitos](#pré-requisitos)
  - [Backend](#backend)
  - [Web Admin](#web-admin)
  - [Mobile](#mobile)
  - [Validação e documentação](#validação-e-documentação)
- [Features — Regras de negócio](#features)
- [Contributors & License](#contributors-license)

## Installation

### Pré-requisitos

- Python **3.11 ou superior**.
- Flutter com Dart **3.13 ou superior**, conforme `admin_web/pubspec.yaml`.
- Chrome para executar o painel Web.
- Projeto Supabase com acesso à conexão PostgreSQL e à senha do banco.
- Para o mobile: projeto do aplicativo e dispositivo ou emulador configurado.

Na pasta raiz deste repositório, confira as ferramentas:

```powershell
python --version
flutter doctor
```

Os comandos principais abaixo usam **Windows/PowerShell**, sem exigir a ativação da `.venv`. Há uma alternativa Linux/macOS ao final da configuração do backend.

### Backend

**1. Instale as dependências e prepare o ambiente local.**

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
```

**2. Configure o PostgreSQL e o JWT no `.env`.**

No Supabase, abra **Connect → Session pooler** e preencha os dados da conexão:

```dotenv
DATABASE_URL=
DATABASE_HOST=SEU_HOST_DO_POOLER
DATABASE_PORT=5432
DATABASE_NAME=postgres
DATABASE_USER=postgres.SEU_PROJECT_REF
DATABASE_PASSWORD='SUA_SENHA_DO_BANCO'

JWT_SECRET_KEY=COLE_AQUI_UM_SEGREDO_GERADO
CORS_ORIGINS=http://localhost:3000

# Opcionais: habilitam o SDK HTTP do Supabase.
SUPABASE_URL=
SUPABASE_KEY=
```

Gere o segredo JWT e copie o resultado para `JWT_SECRET_KEY`:

```powershell
.\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(48))"
```

Mantenha `DATABASE_URL` vazia para usar os campos separados. Se preferir uma URL PostgreSQL completa, ela tem precedência; caracteres especiais da senha precisam ser codificados nessa URL. Nos campos separados, use a senha original.

`SUPABASE_URL=https://SEU_PROJECT_REF.supabase.co` e a chave publicável pertencem ao SDK HTTP: **não substituem a conexão PostgreSQL** usada pelo SQLAlchemy e pelas migrations. O `.env` e a pasta `instance/` permanecem fora do versionamento.

**3. Aplique as migrations e crie o primeiro Superadmin.**

```powershell
.\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade heads
.\.venv\Scripts\python.exe -m flask --app app:create_app criar-superadmin --email admin@suaempresa.com --gerar-senha
```

O primeiro comando prepara o banco configurado no `.env`. O segundo informa o caminho de `instance/primeiro-acesso-superadmin-*.txt`, onde estarão as credenciais geradas. Se a conta já existir, use suas credenciais atuais; o comando não redefine a senha.

**4. Inicie a API e mantenha o terminal aberto.**

```powershell
.\.venv\Scripts\python.exe run.py
```

A API estará disponível em **http://localhost:5000**. Confira a resposta JSON em **http://localhost:5000/api/web/**.

<details>
<summary>Alternativa para Linux/macOS</summary>

Prepare o ambiente na raiz do repositório:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
test -f .env || cp .env.example .env
.venv/bin/python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Preencha o `.env` conforme o exemplo acima. Em seguida:

```bash
.venv/bin/python -m flask --app app:create_app db upgrade heads
.venv/bin/python -m flask --app app:create_app criar-superadmin --email admin@suaempresa.com --gerar-senha
.venv/bin/python run.py
```

</details>

### Web Admin

Em **outro terminal**, partindo da raiz do repositório:

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false
```

Abra **http://localhost:3000** e entre com a conta real de Superadmin. Cadastre a empresa e seu responsável RH; depois, use a conta RH para gerenciar funcionários, setores, escalas e alocações. O acesso dos funcionários ao app também é gerado pelo RH.

O endereço padrão é `http://localhost:5000/api/web/`. Para usar outro backend:

```powershell
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false --dart-define=API_BASE_URL=https://SUA_API/api/web/
```

Inclua a origem do painel em `CORS_ORIGINS` e reinicie a API após alterar o `.env`. A demonstração visual pode ser habilitada com `ENABLE_MOCK_AUTH=true`; ela não substitui uma conta real para operações no banco.

### Mobile

Abra **a pasta do projeto mobile, no repositório separado**, e execute:

```bash
flutter pub get
flutter devices
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000 --dart-define=ALLOW_DEV_HTTP=true
```

Esse exemplo usa um emulador Android com a API executando no mesmo computador. `10.0.2.2` aponta para o host do emulador. Para outro ambiente, configure o endereço acessível da API; em produção, utilize HTTPS.

O mobile usa a **raiz da API**, sem o sufixo `/api/web/`. Não configure credenciais PostgreSQL ou chaves administrativas do Supabase no aplicativo.

**Primeiro acesso:** o RH cria o funcionário, gera sua conta, autoriza o `device_uuid` e configura seus vínculos de setor/escala. O aplicativo realiza login e uma carga inicial válida com internet antes de depender do cache offline. Não há autocadastro no app.

### Validação e documentação

Backend, na raiz do projeto:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
```

Os testes de integração PostgreSQL exigem `TEST_DATABASE_URL` apontando para um banco de teste preparado para criar schemas e assumir o papel `pg_read_all_data`. Sem essa variável, esses testes são ignorados.

Painel, na pasta `admin_web`:

```bash
flutter analyze
flutter test
```

| Assunto | Referência |
| --- | --- |
| Autenticação e permissões | [W01 — Auth](docs/W01-auth.md) |
| Setores e mapa | [W02 — Web Admin](docs/W02-admin-web.md) |
| Alocações e transferências | [Regras de alocação](docs/ALOCACOES.md) |
| Escalas e conflitos | [Fundação W04–W07](docs/W04-W07-fundacao.md) |
| Feriados, afastamentos e apuração | [Espelho histórico](docs/W06-espelho.md) |
| Autorização de aparelhos compartilhados | [W07 — Dispositivos](docs/W07-dispositivos-admin.md) |
| Carga inicial do aplicativo | [W08 — Sync](docs/W08-sync.md) |
| Lotes offline e selfies | [W09 — API de ponto](docs/W09.md) |
| Deploy com build local e Portainer | [Azure](docs/DEPLOY-AZURE.md) |

## Features

| Regra | Comportamento |
| --- | --- |
| **W01 — Empresas e autenticação** | JWT com validade, senhas com hash e erro de login genérico. Empresas inativas não permitem login. O `empresa_id` vem da sessão autenticada e restringe as operações. Superadmin administra empresas e contas RH; não recebe acesso irrestrito aos dados internos. |
| **W02 — Geofencing e políticas** | Setores definem centro, raio positivo, exigência de selfie, dispensa de localização e ação fora do perímetro: bloquear ou deixar pendente. A distância é calculada no servidor. Setores com alocações não podem ser excluídos. |
| **W03 — Funcionários e histórico** | Matrícula única por empresa. Transferir encerra o vínculo anterior e cria outro em uma transação; uma falha desfaz ambos. O fim pode permanecer nulo. Mudanças realizadas por Gestores exibem advertência sobre o impacto no espelho. |
| **W04/W05 — Escalas e conflitos** | Modelos 5x2, Diurno, 12x36 e 24x72, projeção de ciclos e virada da meia-noite. Conflitos consideram os intervalos reais em todos os setores. Horários contíguos são permitidos; vínculos indeterminados usam horizonte explícito de validação de dez anos. |
| **W06 — Feriados e afastamentos** | Feriados por empresa/setor e afastamentos com validação de sobreposição. O espelho considera a alocação histórica vigente e os abonos aplicáveis a cada dia. |
| **W07 — Dispositivos autorizados** | Aparelhos pessoais e compartilhados, com vínculos e permissões por usuário/setor. Dispositivos inativos são bloqueados; a revogação preserva as marcações anteriores. |
| **W08 — Carga inicial** | Sincronização protegida por JWT e `X-Device-UUID`, com horário UTC do servidor, modo de operação e dados autorizados para uso offline. Ausência de alocação recebe resposta informativa, sem erro interno. |
| **W09 — Sincronização offline** | UUID gerado no aparelho garante idempotência do lote. A API preserva horário original, desvio de relógio, indicação offline e horário de recebimento. Selfies usam upload separado associado à marcação. |
| **Imutabilidade do ponto** | `registros_ponto` não recebe UPDATE nem DELETE. Inserções manuais, correções, aprovações e invalidações usam contra-registros em `justificativas_ajustes`, mantendo o original e o histórico das decisões. |
| **Experiência do painel** | Layout responsivo, tema claro/escuro persistido, pesquisa por nome/matrícula e seletores assíncronos com debounce. Atualizações automáticas respeitam a visibilidade da aplicação. |

As regras ficam no backend: validações e controles visuais do Flutter ajudam o usuário, mas não substituem a autorização e a verificação no servidor.

<a id="contributors-license"></a>

## Contributors & License

### Contributors

Contribuições são bem-vindas: melhorias de acessibilidade, testes, documentação e relatos de problemas ajudam a evoluir o projeto.

Antes de enviar uma alteração, descreva o problema e o comportamento esperado, mantenha as regras na Service Layer e execute as verificações da área modificada. Não inclua `.env`, tokens, credenciais nem dados reais de funcionários em commits ou exemplos.

<!-- Adicione aqui os nomes e perfis dos contribuidores do projeto. -->

### License

A licença ainda não foi formalizada neste repositório. **MIT é a proposta indicada pelo badge deste modelo**; sua adoção deve ser confirmada com a inclusão do arquivo `LICENSE` e a identificação dos titulares dos direitos autorais.

Organização da documentação inspirada no [README do Downshift](https://github.com/downshift-js/downshift#readme).
