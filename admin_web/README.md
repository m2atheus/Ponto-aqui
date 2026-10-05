# Painel administrativo Ponto Aqui

Base Flutter Web com Riverpod, Dio e go_router. Requer Flutter 3.47 ou superior
com Dart 3.13 ou superior. As versões resolvidas estão em `pubspec.lock`.

## Executar localmente

Na raiz do repositório, inicie o backend em um terminal:

```powershell
.\.venv\Scripts\python.exe run.py
```

Em outro terminal:

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=API_BASE_URL=http://localhost:5000/api/web/
```

O painel abre no Login; após autenticar, navega para `/dashboard`. A porta 3000 corresponde à
origem CORS do `.env.example` do backend. Para outro domínio ou porta, ajuste
`CORS_ORIGINS` no `.env` do Flask e reinicie o backend.

`API_BASE_URL` é definida na execução/compilação. Use o endereço da API Flask,
incluindo `/api/web/`. Os Services devem usar caminhos relativos como `setores`
para preservar esse prefixo. As credenciais PostgreSQL e Supabase continuam
exclusivamente no backend.

## Organização

```text
lib/
├── main.dart
├── app.dart
├── models/auth_session.dart
├── providers/
│   ├── api_providers.dart
│   └── auth_provider.dart
├── router/
│   ├── app_router.dart
│   └── access_policy.dart
├── services/
│   ├── auth_service.dart
│   ├── api/dio_client.dart
│   └── storage/token_storage.dart
└── views/
    ├── auth/login_view.dart
    ├── dashboard/dashboard_view.dart
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

No modo de desenvolvimento, use `admin@teste.com` com senha `admin`. O AuthService
gera um JWT fictício com validade de oito horas, salva o perfil SUPERADMIN e não
faz requisições de autenticação. A sessão de teste permite navegação visual; o
interceptor bloqueia o envio desse JWT à API. O mock vem desabilitado em builds
release. Também é possível desativá-lo no desenvolvimento:

```powershell
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false
```

| Perfil | Itens disponíveis |
| --- | --- |
| SUPERADMIN | Todos os módulos, incluindo Cadastrar Empresa |
| RH | Dashboard, Setores, Escalas, Funcionários, Alocações, Relatórios, Equipe e Justificativas |
| GESTOR | Dashboard, Equipe e Justificativas |

O roteador verifica o perfil também ao acessar URLs diretamente. A Sidebar
oculta itens sem permissão. O `GoRouter` mantém sua instância durante mudanças
de autenticação e o `ShellRoute` preserva o layout durante a navegação entre os
módulos. O login retoma a rota solicitada quando permitida.

As páginas dos módulos ainda são provisórias: CRUDs e mapa de geofencing ficam
para as próximas etapas. Nenhuma dessas páginas consulta ou modifica dados.
Os testes de RH e Gestor usam respostas HTTP simuladas; somente o superusuário
solicitado possui credenciais mockadas na aplicação.

## Contrato preparado para a API Flask

**Os endpoints abaixo ainda não existem no backend deste repositório.** Logins
com outras credenciais dependem da implementação desses endpoints. O cliente
espera `POST /api/web/auth/login` com este corpo:

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
Como o modelo atual permite o mesmo e-mail em empresas diferentes, o contrato
definitivo de autenticação deverá identificar a empresa quando houver ambiguidade.
Não haverá escolha silenciosa de um usuário pela primeira ocorrência do e-mail.

## Verificação e compilação

```powershell
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=https://SUA_API/api/web/
```

Os testes simulam o transporte HTTP e cobrem envio do JWT, troca/remoção da sessão,
chamadas públicas, bloqueio de destinos externos e tokens mockados, falhas de
armazenamento, login/logout, expiração, confirmação de perfil no servidor,
RBAC no menu e nas URLs, persistência do Shell/Sidebar, layout compacto e
recuperação de rota desconhecida. Não acessam o Supabase online.

A compilação gera `build/web/`. Como as URLs usam caminhos sem `#`, configure a
hospedagem para servir `index.html` quando uma rota como `/dashboard` não
corresponder a um arquivo. Sirva o painel e a API com HTTPS em produção e permita
a origem do painel na configuração CORS do Flask.
