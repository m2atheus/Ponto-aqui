# Deploy na Azure com Docker e Portainer

Todos os builds são executados no computador local. A VM Ubuntu de 1 GiB
apenas baixa e executa as imagens. O banco continua no Supabase.

## 1. Preparar os arquivos e as ferramentas locais

Arquivos incluídos no projeto:

- `Dockerfile` e `.dockerignore`: API Python 3.12 com Gunicorn.
- `admin_web/Dockerfile`, `.dockerignore` e `nginx.conf`: arquivos Flutter já compilados.
- `docker-compose.yml`: Stack para Portainer com Docker Standalone.

Instale/inicie o Docker Desktop em modo Linux containers. Tenha Flutter
disponível no terminal. Crie dois repositórios no Docker Hub:
`ponto-aqui-api` e `ponto-aqui-webadmin`.

A API usa um worker e duas threads para limitar a multiplicação de memória.
O Nginx encaminha `/api/` ao serviço `api` e permite recarregar URLs do go_router.
Referências: [Gunicorn](https://docs.gunicorn.org/en/stable/design.html)
e [Nginx](https://nginx.org/en/docs/http/ngx_http_core_module.html#try_files).

## 2. Conferir a VM

Na sessão SSH do Ubuntu:

```bash
uname -m
free -h
sudo ss -ltnp
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Os comandos de build abaixo usam `linux/amd64` para VMs `x86_64`.
Se a VM mostrar `aarch64`, use `linux/arm64` nos dois builds.

As portas 80 e 8000 precisam estar livres. Se o Portainer já usar a 8000,
troque somente o mapeamento da API na Stack por `8001:8000`.
O proxy interno continua usando `api:8000`.

No Azure Portal, abra VM > Networking e permita entrada TCP na porta 80.
Não é necessário liberar publicamente a porta 8000 para o painel funcionar.
Libere-a apenas para origens que precisem acessar a API diretamente.
Referência: [rede de VMs Azure](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/tutorial-virtual-network).

## 3. Build e push no computador local

Execute no PowerShell, a partir da raiz do projeto. Substitua o usuário e o IP.
O exemplo HTTP serve para validar o deploy; antes do uso com dados reais,
configure HTTPS e compile o painel com a origem HTTPS definitiva.

```powershell
$DockerHubUser = "meu-usuario-docker"
$ImageTag = "v1"
$PublicOrigin = "http://IP-PUBLICO-DA-AZURE"

docker version
docker login

docker buildx build --platform linux/amd64 --load -t "${DockerHubUser}/ponto-aqui-api:${ImageTag}" .
if ($LASTEXITCODE -ne 0) { throw "Falha no build da API." }
docker push "${DockerHubUser}/ponto-aqui-api:${ImageTag}"
if ($LASTEXITCODE -ne 0) { throw "Falha no push da API." }

Push-Location admin_web
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "Falha no flutter pub get." }
    flutter build web --release --dart-define="API_BASE_URL=${PublicOrigin}/api/web/"
    if ($LASTEXITCODE -ne 0) { throw "Falha no build Flutter." }
    docker buildx build --platform linux/amd64 --load -t "${DockerHubUser}/ponto-aqui-webadmin:${ImageTag}" .
    if ($LASTEXITCODE -ne 0) { throw "Falha no build do painel." }
    docker push "${DockerHubUser}/ponto-aqui-webadmin:${ImageTag}"
    if ($LASTEXITCODE -ne 0) { throw "Falha no push do painel." }
} finally {
    Pop-Location
}
```

`API_BASE_URL` é compilada no Flutter: não pode apontar para localhost ou
`http://api:8000`, pois o navegador do usuário não resolve a rede dos containers.
O Nginx publica a API sob a mesma origem do painel.
Referências: [build Flutter Web](https://docs.flutter.dev/deployment/web)
e [buildx](https://docs.docker.com/reference/cli/docker/buildx/build/).

Não publique `.env`, `instance` ou senhas no Registry. Os contextos de build
incluem apenas os arquivos necessários. Imagens públicas expõem o código da API;
use repositórios privados se quiser restringir seu acesso.

## 4. Configurar a Stack no Portainer

Selecione o ambiente Docker Standalone > Stacks > Add stack > Web editor.
Nome: `ponto-aqui`. Cole o conteúdo de `docker-compose.yml`.

Em Environment variables, defina:

```dotenv
DOCKERHUB_USER=meu-usuario-docker
IMAGE_TAG=v1
PUBLIC_ORIGIN=http://IP-PUBLICO-DA-AZURE
DATABASE_URL=postgresql+psycopg2://postgres.ID-DO-PROJETO:SENHA-CODIFICADA@HOST-DO-SESSION-POOLER:5432/postgres?sslmode=require
JWT_SECRET_KEY=SEGREDO-FORTE-GERADO-LOCALMENTE
SUPABASE_URL=
SUPABASE_KEY=
SUPABASE_PUBLISHABLE_KEY=
```

Copie host e usuário exatos do painel Supabase > Connect > Session pooler.
Codifique caracteres especiais da senha como componente de URL.
Não use a URL HTTPS do projeto no lugar de `DATABASE_URL`.
Referência: [conexões Supabase](https://supabase.com/docs/guides/database/connecting-to-postgres).

Gere a chave JWT localmente e mantenha o mesmo valor nas atualizações:

```powershell
.\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(48))"
```

O SDK Supabase é opcional para SQLAlchemy. Deixe seus campos vazios se não
utilizar as funcionalidades do SDK; se habilitá-lo, configure URL e chave juntas.

Se as imagens forem privadas, cadastre o Docker Hub em Registries no Portainer
com seu usuário e um token de acesso autorizado a baixá-las.

Os limites são 512 MiB para API e 64 MiB para Nginx; o restante atende Ubuntu,
Docker e Portainer. Monitore as estatísticas: esses limites não garantem que
qualquer carga de trabalho caiba no servidor.
Referência: [limites no Compose](https://docs.docker.com/reference/compose-file/services/#mem_limit).

## 5. Atualizar o banco e iniciar

O deploy não cria tabelas automaticamente. Antes de disponibilizar a versão,
confirme que o `.env` local aponta para o mesmo Supabase de produção.
Se houver migrations novas, faça backup do banco e execute localmente:

```powershell
.\.venv\Scripts\python.exe -m flask --app app:create_app db current
.\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade heads
```

Depois clique em Deploy the stack. Não há `build:` na Stack.

Confira os containers e os logs no Portainer. A prova HTTP da API verifica
inicialização, não a conectividade do PostgreSQL; valide também um login real.

```powershell
curl.exe -f "${PublicOrigin}/"
curl.exe -f "${PublicOrigin}/api/web/"
```

Abra a origem pública no navegador, entre com uma conta real e teste também
recarregar uma página interna do painel.

## 6. Publicar atualizações

1. Altere o código e execute as verificações apropriadas localmente.
2. Defina uma nova tag, por exemplo `$ImageTag = "v2"`.
3. Repita os builds e pushes locais do passo 3.
4. Se houver migrations, aplique-as antes de disponibilizar a nova versão,
   considerando sua compatibilidade com a versão ainda em execução.
5. Portainer > Stacks > ponto-aqui > Editor: altere `IMAGE_TAG` para `v2`.
6. Clique em Update the stack. Ative a opção de re-pull/redeploy se disponível.
7. Aguarde os containers saudáveis e valide o painel e os logs.

O push sozinho não atualiza containers existentes. A troca de tag dispara o
deploy da versão nova; haverá uma breve interrupção com apenas uma instância.
Referência: [atualização de Stacks](https://docs.portainer.io/user/docker/stacks/edit).

Para voltar às imagens anteriores, restaure a tag antiga. Isso não desfaz
migrations; o rollback depende de compatibilidade com o schema atual.

Nunca execute `flutter build web` nem `docker build` na VM Azure.
