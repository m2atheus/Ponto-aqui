# W01 — Modelos e autenticação

Esta etapa implementa os modelos W01/W02/W03 e a autenticação real. Os CRUDs e
Services de Setores, Funcionários e Alocações serão construídos na próxima etapa.
O aplicativo mobile permanece fora do escopo; a API já compartilha o contrato
de autenticação com ele.

## Preparar o banco

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade
```

A migration `0003` preserva as marcações W09, migra as políticas de setor e
cria `funcionarios`, com RLS e chaves compostas por empresa. Apenas Superadmin
fica com `empresa_id = NULL`; os demais perfis exigem uma empresa.
O perfil legado `Relogio` passa a `UsuarioSetor`; o nome Python `RELOGIO` continua
como alias de `USUARIO_SETOR`. O enum de origem das batidas permanece independente.

Contas de funcionário/alocação existentes recebem um cadastro de funcionário
vinculado. A matrícula anterior é preservada; quando estava ausente, a migration
usa `LEGACY-UUID_DO_USUARIO`, para revisão posterior. `cargo` e `endereco` ficam
opcionais para permitir a atualização de dados antigos ainda sem essas informações.
A matrícula antiga em `usuarios` permanece como coluna legada; novos cadastros
de funcionários deverão usar `funcionarios.matricula`.

O e-mail é único globalmente, permitindo login sem escolher uma empresa.
A migration bloqueia e-mails duplicados, alocações sobrepostas e Superadmins
com vínculos de empresa. A mensagem informa o que precisa de revisão, sem
renomear contas ou modificar pontos para contornar conflitos. O downgrade
também é bloqueado quando existem funcionários ou contas globais a preservar.

A constraint de sobreposição usa `btree_gist`. A migration instala a extensão
se necessário e respeita o schema de uma instalação existente. Datas são
inclusivas; fim nulo significa período aberto. Duas alocações do mesmo
funcionário no mesmo setor não podem compartilhar um dia, inclusive em escritas
concorrentes. A regra é específica desse par; outros setores não são bloqueados.
`escala_id` e `usuario_id` da alocação são opcionais para permitir cadastro sem
escala/conta, mas, quando informados, têm vínculos de empresa consistentes.

## Criar a primeira conta para testar

O cadastro HTTP de empresas/usuários será implementado separadamente. Um operador
com acesso ao console do backend pode criar a primeira conta global:

```powershell
.\.venv\Scripts\python.exe -m flask --app app:create_app shell
```

```python
from getpass import getpass
from app import db
from app.models import Usuarios, PapelUsuario
from app.services.auth_service import AuthService

admin = Usuarios(
    nome="Administrador", email="seu-email@exemplo.com",
    senha_hash=AuthService.hash_senha(getpass("Senha: ")),
    papel=PapelUsuario.SUPERADMIN, empresa_id=None,
)
db.session.add(admin)
db.session.commit()
```

Use um e-mail ainda não cadastrado e sua própria senha. O hash usa scrypt com
salt; senha original e hash não são enviados nas respostas. Contas RH/Gestor
precisam do UUID de uma empresa ativa. Uma empresa desativada impede login.
Nenhuma conta ou senha de demonstração é criada automaticamente pela migration.

## Contrato HTTP

`POST /auth/login`, `POST /api/web/auth/login` e
`POST /api/mobile/auth/login` compartilham a mesma implementação:

```json
{"email": "seu-email@exemplo.com", "senha": "sua-senha"}
```

Resposta HTTP 200:

```json
{
  "access_token": "JWT_ASSINADO",
  "token_type": "Bearer",
  "usuario": {
    "id": "UUID_DO_USUARIO",
    "nome": "Administrador",
    "email": "seu-email@exemplo.com",
    "papel": "SUPERADMIN",
    "empresa_id": null
  }
}
```

O JWT expira em 30 minutos por padrão (`JWT_ACCESS_TOKEN_EXPIRES` na factory).
As claims `sub`, `empresa_id` e `role` são derivadas do usuário no banco;
o request não pode escolher seu perfil nem sua empresa. O login normaliza o
e-mail, preservando a senha exatamente como enviada. Falhas de credenciais,
usuário inativo e empresa inativa retornam o mesmo HTTP 401 e JSON:

```json
{"erro": {"codigo": "LOGIN_INVALIDO", "mensagem": "Usuário ou senha inválidos"}}
```

As rotas protegidas retornam 401 para token ausente, inválido ou vencido.
`GET /api/web/auth/me` (também `/auth/me` e `/api/mobile/auth/me`) recebe Bearer
JWT e retorna `{"usuario": {...}}`, reconstruindo o perfil e conferindo
novamente usuário, empresa e status no banco. Assim, desativar uma empresa
também impede restaurar sua sessão. Não há refresh/logout de servidor nesta etapa.

Os papéis retornados são `SUPERADMIN`, `RH`, `GESTOR`, `FUNCIONARIO` e
`USUARIO_SETOR`. O painel Flutter aceita os três primeiros. Os demais estão
disponíveis para clientes apropriados, sem conceder acesso administrativo.

O login mobile pode incluir `dispositivo_id`. A claim correspondente só é emitida
quando o aparelho existe, está ativo e pertence à empresa/usuário autenticados.
O aparelho deve ser cadastrado por um operador confiável antes disso; não é
registrado automaticamente pelo login. Uma conta de funcionário pode fazer
login sem aparelho, mas o envio W09 exige sua vinculação para aceitar marcações.

## Usar o Flutter Web com a API real

Inicie o backend com `.\.venv\Scripts\python.exe run.py` e, em outro terminal:

```powershell
cd admin_web
flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false --dart-define=API_BASE_URL=http://localhost:5000/api/web/
```

Entre com a conta criada no banco. Os cadastros de Empresas/Escalas do painel
ainda usam listas em memória; autenticação real não muda essa persistência.

Referências: [hashes de senha do Werkzeug](https://werkzeug.palletsprojects.com/en/stable/utils/#werkzeug.security.generate_password_hash),
[callbacks JWT](https://flask-jwt-extended.readthedocs.io/en/stable/api.html)
e [constraints de exclusão PostgreSQL](https://www.postgresql.org/docs/current/rangetypes.html#RANGETYPES-CONSTRAINT).
