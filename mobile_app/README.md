# Ponto-aqui mobile

Aplicativo independente Android/iOS: MVVM, Riverpod, Repository Pattern e SQLite
real via Drift. 

Tratamento do relógio, auditoria atual, matriz de endpoints, arquivos, sete critérios
e dependências: [evidência temporal](docs/timekeeping.md).

## Execução

Ambiente validado: Flutter 3.47.6 / Dart 3.13.5. Versões em `pubspec.lock`.

```powershell
cd mobile_app
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d <id-do-aparelho> --dart-define=PONTO_AQUI_DEMO=true
```

`cd mobile_app` seleciona o projeto mobile. `flutter pub get` resolve as dependências
fixadas. `flutter analyze` verifica tipos e lints. `flutter test` executa as suítes
locais e de widgets. `flutter devices` lista alvos disponíveis. `flutter run` inicia
a demonstração debug no alvo escolhido, sem habilitar dados fictícios em release.

Android requer Android SDK; iOS requer macOS/Xcode. Não existe alvo Web.
Drift utiliza sua API SQL: não é necessário gerar código.
Referência da API utilizada: [SQL personalizado](https://drift.simonbinder.eu/sql_api/custom_queries/)
e [transações Drift](https://drift.simonbinder.eu/dart_api/transactions/).
Sem flag, a tela explica que primeiro acesso requer internet, autenticação e aparelho
previamente cadastrado. Em release, a flag é ignorada. O contexto fictício utiliza
origem `demo://ponto-aqui` e IDs `demo-*`, identificados visualmente como teste; não são
credenciais nem dispositivos autorizados. Eventos demo não podem gerar payload W09.

## Diagnóstico da auditoria

Em 13/10/2026, não havia app mobile: apenas `admin_web/`. Foram examinados README,
PROMPT-MOBILE, W08/W09, models, rotas, Services, middleware de aparelho, contratos e
testes do backend, DTO/sync/tema do painel. Working tree inicial limpo.
O símbolo da marca foi copiado do painel, sem alteração de sua origem.

| Endpoint existente | Contrato | Dependência |
| --- | --- | --- |
| POST `/api/mobile/auth/login` | email, senha, dispositivo_id; JWT Flask e usuario | Aparelho pessoal previamente cadastrado |
| GET `/api/mobile/auth/me` | JWT; usuario validado no servidor | Restauração segura de sessão |
| GET `/api/v1/mobile/sync` | JWT + X-Device-UUID; fuso IANA, data_referencia, funcionario, alocacoes, server_timestamp | Bootstrap/cache W08 validado |
| POST `/api/mobile/marcacoes/lote` | UUIDs, tipo, ocorrido_em com timezone, desvio inteiro, offline booleano; posição opcional | Transporte W09 futuro |

W07 tem Service de cadastro/revogação, mas não provisionamento integrado ao login
por rota HTTP. O histórico W08 (até 20 eventos em sete dias) não substitui o banco
local. A descrição W09 que chama `sub` de UUID do funcionário deve ser interpretada
conforme o código: é Usuarios.id, não Funcionarios.id.
Incompatibilidades estão documentadas separadamente em [contracts.md](docs/contracts.md).

## Arquivos e responsabilidades

Todos os arquivos criados estão em `mobile_app/`. Nenhum arquivo preexistente do
backend, painel ou documentação raiz foi modificado. Os arquivos nativos gerados
incluem manifests, Gradle/Xcode, runners, ícones e recursos de plataforma.

| Arquivo/grupo | Responsabilidade |
| --- | --- |
| `lib/main.dart` | Inicialização Flutter, timezone e ProviderScope |
| `lib/app/app.dart` | Aplicação e tema #0B3158 / #008E89 |
| `lib/app/providers.dart` | Injeção Riverpod, contexto demo restrito, banco privado e conectividade |
| `lib/core/capture.dart` | Relógio substituível, data civil IANA, ISO com offset e conversão W08 |
| `lib/features/marcacoes/domain/mark.dart` | Tipos, escopo, vigência/alocação, evento imutável e interface de Repository |
| `lib/features/marcacoes/data/sqlite_mark_repository.dart` | Schema v2, SQLite, transações, histórico/outbox e integridade |
| `lib/features/marcacoes/presentation/mark_view_model.dart` | Captura, estado visual, concorrência, confirmação e erros |
| `lib/features/marcacoes/presentation/mark_screen.dart` | Tela responsiva, etapas, horários, mensagens acessíveis e diálogo |
| `test/marcacoes_test.dart` | Domínio, ViewModel, SQLite em memória/arquivo e widgets |
| `assets/brand/ponto_aqui_symbol.png` | Identidade visual existente |
| `android/`, `ios/` | Scaffolds Flutter; nome visível Ponto-aqui |
| `pubspec.yaml`, `pubspec.lock` | Dependências e versões resolvidas |
| `analysis_options.yaml`, `.gitignore`, `.metadata` | Lints, exclusões e metadados Flutter |
| `README.md`, `docs/contracts.md` | Execução, entrega, roteiro e incompatibilidades |

GoRouter e Dio ficam para histórias com navegação/HTTP: esta entrega tem uma única
tela e nenhum envio. Não há geração de código Drift nem SharedPreferences.

## Fluxo completo

1. Capturar imediatamente hora do toque e observação de conectividade, antes de await.
2. Determinar data no fuso da empresa, validar vigência/alocação e consultar os
   registros SQLite do escopo origem API/empresa/conta/aparelho.
3. Reconstruir próxima etapa, gerar UUID v4 e congelar evidências originais: IDs,
   instante UTC, ISO com offset, amostra/desvio disponíveis, offline, posição e criação.
4. Dentro da transação, verificar novamente sequência e última batida. Inserir
   evidência e metadados `na_fila` atomicamente. Restrições impedem repetir etapa/UUID.
5. Após commit, incluir o evento persistido na tela com sua hora original e mostrar
   “Ponto salvo no aparelho”. Nenhuma requisição HTTP é feita.
6. Em erro/rollback, manter a etapa anterior e informar falha. Desabilitar botão
   e novos acionamentos no ViewModel durante toda a operação.

Janela suspeita padrão: 30 segundos, configurável por injeção. O diálogo informa
o próximo tipo. Cancelar não persiste; confirmar preserva a hora do toque inicial,
mesmo após esperar no diálogo. Mudança de dia durante o diálogo exige novo toque.
Recuo do relógio também exige confirmação. A proteção é revalidada no repositório.

Novas instalações usam `ponto_aqui.sqlite` no diretório privado de suporte do app.
Instalações anteriores reutilizam seu banco existente para preservar evidências.
Evidências ficam em
`marks` (triggers rejeitam UPDATE/DELETE); metadados ficam em `transport`.
`pending(scope)` permite consulta futura sem reescrever eventos. Não existe worker
nem confirmação de aceitação pelo servidor. Reabrir reconstrói a tela pelo SQLite.

## Sete critérios de aceite

O pedido não enumera sete critérios textuais separados. Este agrupamento mantém
os requisitos e os quinze cenários solicitados. Testes em `test/marcacoes_test.dart`.

| Critério | Arquivos | Testes |
| --- | --- | --- |
| CA1 Tela vazia com Entrada esperada | Screen, ViewModel.load | `CA1 empty SQLite...`, widget `CA1 CA3 CA4 screen...` |
| CA2 Progressão de quatro etapas e conclusão | MarkType, Repository, ViewModel.next | `CA2 CA3 CA4 CA5 four single taps...`, bloqueio da quinta etapa |
| CA3 Registro com um toque normal | register, append, Screen | Testes de quatro toques e widget usando SQLite |
| CA4 Horário original e sucesso após commit | capture.dart, save, Mark | Widget, `concurrent taps blocked...`, `time passing...`, ISO com offset/microssegundos |
| CA5 UUID único e duplicidades protegidas | UUID, transação/restrições | Quatro UUIDs v4, duas VMs, repetição de etapa, confirmação/cancelamento, imutabilidade |
| CA6 Offline, sem HTTP e falha honesta | Repository, providers | Evidências offline/desconhecidas, HTTP proibido, rollback real de marks+transport |
| CA7 Persistência e recuperação | SQLite em arquivo, load | Fechar/reabrir arquivo real, isolamento de conta/API/empresa/aparelho e mudança de dia |

Há testes adicionais de vigência, múltiplas alocações, fuso diferente do aparelho,
contexto vencido, limitação de meia-noite, conversão W08, filtragem W09 e demo em
produção. Relógio e repositório são substituíveis. O teste de recuperação usa arquivo
SQLite real; testes não simulam persistência com listas.

## Validação e limites

Em 19/10/2026, após o tratamento temporal: `flutter analyze` **sem problemas** e
`flutter test --reporter expanded` **52 testes aprovados, nenhum ignorado**.
Esse comando de teste executa as suítes com saída detalhada. Inclui regressão das
marcações, relógio, widgets, reabertura de SQLite e migração real de schema 1 para 2
preservando evidências e metadados da fila. Sem execução física ou integração HTTP
real com Flask/PostgreSQL nesta entrega.

Validação executada em 13/10/2026: `flutter pub get` concluído;
`flutter analyze` **sem problemas**; `flutter test` **28 testes aprovados**.
Inclui dois testes de widget e persistência em arquivo SQLite real.
As falhas iniciais de asserções/rolagem nos testes foram corrigidas e a suíte final
foi reexecutada com sucesso. Não houve validação de integração HTTP com o backend.
`flutter doctor -v` não encontrou Android SDK. Não foi validado APK ou execução em
aparelho/iOS neste Windows. O roteiro abaixo aguarda um ambiente mobile preparado.

- Produção não tem contexto até autenticação/bootstrap W07/W08. Ponto de integração:
  `employeeContextProvider`, a ser substituído por contexto confiável e cache validado.
- Múltiplas alocações exigem ID previamente selecionado e vigente; sem ele, a tela
  informa necessidade de seleção e bloqueia captura. Não há tela de gestão de vínculos.
- Demo avança a data civil. Contexto real com data W08 vencida bloqueia captura até
  atualização: política explícita, sem supor validade futura da carga.
- Jornadas que cruzam meia-noite são bloqueadas explicitamente (`crossesMidnight`)
  até existir contexto confiável de jornada. O integrador deve sinalizar isso a partir
  da escala W08. Nenhuma marcação de madrugada é associada por inferência a outro dia.
- Sem GPS/câmera: posição, precisão e selfie ausentes. Futuro servidor poderá recusar
  conforme política do setor. Nenhuma evidência é fabricada.
- Conectividade observa interfaces, não acesso à API. Desvio desconhecido é nulo;
  amostra/idade são preservadas, sem recalcular o payload após captura.
- Um ciclo de quatro etapas por escopo/data. Etapas extras dependem de outra história.
- Não implementados: login/provisionamento, sync W09, selfie, modo relógio, escalas,
  justificativas, ajustes, relatórios ou espelho. Nenhuma integração real foi testada.

## Roteiro manual em modo avião

1. Executar debug com PONTO_AQUI_DEMO=true e conferir identificação de teste.
2. Ativar modo avião e desligar Wi-Fi. Encerrar/reabrir: tela funciona sem backend.
3. Tocar uma vez em Entrada. Conferir horário original e mensagem de persistência.
4. Tocar imediatamente na próxima etapa: verificar o tipo no diálogo. Cancelar
   não cria ponto; repetir/confirmar cria somente uma etapa.
5. Esperar mais de 30 segundos entre próximas batidas. Concluir as quatro, verificar
   mensagem de conclusão e botão desabilitado.
6. Forçar encerramento e reabrir ainda offline; conferir mesmos horários/etapas.
   Reiniciar o aparelho e repetir a conferência.
7. No próximo dia civil da empresa, verificar Entrada disponível. Dados anteriores
   permanecem no banco; esta história não possui tela de histórico completo.
8. Sair do modo avião: nenhum envio deve ocorrer.
9. Executar sem flag, ou release com flag: conferir bloqueio do contexto fictício.

Não limpar dados/desinstalar durante a recuperação: isso remove o banco privado.
Nenhum commit, push, merge, PR ou alteração de remoto foi realizado.
