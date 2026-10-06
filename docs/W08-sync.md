# W08 — Carga inicial mobile

`GET /api/v1/mobile/sync` exige JWT e o aparelho autorizado por W07:

```http
Authorization: Bearer JWT_VALIDO
X-Device-UUID: UUID_DO_APP_REGISTRADO
```

`empresa_id` e usuário vêm do JWT, e o modo vem do dispositivo no banco. O token
precisa conter `dispositivo_id` vinculado ao UUID do header. Para relógios, a
conta deve ter papel `USUARIO_SETOR`, com `setor_id` autorizado no JWT. O tipo
persistido é `RELOGIO`, representando o relógio de setor. A emissão de tokens
para esse login continua sob responsabilidade do fluxo confiável de W07;
o sync não cria aparelhos nem emite tokens.

Exemplos completos, com identificadores fictícios:
[Modo Pessoal](examples/w08-pessoal.json) e [Modo Relógio](examples/w08-relogio.json).

## Horário e vigência

- `server_timestamp`: instante UTC capturado ao montar a carga, com seis casas
  de precisão e sufixo `Z`. O mesmo valor aparece em `X-Server-Timestamp`.
- `data_referencia`: data desse instante no `fuso_horario` da empresa. O início
  e o fim da alocação são inclusivos. Fim vazio representa vigência aberta.
- A carga inclui todas as alocações vigentes nessa data. Em um dia de folga de
  um ciclo, a escala continua no payload para o app calcular a programação.
  Turnos e referências são enviados, sem alterar a definição histórica.
- O timestamp informa o relógio do servidor; a estimativa de desvio do celular
  deve considerar o tempo de ida e volta da requisição.

## DTO pessoal

`funcionario` contém apenas ID, ID da conta opcional, nome, matrícula e cargo.
`alocacoes` conserva todos os vínculos vigentes, cada um com ID, datas, setor e
escala. Quando existe exatamente uma, `setor` e `escala` também a representam.
Com várias, esses dois campos ficam nulos e o status orienta consultar a lista.

O setor contém centro/raio e políticas de selfie, perímetro, localização e desvio
máximo. A escala contém modelo, referência, tolerância e turnos ordenados com
horários locais, intervalo em minutos, virada e dias ISO (segunda=1).

`marcacoes_recentes` retorna até 20 registros recebidos nos últimos sete dias,
ordenados por recebimento decrescente. A hora original do aparelho é preservada,
mesmo quando está no futuro por desvio. Não são enviados selfies, senhas, e-mails,
payload original, hashes ou snapshots de localização.

## DTO relógio

`setor` corresponde exclusivamente ao vínculo do aparelho. `funcionarios`
contém todos os funcionários ativos com alocação vigente nesse setor, inclusive
os que ainda não possuem conta de acesso. Cada item contém suas alocações com
`escala_id`. O catálogo `escalas` contém uma cópia de cada escala utilizada.
Não é enviado histórico de marcações de toda a equipe.

Consultas de alocações usam joins por empresa; turnos são carregados em lote.
A quantidade de consultas não cresce com a quantidade de funcionários.

## Status e erros

| HTTP | `status` / `erro.codigo` | Significado |
| --- | --- | --- |
| 200 | `OK` | Carga disponível. |
| 200 | `SEM_ALOCACAO` | Pessoal sem alocação hoje; setor/escala nulos e lista vazia. |
| 200 | `SEM_FUNCIONARIO` | Conta pessoal sem cadastro ativo de funcionário. |
| 200 | `SEM_ESCALA` | Alocação ainda sem escala. |
| 200 | `ESCALA_SEM_TURNOS` | Escala ainda sem turnos estruturados; não há inferência de JSON legado. |
| 200 | `MULTIPLAS_ALOCACOES` | Todas as alocações pessoais estão na lista. |
| 200 | `SEM_FUNCIONARIOS` | Relógio sem funcionários alocados hoje. |
| 401 | `TOKEN_INVALIDO` | JWT ausente, inválido ou expirado. |
| 403 | `DISPOSITIVO_NEGADO` | UUID ausente/desconhecido, revogado ou vínculo incompatível. |
| 403 | `SETOR_INDISPONIVEL` | Setor do relógio desativado. |
| 503 | `SYNC_INDISPONIVEL` / `DISPOSITIVOS_INDISPONIVEIS` / `FUSO_INVALIDO` | Falha temporária de banco ou configuração. |

Em sucesso, `mensagem_status` traz a explicação para exibição. A resposta usa
`Cache-Control: private, no-store`: o app salva sua cópia offline explicitamente,
sem depender do cache HTTP. CORS permite `X-Device-UUID` e expõe o header de hora.

O sync usa um Blueprint versionado separado. Os endpoints W09 existentes mantêm
suas URLs e regras; o sync não habilita envio coletivo de pontos por relógios.

## Migrations e testes

A migration `0005` une as duas revisões anteriores (`0004` e `0004_w04_w07`),
sem DDL nem alterações de dados próprias. Ela resolve a ambiguidade de `head` e
permite instalar ambas as fundações. Nenhuma migration foi aplicada online durante
esta implementação. Os testes verificam a carga por HTTP e Service, fuso, vigência,
isolamento, histórico limitado, relógio, revogação, cabeçalhos e consultas em lote.
