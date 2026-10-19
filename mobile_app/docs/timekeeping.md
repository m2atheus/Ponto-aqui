# Relógio do aparelho e evidência temporal

## Auditoria e arquitetura

Auditoria de 19/10/2026: o mobile tem MVVM, Riverpod, SQLite/Drift, captura local e
serializador W09. Não tem cliente HTTP, autenticação real, bootstrap W08 ou
transportador. Antes desta alteração, `ClockEstimate` só chegava por injeção e
não havia medição/persistência da estimativa nem prévia do relógio na tela.
As alterações locais preexistentes em `.gitignore` e `AGENTS.md` foram preservadas.

Mantemos a arquitetura e a tela existentes. A sequência implementada foi:
serviço temporal e armazenamento isolado; adaptador para respostas; integração
na captura/tela; testes de migração, relógio, widgets e contrato de recebimento.
Não há nova tela, endpoint, alteração no backend ou nova dependência de pacote.

| Endpoint existente | Referência temporal atual | Uso pelo adaptador |
| --- | --- | --- |
| POST `/api/mobile/auth/login` | Nenhuma hora atual explícita | Sem nova amostra |
| GET `/api/mobile/auth/me` | Nenhuma hora atual explícita | Sem nova amostra |
| GET `/api/v1/mobile/sync` | `server_timestamp` e `X-Server-Timestamp`, UTC com Z | Referência válida; se ambos vierem, devem concordar |
| POST `/api/mobile/marcacoes/lote` | `recebido_em` por evento, preservado em reenvios | Recebimento validável, **não** serve como hora atual |
| POST `/api/mobile/marcacoes/{evento_cliente_id}/selfie` | Sem referência atual explícita | Sem nova amostra |

Matriz conferida em rotas/Services e testes W08/W09. Não se assume header `Date`
ou `X-Server-Timestamp` nas demais rotas. Para medir em todas as conversas, o
responsável pela API precisa aprovar um header temporal explícito, preferencialmente
`X-Server-Timestamp` UTC, nas respostas relevantes, com exposição CORS quando
aplicável. Essa proposta não foi aplicada. O adaptador já aceita esse header em
respostas bem-sucedidas da mesma origem; não cria chamadas adicionais.

## Medição e continuidade

Fórmula preservada: `offsetMs = serverTimestampUtc - deviceUtcAtReceipt`.
Positivo = aparelho atrasado; negativo = adiantado. A hora original não é corrigida.
`offsetMs ~/ 1000` trunca para zero, como no código anterior: +1599 ms → +1 s,
-1599 ms → -1 s. Fuso UTC e desvio são grandezas distintas.

A referência representa a montagem da resposta, não o ponto médio de uma viagem
simétrica. A estimativa inclui latência. Guardamos a duração monotônica da viagem,
sem chamá-la de limite de erro ou prometer precisão. Não adotamos ponto médio.

Relógio civil e `Stopwatch` são injetáveis. Com âncora viva, a diferença entre avanço
civil e monotônico acima de dois segundos invalida a estimativa. Essa tolerância
de medição é injetável; não é o limite de negócio nem comprovação de fraude.
Igualdade à tolerância mantém a continuidade. Uma alteração menor pode não ser
detectada. Não há limite de idade de negócio inventado: a idade monotônica fica
disponível e nenhuma amostra comprova que o relógio permaneceu correto offline.

Suspensão/perda de foco invalida a continuidade de forma conservadora, pois o
comportamento do contador durante suspensão depende da plataforma. Ao retomar,
mostramos estimativa desatualizada até nova referência. Contadores não são
persistidos. Reabertura guarda a última amostra, mas não a apresenta como medição
atual nem calcula idade civil potencialmente enganosa. Estimativa injetada sem
âncora viva também é desatualizada. Falhas/timeout e referências inválidas não
substituem a última amostra válida. Não há requisições de tentativa automática.

## Persistência e captura

Schema local 1 → 2 cria somente `clock_estimates`, sem apagar/recriar o banco e sem
reescrever `marks`/`transport`. A chave usa o mesmo escopo de origem API, empresa,
conta e aparelho. A tabela guarda offset, referência UTC do servidor, hora civil
de recebimento da amostra, duração da requisição e origem da referência. Não guarda
credenciais nem continuidade monotônica entre execuções.

Na captura, hora original e snapshot temporal são congelados **antes de await**.
O ponto guarda disponibilidade (`unmeasured`, `available`, `stale`), motivo,
referência/idade quando mensurável, desvio atual ou null e dados auxiliares da
última amostra. Desvio antigo não é reutilizado como atual após perda de continuidade.
Os campos auxiliares não entram no payload HTTP.

A transação de marcação continua inserindo evidência e fila juntas. A interface
confirma somente após commit. Nova referência, alteração do relógio ou confirmação
de diálogo não recalculam eventos anteriores. O diálogo de batidas próximas exibe
o instante do toque; a prévia pode avançar, mas o evento pendente mantém o instante
e desvio congelados. Evidências desconhecidas nunca são completadas retroativamente.

## Interface e política

Enquanto ativa, a tela atualiza a hora do aparelho a cada segundo e explica que
o instante definitivo é capturado no toque. Mantém um toque no fluxo normal.
Avisos acessíveis indicam desvio desconhecido/desatualizado ou excessivo.

O limite vem de `EmployeeContext.clockLimitSeconds`, ponto de injeção da política
W08 `setor.politicas.limite_desvio_relogio_segundos`. Sem política, a interface diz
que o limite não está disponível; não inventa um valor de produção. A regra é a
mesma do servidor: `abs(desvio_em_segundos) > limite`. Igualdade não é excesso.
Esses avisos não bloqueiam a gravação. Bloqueios anteriores de identidade,
vigência, data de referência W08 e jornada noturna permanecem: podem impedir
captura se uma mudança civil tornar o contexto inválido e dependem dos fluxos próprios.

## Pontos de integração

- `ClockService` calcula e fornece snapshots; `SqliteClockEstimateStore` persiste
  a última amostra. `clockServiceProvider(employee)` compartilha a instância entre
  tela e futuro cliente HTTP daquele contexto. O bootstrap deve canonicalizar a origem.
- `ClockResponseObserver.begin()` captura início; o cliente futuro deve capturar
  `service.read()` imediatamente ao receber a resposta, antes de awaits de parsing
  ou disco, e passar os dois instantes, URI, status, headers e body a `response()`.
  Timeouts não chamam esse callback. O adaptador verifica origem, timestamp UTC,
  coerência header/body e continuidade; não implementa cliente, sessão ou requests.
- `Mark.w09Payload()` mantém apenas os campos aceitos e o desvio congelado. Não
  envia `recebido_em`, metadados internos ou demonstrações; bloqueia desconhecidos
  incompatíveis com o contrato atual.
- `MarkReceipt.verify()` valida um resultado por item contra o evento original:
  UUID, persistência/status, instante, offset, offline e desvio; exige recebimento
  explícito do servidor. Preserva situação remota, inclusive recusa, sem tratá-la
  como aprovação. Não é transportador, não confirma a fila e não mede hora atual.

## Arquivos alterados e criados

| Arquivo | Responsabilidade |
| --- | --- |
| `lib/core/capture.dart` | Estimativa com referência/duração/origem e parsing temporal estrito |
| `lib/core/clock/clock_service.dart` | Relógios injetáveis, cálculo, continuidade e snapshot |
| `lib/core/clock/clock_response_observer.dart` | Adaptador temporal de futuras respostas HTTP |
| `lib/core/clock/sqlite_clock_estimate_store.dart` | Última amostra isolada em SQLite |
| `lib/app/providers.dart` | Banco compartilhado e serviços temporais Riverpod |
| `lib/features/marcacoes/domain/mark.dart` | Limite de política opcional no contexto |
| `lib/features/marcacoes/data/sqlite_mark_repository.dart` | Migração aditiva para schema 2 |
| `lib/features/marcacoes/data/mark_receipt.dart` | Verificação contratual dos três elementos temporais |
| `lib/features/marcacoes/presentation/mark_view_model.dart` | Snapshot no toque e estado da prévia/avisos |
| `lib/features/marcacoes/presentation/mark_screen.dart` | Prévia, avisos, instante no diálogo e ciclo de vida |
| `test/clock_service_test.dart` | Medição, sinais, limites, continuidade, isolamento e persistência |
| `test/clock_capture_test.dart` | Widgets, captura, diálogo e recebimento controlado |
| `test/clock_migration_test.dart`, `test/fixtures/mark_schema_v1.sql` | Upgrade real de arquivo schema 1 preservando evidências/fila/triggers |
| `test/support/clock_fakes.dart` | Fontes determinísticas de relógio e contexto |
| `test/marcacoes_test.dart` | Regressão existente; teste de payload agora usa amostra viva em vez de seed sem âncora |
| `README.md`, `docs/contracts.md`, `docs/timekeeping.md` | Execução, contratos, dependências e aceites |

## Matriz dos sete critérios

| Critério | Estado | Evidência / dependência |
| --- | --- | --- |
| 1. Calcular desvio a cada conversa | **Pendente de dependência** | Medição/adaptador implementados e verificados com respostas controladas; falta cliente mobile e header atual nas demais rotas |
| 2. Guardar e enviar desvio com cada marcação | **Pendente de dependência** | SQLite/snapshot/payload verificados; transmissão depende de transportador e contrato para desconhecido |
| 3. Avisar desvio elevado sem bloquear | **Implementado e verificado** | Testes de widgets com ambos sinais; regra abaixo/igual/acima do limite |
| 4. Mudança do relógio não altera eventos antigos | **Implementado e verificado** | Testes de novos offsets, mudanças civis e JSON original persistido |
| 5. Exibir hora antes de confirmar | **Implementado e verificado** | Widget com tick da prévia e instante congelado no diálogo |
| 6. Avisar desvio desconhecido sem conversa prévia | **Implementado e verificado** | Widget sem amostra permite captura; reinício/suspensão explicitam desatualização |
| 7. Chegar ao servidor com hora original, desvio e recebimento | **Pendente de dependência** | Payload e recebimento controlado validados; não há entrega real nem teste novo de persistência PostgreSQL |

Os critérios marcados verificados foram exercitados por testes automatizados, não
por execução física no aparelho. Integração real permanece sem validação. Nenhum
teste ignorado é contabilizado como aprovado. Resultados de comandos são registrados
no README após execução.

Validação final em 19/10/2026: análise sem problemas e 52 testes aprovados, sem
testes ignorados. Os testes de recebimento usam resultados controlados: não
comprovam entrega HTTP ou commit PostgreSQL. Não houve execução em aparelho.

## Dependências por responsável funcional

| Dependência | Responsável funcional | Próxima entrega necessária |
| --- | --- | --- |
| Autenticação/aparelho | Equipe de identidade e dispositivos | Sessão mobile confiável e aparelho previamente cadastrado |
| Fonte temporal e política W08 | Equipe de bootstrap/API | Contexto/cache validado e conexão do adaptador à resposta real |
| Todas as conversas com hora atual | Responsável pelo contrato HTTP Flask | Aprovar referência temporal nas rotas que hoje não a fornecem |
| Transportador mobile/W09 | Equipe de sincronização mobile | Entregar fila sem recalcular evidências; conectar validação do recebimento |
| Desvio desconhecido | Responsável pelo backend e regra de negócio | Decidir representação/classificação; proposta em `contracts.md` |
| Conectividade desconhecida | Equipe de conectividade/sincronização | Resolver incompatibilidade preexistente do booleano obrigatório |

## Verificação manual

Em desenvolvimento, abrir com `PONTO_AQUI_DEMO=true`: conferir hora dinâmica e
aviso desconhecido; registrar em modo avião; encerrar/reabrir e verificar os
eventos intactos. A demonstração não fabrica referência do servidor ou limite.
Avisos de desvio conhecido e a troca de amostras são testados por injeção
controlada nos testes, até existir comunicação real autenticada.

Com uma referência legítima já integrada, alterar a hora civil para frente/para
trás mantendo contexto válido: conferir desatualização sem modificar eventos;
suspender/retomar e conferir perda de continuidade. Nova referência só afeta
futuras marcações. Os bloqueios antigos de dia/jornada podem interferir, conforme
descrito acima. Não há integração direta com PostgreSQL/Supabase, sync geral,
login, provisionamento, worker ou alteração remota nesta entrega.

APIs consultadas: [Stopwatch](https://api.dart.dev/dart-core/Stopwatch-class.html)
e [migrações Drift](https://drift.simonbinder.eu/migrations/api/).
