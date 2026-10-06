# W02 — Gestão de Setores

O RH gerencia os setores da própria empresa em `/setores`. A API recebe o JWT,
confirma o usuário, seu perfil e a empresa ativa no banco e aplica o filtro de
`empresa_id` em todas as consultas. O frontend não envia `empresa_id` no corpo.

## Executar e usar

1. Na raiz, inicie o Flask: `.\.venv\Scripts\python.exe run.py`.
2. Em outro terminal, na pasta `admin_web`, execute `flutter pub get` e
   `flutter run -d chrome --web-port=3000`.
3. Entre com uma conta real de RH e abra **Setores → Novo Setor**.
4. Informe nome e políticas, clique no mapa para escolher o centro e ajuste
   o raio. Também é possível digitar as coordenadas. Clique em **Salvar**.

O cadastro só entra na tabela após confirmação do servidor. Uma atualização
da página consulta os mesmos dados no PostgreSQL. A tela de Alocações usa essa
lista para oferecer os setores disponíveis. Escalas do painel seguem seu fluxo
atual; esta implementação não altera o layout global nem cria o aplicativo mobile.

## Contrato HTTP

Todos os endpoints exigem `Authorization: Bearer <JWT>` e perfil RH.

| Método | Endereço | Sucesso |
| --- | --- | --- |
| GET | `/api/web/setores` | 200: `{"setores": [...]}` |
| POST | `/api/web/setores` | 201: `{"setor": {...}}` |
| PUT | `/api/web/setores/<uuid>` | 200: `{"setor": {...}}` |
| DELETE | `/api/web/setores/<uuid>` | 200: `{"id": "<uuid>", "removido": true}` |

Corpo de criação (PUT aceita também atualização parcial):

```json
{
  "nome": "Sede",
  "endereco": "Rua do Trabalho, 100",
  "latitude": -8.0476,
  "longitude": -34.877,
  "raio_metros": 100,
  "exige_selfie": true,
  "acao_fora_perimetro": "PENDENTE",
  "ignorar_localizacao": false
}
```

O DTO de resposta adiciona `id`, `empresa_id`, `ativo` e
`limite_desvio_relogio_segundos`. As coordenadas JSON se chamam `latitude` e
`longitude`; o serviço as mapeia para `latitude_centro` e `longitude_centro`.
O banco mantém sete casas decimais nas coordenadas e duas no raio. Nome admite
120 caracteres; endereço opcional admite 255. Raio deve permanecer positivo
após o arredondamento do banco. Latitude aceita -90 a 90; longitude, -180 a 180.
Os booleanos são estritos e a ação admite somente `BLOQUEAR` ou `PENDENTE`.
Campos desconhecidos, incluindo tentativa de alterar `empresa_id`, retornam 400.

Nome duplicado na mesma empresa recebe 409. Exclusão com qualquer alocação,
inclusive histórica, também recebe 409. Outros vínculos protegidos por FK,
como feriados e dispositivos, impedem exclusão e preservam seus registros.
Um setor de outra empresa recebe 404. JWT ausente, vencido ou incompatível
com a conta recebe 401; perfis sem permissão recebem 403.

Erros seguem o envelope comum:

```json
{
  "erro": {
    "codigo": "SETOR_ALOCADO",
    "mensagem": "Não é possível remover um setor com funcionários alocados, mesmo em alocações encerradas."
  }
}
```

O repositório traduz erros para `RepositoryFailure`; a tela conserva os dados
e mostra um SnackBar vermelho. Respostas HTTP com DTO inválido não confirmam
cadastro/edição, e exclusão exige confirmação explícita. O DTO ainda lê os
resumos antigos usados por Alocações; sua edição fica desabilitada quando o
perímetro não foi enviado, para evitar substituir informações desconhecidas.

## Mapa e verificações

O mapa usa `flutter_map`, `latlong2` e tiles HTTPS do OpenStreetMap, com
atribuição clicável aos contribuidores. `CircleMarker.useRadiusInMeter`
mantém o raio em metros em diferentes níveis de zoom. As credenciais da API
não são enviadas ao servidor de tiles. A política de ignorar localização
dispensa posição na marcação de ponto; o setor continua com centro e raio
cadastrados para compatibilidade com o modelo existente.

- [Documentação do CircleLayer](https://docs.fleaflet.dev/layers/circle-layer).
- [Política de uso dos tiles OpenStreetMap](https://operations.osmfoundation.org/policies/tiles/).

Na pasta `admin_web`, execute `flutter analyze`, `flutter test` e
`flutter build web --release`. Os testes usam adaptadores HTTP e imagens locais
de tiles, cobrindo mapa, slider, validações, CRUD, erros, logout durante escrita,
preservação do Shell e layout de 320 pixels. Os testes Flask em
`tests/test_setores_api.py` validam persistência, isolamento, RBAC, preflight,
precisão numérica e exclusão bloqueada em PostgreSQL de teste. Eles não acessam
o Supabase online. Não há alteração de models ou migration nova nesta etapa.
