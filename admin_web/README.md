# Painel administrativo Ponto Aqui

Base Flutter Web com Riverpod, Dio e go_router. Requer Flutter 3.47 ou superior
com Dart 3.13 ou superior. As versões resolvidas estão em `pubspec.lock`.

## Executar localmente

Para testar as telas com os acessos mockados, basta executar o Flutter. A API e
o Supabase não precisam estar em execução. Na raiz do repositório:

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port=3000
```

Abra `http://localhost:3000`. O painel abre no Login; após autenticar, navega para
`/dashboard`. Use **Sair** no canto superior direito para trocar de perfil e
`Ctrl+C` no terminal para parar a execução.

### Executar também a API Flask

Com a `.venv` e o `.env` preparados conforme o [README principal](../README.md),
inicie a API em outro terminal na raiz do repositório:

```powershell
.\.venv\Scripts\python.exe run.py
```

Para indicar explicitamente o endereço da API, execute na pasta `admin_web`:

```powershell
flutter run -d chrome --web-port=3000 --dart-define=API_BASE_URL=http://localhost:5000/api/web/
```

A API fica em `http://localhost:5000`. `run.py` não inicia o painel Flutter.
A porta 3000 corresponde à origem CORS do `.env.example` do backend.
Para outro domínio ou porta, ajuste
`CORS_ORIGINS` no `.env` do Flask e reinicie o backend.

`API_BASE_URL` é definida na execução/compilação e usa
`http://localhost:5000/api/web/` por padrão. Use o endereço da API Flask,
incluindo `/api/web/`. Os Services devem usar caminhos relativos como `setores`
para preservar esse prefixo. As credenciais PostgreSQL e Supabase continuam
exclusivamente no backend.

## Organização

```text
lib/
├── main.dart
├── app.dart
├── models/
│   ├── auth_session.dart
│   └── management_mock.dart
├── providers/
│   ├── api_providers.dart
│   ├── auth_provider.dart
│   └── management_mock_provider.dart
├── router/
│   ├── app_router.dart
│   └── access_policy.dart
├── services/
│   ├── auth_service.dart
│   ├── api/dio_client.dart
│   └── storage/token_storage.dart
└── views/
    ├── auth/login_view.dart
    ├── dashboard/dashboard_screen.dart
    ├── empresas/empresas_screen.dart
    ├── escalas/escalas_screen.dart
    ├── layouts/admin_scaffold.dart
    ├── layouts/sidebar.dart
    └── modules/module_placeholder_view.dart
```

`dioProvider` fornece o cliente HTTP aos futuros Services. O interceptor lê o JWT
a cada requisição pelo `tokenStorageProvider`, usando `SharedPreferencesAsync`.
O `AuthService` persiste token e perfil juntos em `saveSession()`, e o logout
remove a sessão com `clearAccessToken()`. O estado da autenticação usa Riverpod.
Requisições públicas podem
usar `Options(extra: {'skipAuth': true})`. Chamadas para outra origem são
bloqueadas antes do envio. O JWT não é registrado nos logs.

O roteador redireciona `/` para `/dashboard`, renderiza o Dashboard dentro de um
`ShellRoute` e oferece recuperação para URLs desconhecidas. O menu fica fixo em
telas a partir de 1000 pixels e passa para um Drawer em telas menores.

## Login e permissões

No modo de desenvolvimento, todos os acessos abaixo usam a senha `admin`:

| E-mail | Perfil |
| --- | --- |
| admin@teste.com | SUPERADMIN |
| rh@teste.com | RH da empresa de demonstração |
| gestor@teste.com | GESTOR da empresa de demonstração |

O AuthService gera um JWT fictício com validade de oito horas, salva o perfil e
a empresa correspondente e não faz requisições de autenticação. A sessão de teste permite navegação visual; o
interceptor bloqueia o envio desse JWT à API. O mock vem desabilitado em builds
release. Também é possível desativá-lo no desenvolvimento:

```powershell
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false
```

| Perfil | Itens disponíveis |
| --- | --- |
| SUPERADMIN | Dashboard global e Empresas; sem acesso aos módulos internos das empresas |
| RH | Dashboard, Setores, Escalas, Funcionários, Alocações, Relatórios, Equipe e Justificativas |
| GESTOR | Dashboard, Equipe e Justificativas |

O roteador verifica o perfil também ao acessar URLs diretamente. A Sidebar
oculta itens sem permissão. O `GoRouter` mantém sua instância durante mudanças
de autenticação e o `ShellRoute` preserva o layout durante a navegação entre os
módulos. O login retoma a rota solicitada quando permitida.

## Telas de demonstração

O Dashboard mostra cards diferentes por perfil: empresas e atalho de cadastro
para Superadmin; funcionários, setores e escalas ativas para RH; justificativas
pendentes para Gestor. Os números são fictícios. Os totais de empresas e escalas
ativas acompanham as alterações das listas locais; funcionários, setores e
justificativas usam valores fixos.

`/empresas` é exclusivo do Superadmin. A tabela mostra razão social, CNPJ,
administrador/RH e status. Nova Empresa e Editar abrem um formulário com validação
de campos obrigatórios, e-mail, formato e duplicidade de CNPJ. Desativar pede
confirmação e preserva a linha; o status pode ser reativado no formulário.
O atalho `/empresas/nova` abre a tabela com o modal de cadastro.
O e-mail do administrador é apenas armazenado na lista de demonstração; não cria
um usuário real nem envia convites.

`/escalas` é exclusivo do RH. A tabela mostra nome, entrada, saída, dias e status.
O formulário valida horários HH:mm, nomes duplicados e seleção de ao menos um
dia. Saída anterior à entrada representa término no dia seguinte e é indicada
na tabela. Remover pede confirmação. O formulário é semanal básico; não calcula
intervalos, carga horária legal ou escalas cíclicas.

As listas são mantidas em memória por providers e preservadas ao navegar entre
as telas. São reiniciadas ao trocar/encerrar a sessão ou recarregar o navegador.
Toda escala recebe o `empresa_id` da sessão, e escritas para outra empresa são
bloqueadas também no provider. Essas operações não utilizam Dio nem alteram o
Supabase. Setores com mapa e Funcionários ficam para a próxima etapa.

## Contrato preparado para a API Flask

**Os endpoints abaixo estão implementados no backend.** Atualize o banco e
cadastre a conta conforme o [guia W01](../docs/W01-auth.md). O cliente envia
`POST /api/web/auth/login` com este corpo:

```json
{"email": "usuario@empresa.com", "senha": "senha-do-usuario"}
```

Resposta HTTP 200 esperada:

```json
{
  "access_token": "JWT_ASSINADO_PELO_FLASK_COM_EXP",
  "usuario": {
    "id": "UUID_DO_USUARIO",
    "nome": "Nome do usuário",
    "email": "usuario@empresa.com",
    "papel": "RH",
    "empresa_id": "UUID_DA_EMPRESA"
  }
}
```

`GET /api/web/auth/me`, com Bearer JWT, deve retornar o objeto `usuario` no mesmo
formato. Ao recarregar a página com sessão real, o AuthService consulta esse
endpoint para confirmar o perfil em vez de confiar nos privilégios do cache.
Tokens expirados, respostas 401/403 e perfis sem acesso não abrem o painel.
São aceitos os nomes dos papéis em maiúsculas e os valores atuais do enum Flask.
RH e Gestor exigem `empresa_id`; Superadmin pode ter contexto global.

A autorização e os filtros de empresa continuam obrigatórios no backend.
O e-mail é único globalmente; a API obtém a empresa pelo usuário autenticado.
Somente Superadmin tem `empresa_id` nulo. Empresa inativa impede login e
restauração da sessão. Os cadastros das telas continuam mockados nesta etapa.

## Verificação e compilação

```powershell
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=https://SUA_API/api/web/
```

Os testes simulam o transporte HTTP e cobrem envio do JWT, troca/remoção da sessão,
chamadas públicas, bloqueio de destinos externos e tokens mockados, falhas de
armazenamento, login/logout, expiração, confirmação de perfil no servidor,
RBAC no menu e nas URLs, persistência do Shell/Sidebar, cards por perfil,
cadastro/edição/desativação de empresas, cadastro/edição/remoção de escalas,
validação dos formulários, isolamento ao trocar de empresa, layout compacto e
recuperação de rota desconhecida. Não acessam o Supabase online.

A compilação gera `build/web/`. Como as URLs usam caminhos sem `#`, configure a
hospedagem para servir `index.html` quando uma rota como `/dashboard` não
corresponder a um arquivo. Sirva o painel e a API com HTTPS em produção e permita
a origem do painel na configuração CORS do Flask.
