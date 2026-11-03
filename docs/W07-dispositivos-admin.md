# W07 — Autorização manual de aparelhos

Em **Funcionários → Ações → Aparelhos e segurança** (ícone de dispositivos),
o RH pode autorizar e revogar aparelhos em um diálogo próprio. O histórico
de **Equipe** permanece dedicado às escalas e alocações. Gere primeiro a conta do
funcionário em **Funcionários → Gerar Acesso App**.

## Persistência

`dispositivos` mantém o UUID físico único, `tipo` (`PESSOAL`/`RELOGIO`), nome,
último acesso e `ativo` (o status persistido). O JSON também oferece `status`
com os valores `Ativo`/`Inativo`; não existe um segundo status independente.

A migration **0009** cria `dispositivos_usuarios`, com autorizações individuais
por empresa, usuário e aparelho. Os aparelhos pessoais existentes recebem seus
vínculos automaticamente. A FK de `registros_ponto` passa a referenciar essa
autorização composta, permitindo vários usuários no mesmo relógio sem perder
a integridade entre dispositivo, empresa e funcionário. Nenhuma batida é
editada ou excluída. O downgrade é recusado quando já há pontos de relógio.

A migration **0010** adiciona `dispositivos_usuarios_setores`: cada autorização
de funcionário pode abranger vários setores. Os vínculos de relógios existentes
são copiados com o status anterior. `dispositivos.setor_id` passa a ser apenas a
referência legada; as permissões efetivas vêm dos vínculos por setor.

```powershell
.\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade
```

## Contrato administrativo

Todas as rotas exigem `Authorization: Bearer <JWT>`. A empresa vem do JWT e é
revalidada no banco, junto com o papel e a situação da conta/empresa.

- `GET /api/v1/admin/funcionarios/<id>/dispositivos`: RH/Gestor. Retorna
  `dispositivos`, `setores_disponiveis` (alocações vigentes no fuso da empresa)
  e `tem_acesso_app`. Funcionário de outra empresa retorna `404`.
- `POST /api/v1/admin/funcionarios/<id>/dispositivos`: somente RH, retorna
  `201 {"dispositivo": {...}}` após confirmar a autorização.
- `POST /api/v1/admin/funcionarios/<id>/dispositivos/<dispositivo_id>/revogar`:
  somente RH, sem corpo; retorna `200 {"dispositivo": {...}}`.

Exemplo de autorização:

```json
{
  "device_uuid": "31da5a20-1a4a-41ef-87c8-e5a3f986d313",
  "tipo": "RELOGIO",
  "nome_identificador": "Celular da Portaria",
  "setor_id": "<UUID do setor>"
}
```

`nome_identificador` é opcional. `setor_id` só vale para `RELOGIO` e pode ser
omitido quando o funcionário tem um único setor vigente, ou quando o relógio
já existe e ele tem alocação vigente nesse setor. Em caso de múltiplos setores,
o formulário solicita a escolha. Um aparelho pessoal continua exclusivo de seu
titular; não é transferido automaticamente para outra pessoa. Repetir o POST
com o mesmo UUID e outro `setor_id` adiciona uma autorização; não substitui os
setores já autorizados. O DTO do aparelho inclui `setores: [{id, nome, ativo}]`.

### Converter um aparelho pessoal para compartilhado

Selecione **Relógio Compartilhado** no formulário e escolha o setor. Se o UUID
estiver cadastrado como pessoal, a primeira tentativa retorna
`409 CONVERSAO_RELOGIO_NECESSARIA`, sem modificar nenhum vínculo. O painel
solicita a confirmação **Converter e autorizar**, e só então repete o POST com
`"converter_para_relogio": true`. Esse campo precisa ser booleano e só vale
para `tipo: RELOGIO`.

A conversão mantém a PK/UUID do aparelho, as marcações e os vínculos históricos.
O titular anterior mantém seu acesso nos próprios setores com alocação vigente
se sua autorização estava ativa. Ele não precisa pertencer ao novo setor
escolhido para outro funcionário. Autorizações anteriormente revogadas não são
restauradas apenas pela conversão.

Depois de converter, entre novamente no aplicativo para emitir o JWT com o
contexto do setor. O sync de um token pessoal anterior retorna
`403 DISPOSITIVO_MODO_ALTERADO`, com essa orientação. O suporte a vários setores
exige a migration `0010`.

Um relógio já existente é vinculado a outro funcionário repetindo o POST com
o mesmo UUID, `tipo: RELOGIO` e o setor desejado. O aparelho físico continua
sendo uma única linha e pode atender setores diferentes. O funcionário que
recebe a nova autorização precisa estar alocado nesse setor e ter conta ativa.

## Revogação e sincronização

- `PESSOAL`: autorizar um novo aparelho desativa os outros aparelhos pessoais
  daquele usuário; seus relógios compartilhados permanecem autorizados.
- `RELOGIO`: autorizar ou fazer login não revoga vínculos de outras pessoas.
  Revogar pelo perfil remove o acesso daquele funcionário ao relógio em todos
  os seus setores. Reautorizar um setor restaura somente o setor escolhido.
- Todas as autorizações são revalidadas no login/sync e no recebimento de
  novas marcações. A desativação preserva vínculos e pontos para auditoria.
- `ativo`/`status` no DTO representam o acesso efetivo do funcionário:
  tanto o aparelho quanto seu vínculo precisam estar ativos.

## Integração mobile

O app deve mostrar o `device_uuid` da instalação no rodapé do login, permitindo
copiar o código para o RH. O UUID identifica a instalação; não substitui senha
nem concede autorização por si só.

`POST /api/mobile/auth/login` continua aceitando `email`, `senha` e o
`dispositivo_id` interno utilizado por clientes anteriores. Também aceita
`device_uuid`, permitindo login com o código previamente autorizado pelo RH.
Se ambos forem enviados, devem identificar o mesmo aparelho. Não há cadastro
automático de um UUID desconhecido nessa rota, e os erros de credenciais ou
autorização de aparelho permanecem genéricos.

O JWT inclui `dispositivo_id`, `device_uuid` e, para relógios, `setor_id` e
`setor_ids`. O login aceita `setor_id` opcional para escolher o contexto inicial
entre os setores autorizados. A resposta inclui `setores_disponiveis` (`id`,
`nome`). Sem escolha explícita, usa a referência legada se autorizada; caso
contrário, o primeiro setor autorizado em ordem alfabética.

O app pode obter outra carga usando `GET /api/v1/mobile/sync?setor_id=<UUID>`,
com o mesmo JWT e header do aparelho. A API revalida o setor no banco; não
confia apenas na lista do token. A carga contém `setores_disponiveis` e os dados
do setor escolhido. O cache offline deve ser separado por empresa, usuário e
setor. Tokens legados de `USUARIO_SETOR` continuam restritos ao setor original.

`GET /api/v1/mobile/sync` exige `X-Device-UUID` e retorna `modo_operacao: RELOGIO`
para o dispositivo compartilhado. Cada funcionário entra com sua própria conta
e envia pontos/selfies com seu JWT; não há permissão para registrar em nome de
outro funcionário apenas por conhecer sua matrícula. O app pode substituir a
sessão local ao trocar de usuário, sem revogar as sessões dos demais no servidor.

O campo legado **ID de cadastro** pode ser copiado no painel; ele corresponde
à PK `dispositivo_id`, enquanto **Copiar código** copia o UUID da instalação.
