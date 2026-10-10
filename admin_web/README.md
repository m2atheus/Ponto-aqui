# Painel administrativo Ponto Aqui

Base Flutter Web com Riverpod, Dio e go_router. Requer Flutter 3.47 ou superior
com Dart 3.13 ou superior. As versões resolvidas estão em `pubspec.lock`.

## Executar localmente

O painel usa autenticação real por padrão. Inicie a API e configure a conta
conforme o [README principal](../README.md). Na raiz do repositório:

```powershell
cd admin_web
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false
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
│   ├── funcionario.dart
│   ├── alocacao.dart
│   ├── setor.dart
│   ├── escala.dart
│   └── w06.dart
├── providers/
│   ├── api_providers.dart
│   ├── auth_provider.dart
│   ├── funcionarios_provider.dart
│   ├── alocacoes_provider.dart
│   ├── setores_provider.dart
│   ├── escalas_provider.dart
│   ├── dashboard_provider.dart
│   └── w06_provider.dart
├── repositories/
│   ├── funcionario_repository.dart
│   ├── alocacao_repository.dart
│   ├── setor_repository.dart
│   ├── escala_repository.dart
│   ├── w06_repository.dart
│   └── repository_failure.dart
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
    ├── funcionarios/funcionarios_screen.dart
    ├── alocacoes/alocacoes_screen.dart
    ├── setores/setores_screen.dart
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

O login real usa a senha da conta cadastrada no banco. Os acessos abaixo são
apenas para demonstração opcional, habilitada com `ENABLE_MOCK_AUTH=true`;
somente nesse modo usam a senha `admin`:

| E-mail | Perfil |
| --- | --- |
| admin@teste.com | SUPERADMIN |
| rh@teste.com | RH da empresa de demonstração |
| gestor@teste.com | GESTOR da empresa de demonstração |

O AuthService gera um JWT fictício com validade de oito horas, salva o perfil e
a empresa correspondente e não faz requisições de autenticação. A sessão de teste permite navegação visual; o
interceptor bloqueia o envio desse JWT à API. O mock vem desabilitado por padrão.
Para habilitar apenas a navegação de demonstração:

```powershell
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=true
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

## Telas e persistência

O Dashboard mostra cards diferentes por perfil: empresas e atalho de cadastro
para Superadmin; funcionários, setores e escalas ativas para RH; justificativas
pendentes para Gestor. Os totais vêm da API e são atualizados após alterações
nos cadastros. O botão Atualizar indicadores consulta novamente o banco.

`/empresas` é exclusivo do Superadmin. A tabela mostra razão social, CNPJ,
administrador/RH e status. Nova Empresa e Editar abrem um formulário com validação
de campos obrigatórios, e-mail, formato e duplicidade de CNPJ. Desativar pede
confirmação e preserva a linha; o status pode ser reativado no formulário.
O atalho `/empresas/nova` abre a tabela com o modal de cadastro.
O formulário também recebe nome e senha inicial do RH. A API grava empresa e
conta RH na mesma transação; a senha fica com hash. No cadastro/edição, o diálogo
só fecha após confirmação do servidor; falhas aparecem no formulário. A senha
na edição é opcional. A tela consulta o banco novamente ao recarregar a página
e oferece atualização manual. Sessões mockadas não podem cadastrar empresas.
Não há envio automático de convites.

`/escalas` é exclusivo do RH e usa Dio para GET, POST, PUT e DELETE. A tabela
mostra modelo, turnos, dias e status. O formulário aceita 5x2, Diurno, 12x36 e
24x72, vários turnos, intervalos e data de referência para os ciclos. Saída
anterior à entrada indica virada de dia; horários iguais exigem selecionar
saída no dia seguinte para jornadas de 24 horas. A API valida os dados.

Remover pede confirmação. Escalas já utilizadas em alocações não podem ser
removidas nem ter seus turnos reescritos; edite o nome/status ou crie outra
escala. O servidor extrai `empresa_id` do JWT. Reabrir o painel consulta os
registros persistidos no Supabase.

`/setores` é exclusivo do RH e usa a API para listar, cadastrar, editar e remover
os locais de trabalho. O formulário tem mapa OpenStreetMap: clique para definir
o centro e ajuste o raio em metros pelo slider ou pelo campo numérico. Latitude
e longitude também podem ser digitadas, inclusive se o mapa estiver indisponível.
Nome, coordenadas e raio positivo são obrigatórios; endereço é opcional.
Os seletores controlam selfie, localização dispensada e bloqueio ou análise
fora do perímetro. As políticas e o perímetro existentes são preservados na edição.
Remover pede confirmação; setores com alocações, inclusive encerradas, recebem
HTTP 409 e permanecem na tabela. As mudanças aparecem após confirmação da API.
Sessões de demonstração não gravam setores. Consulte o
[contrato W02](../docs/W02-admin-web.md).

Após atualizar o projeto, execute `flutter pub get` na pasta `admin_web` para
instalar os pacotes de mapa e reinicie os dois terminais: Flask e Flutter.

`/funcionarios` é exclusivo do RH e usa Dio para listar, cadastrar, editar e
desativar, com confirmação e indicadores de carregamento. Nome e matrícula
são obrigatórios; cargo é opcional conforme o modelo Flask. Erros de negócio
aparecem no formulário e em SnackBar vermelho. O cadastro só é refletido na
tabela após a confirmação da API.

As rotas de Funcionários estão implementadas em `/api/web/funcionarios`.
Após atualizar o código, reinicie o Flask com `python run.py` no ambiente
virtual e mantenha-o aberto durante o uso do painel. A API valida o perfil RH,
a empresa da sessão e a matrícula única, e persiste as mudanças no PostgreSQL.
Consulte o [contrato de integração W03](../docs/W03-admin-web.md).
`/alocacoes` é exclusivo do RH e usa a API para listar os vínculos com nomes,
matrículas, setores e datas. Nova Alocação abre um modal com funcionários e
setores ativos, início obrigatório e fim opcional, em DD/MM/AAAA. Encerrar
solicita a data final e envia apenas `data_fim`; o registro permanece na tabela.
O backend recusa períodos sobrepostos no mesmo setor e alterações dos vínculos
históricos. Erros mantêm o formulário preenchido e aparecem em SnackBar.
A consulta de setores usa `GET /api/web/setores`, compartilhando os dados reais
com a gestão de Setores. Novos setores ficam disponíveis no cadastro de alocações.

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
restauração da sessão. Empresas e escalas usam persistência real.

Equipe, Justificativas e Relatórios consultam os dados reais da empresa via
`W06Repository`. O RH cadastra, edita e remove feriados/afastamentos e consulta
o espelho mensal; o Gestor consulta equipe e justificativas. O atestado é enviado
em multipart ao salvar o afastamento e baixado por um endpoint com JWT.
Consulte o [guia de uso](../docs/W06-admin-web.md), incluindo as migrations.

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
