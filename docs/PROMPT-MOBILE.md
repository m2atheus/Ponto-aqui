# Prompt para desenvolver o aplicativo mobile Ponto Aqui

Atue como um Engenheiro de Software Sênior especialista em Flutter, Dart, arquitetura mobile, APIs REST, segurança e aplicações offline-first.

Seu objetivo é construir o aplicativo Android/iOS de ponto eletrônico **Ponto Aqui**, integrado ao backend Flask deste repositório. O app precisa registrar marcações sem internet e sincronizá-las posteriormente, preservando integralmente suas evidências.

Trabalhe no repositório existente, com implementações incrementais e verificáveis. Este texto orienta o desenvolvimento; o código atual e seus testes são a fonte de verdade dos contratos HTTP. Não implemente um sistema paralelo nem simule integrações inexistentes como se estivessem prontas.

## 1. Auditoria obrigatória antes de implementar

Leia primeiro:

- `README.md`.
- `app/__init__.py`: configuração JWT, limites HTTP e prefixos dos Blueprints.
- `app/models.py`: entidades, enums, restrições e isolamento.
- `app/routes/auth_routes.py`, `mobile_routes.py` e `web_routes.py`.
- `app/middleware/device_middleware.py`.
- `app/services/auth_service.py`, `device_service.py`, `mobile_sync_service.py`.
- `app/services/registro_ponto_service.py`, `ponto_payload.py`, `geofencing_service.py`, `selfie_service.py`.
- `app/services/check_schedule_conflict_service.py` e `app/utils/time_calculator.py`.
- `docs/W01-auth.md`, `docs/W04-W07-fundacao.md`, `docs/W08-sync.md`, `docs/W09.md`.
- `docs/examples/w08-pessoal.json` e `docs/examples/w08-relogio.json`.
- `tests/test_auth_w01.py`, `test_devices_w07.py`, `test_mobile_sync_w08.py`, `test_mobile_w09.py`, `test_time_calculator.py` e `test_schedule_conflicts_w05.py`.
- `admin_web/lib/models/mobile_sync_dto.dart` e `admin_web/lib/services/sync_service.dart`: modelos e sincronização reutilizáveis, já existentes.
- `admin_web/lib/theme/app_theme.dart` e `admin_web/assets/brand/`: identidade visual existente.

Se algum arquivo estiver indisponível, peça o conteúdo necessário. Se documentação e implementação divergirem, identifique a divergência e confirme o comportamento pelos Services, rotas e testes.

Não leia, copie ou exponha senhas, tokens reais, `.env` ou credenciais em `instance/`.

Produza um inventário inicial dos endpoints existentes, seus contratos e as lacunas que impedem os fluxos mobile. Não invente URLs, campos, refresh tokens ou permissões.

## 2. Arquitetura e stack do aplicativo

Crie um projeto Flutter separado, preferencialmente em `mobile_app/`, preservando o painel `admin_web/`.

Adote **MVVM**, com **Repository Pattern**, organização por funcionalidades e camadas de Presentation, Domain e Data. A separação de Views, ViewModels, Repositories e Services segue a orientação oficial do Flutter. Acrescente casos de uso onde houver coordenação complexa, especialmente captura e sincronização; evite abstrações sem utilidade.

Stack:

- Flutter/Dart com null safety; versões compatíveis verificadas no ambiente.
- `flutter_riverpod` para estado e injeção de dependências, usando Notifier/AsyncNotifier conforme o fluxo.
- `go_router` para navegação e proteção de rotas.
- `dio` para chamadas HTTP.
- Drift/SQLite para cache estruturado, histórico e fila transacional de marcações.
- `flutter_secure_storage` para JWT e identificadores sensíveis da sessão.
- `shared_preferences` apenas para preferências simples; não usar como banco da fila.
- UUID para identificação da instalação e de cada evento.
- Integrações de câmera, geolocalização e diretório privado de arquivos.
- Monitoramento de conectividade como sinal de tentativa de sincronização, nunca como prova de acesso à API.
- Biblioteca de timezone com suporte a zonas IANA para regras de escala da empresa.

Confirme as dependências e APIs na documentação oficial antes de escolher versões. Não instale pacotes obsoletos ou copie exemplos incompatíveis com o SDK.

Estrutura inicial:

```text
mobile_app/lib/
  main.dart
  app/
    app.dart
    router/
    theme/
  core/
    config/
    network/
    database/
    storage/
    device/
    clock/
    errors/
  features/
    auth/
      data/
      domain/
      presentation/
    bootstrap/
      data/
      domain/
      presentation/
    marcacoes/
      data/
      domain/
      presentation/
    sincronizacao/
      data/
      domain/
      presentation/
    escala/
      data/
      domain/
      presentation/
    relogio_setor/
      data/
      domain/
      presentation/
```

Widgets cuidam da apresentação. ViewModels expõem estado e ações. Casos de uso coordenam operações. Repositories conciliam fontes locais/remotas. Services e DataSources encapsulam HTTP, SQLite, câmera e GPS. Não colocar Dio, SQL ou regras de sincronização dentro dos Widgets.

## 3. Contexto do backend e limite de responsabilidade

O servidor usa Flask com Application Factory, Blueprints, Service Layer, SQLAlchemy, migrations, JWT e PostgreSQL hospedado no Supabase.

**O aplicativo conversa somente com a API Flask.** Não acessar tabelas pelo SDK Supabase, conectar ao PostgreSQL, usar Supabase Auth em substituição ao JWT Flask ou embutir senhas/chaves de backend no app.

Entidades relevantes:

- Empresas: isolamento e situação ativa/inativa.
- Usuarios: conta de autenticação, senha hash e papel.
- Funcionarios: cadastro funcional, matrícula única por empresa e vínculo opcional com Usuario.
- Setores: localização, raio e políticas de ponto.
- Escalas e Turnos: programação semanal/cíclica e horários.
- Alocacoes: funcionário, setor, escala e vigência histórica.
- Feriados e Afastamentos: contexto futuro de apuração, com regras no servidor.
- Dispositivos: aparelho pessoal ou relógio de setor.
- RegistrosPonto: evidências imutáveis.
- SelfiesPonto: fotos privadas vinculadas à marcação.
- JustificativasAjustes: fluxo de correções separado, W10.

Não confundir `usuario_id` com `funcionario.id`. Não confundir `dispositivo_id`, ID da linha no banco, com `device_uuid`, identificador da instalação. Eles podem coincidir em dados legados, mas o app não deve assumir isso.

A empresa e as permissões vêm da sessão validada pelo servidor. Separe banco/cache/filas por origem da API, empresa, usuário e aparelho. Uma troca de conta ou empresa nunca pode enviar eventos da sessão anterior.

## 4. Endpoints existentes e autenticação real

Use uma URL-base da origem do Flask, configurável por ambiente, por exemplo `https://api.exemplo.com`. Existem dois prefixos mobile diferentes: não acrescentar `/api/v1` indiscriminadamente a todas as rotas.

Rotas atuais:

| Método | Caminho | Finalidade |
| --- | --- | --- |
| POST | /api/mobile/auth/login | Login Flask |
| GET | /api/mobile/auth/me | Perfil validado pelo servidor |
| GET | /api/v1/mobile/sync | Carga inicial W08 |
| POST | /api/mobile/marcacoes/lote | Sincronização W09 |
| POST | /api/mobile/marcacoes/{evento_cliente_id}/selfie | Upload da selfie |

O mesmo Auth Blueprint possui aliases `/auth` e `/api/web/auth`; mantenha no app o prefixo mobile.

Login atual:

```json
{
  "email": "funcionario@empresa.exemplo",
  "senha": "SENHA_DO_USUARIO",
  "dispositivo_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
}
```

`dispositivo_id` precisa corresponder a um aparelho previamente cadastrado, ativo e vinculado à conta/empresa. O AuthService atual não aceita novos campos como `device_uuid` ou `nome_dispositivo` nesse body.

Resposta de sucesso:

```json
{
  "access_token": "JWT_EMITIDO_PELO_FLASK",
  "token_type": "Bearer",
  "usuario": {
    "id": "22222222-2222-4222-8222-222222222222",
    "nome": "Ana Silva",
    "email": "funcionario@empresa.exemplo",
    "papel": "FUNCIONARIO",
    "empresa_id": "99999999-9999-4999-8999-999999999999"
  }
}
```

- `/me` devolve `{"usuario": {...}}`.
- Papéis da resposta de autenticação: `SUPERADMIN`, `RH`, `GESTOR`, `FUNCIONARIO`, `USUARIO_SETOR`.
- Login inválido retorna HTTP 401 com `erro.codigo = LOGIN_INVALIDO` e mensagem genérica **Usuário ou senha inválidos**.
- Usuário ou empresa inativos também impedem login.
- Access token tem validade padrão de 30 minutos.
- A configuração de expiração de refresh token existe, mas atualmente não há endpoint de renovação nem emissão de refresh token nessa resposta.
- Não implementar chamadas fictícias a `/refresh`.
- Enviar `Authorization: Bearer TOKEN` nas requisições protegidas.
- Enviar `X-Device-UUID` no sync; pode padronizar o header nas demais chamadas mobile, sabendo que W09 valida atualmente os IDs no payload/JWT.
- HTTP 401 exige reautenticação, mantendo as evidências locais pendentes.
- HTTP 403 exige distinguir autorização negada/aparelho revogado de falhas de rede.

Armazene o token de forma segura, restrinja seu envio à origem configurada e não registre senha/JWT em logs. O interceptor deve evitar loops de login e tentativas ilimitadas de autenticação.

Não reutilize automaticamente o cliente Dio do painel: ele injeta a sessão administrativa e pode substituir o token mobile.

## 5. Dispositivos W07 e integrações ainda pendentes

O `device_uuid` deve ser um UUID estável gerado para a instalação. Não exigir IMEI, MAC ou identificadores de hardware restritos. Não gerar um UUID novo a cada abertura ou retransmissão.

No banco:

- `PESSOAL`: vinculado à conta do funcionário.
- `RELOGIO`: vinculado ao setor.
- UUID sozinho não autentica o usuário nem comprova fisicamente o aparelho.

O sync confere que o `device_uuid` do header corresponde ao `dispositivo_id` autorizado no JWT.

O Service `DeviceService.registrar_login_pessoal` já registra o novo aparelho e revoga outros pessoais ativos do mesmo usuário, mas **ainda não está integrado ao endpoint de login atual nem exposto por uma rota HTTP de provisionamento**.

Para relógio, o sync exige papel `USUARIO_SETOR` e claim `setor_id`. **O login atual não implementa esse fluxo de emissão de token de setor.**

Antes de prometer primeiro acesso completo:

1. Identifique como obter o ID cadastrado do dispositivo e como provisionar a instalação.
2. Documente as alterações mínimas necessárias no backend.
3. Se propondo integrar registro/revogação ao login, apresente um contrato explícito e preserve compatibilidade.
4. Não liberar marcações com UUID inventado ou token fabricado para contornar a pendência.

A funcionalidade desejada de sair do modo relógio com senha do gestor requer autenticação no servidor. Não armazenar nem verificar localmente a senha do gestor. Essa integração deve ser especificada separadamente.

## 6. Bootstrap W08 e DTOs

`GET /api/v1/mobile/sync` exige JWT válido e dispositivo autorizado.

Campos comuns:

- `server_timestamp`: UTC ISO 8601 com sufixo Z; também enviado em `X-Server-Timestamp`.
- `data_referencia`: data civil no fuso da empresa.
- `fuso_horario`: identificador IANA.
- `modo_operacao`: `PESSOAL` ou `RELOGIO`.
- `status` e `mensagem_status`.

Modo pessoal:

- `funcionario`: id, usuario_id opcional, nome, matricula, cargo opcional.
- `setor` e `escala`: podem ser nulos.
- `alocacoes`: todos os vínculos vigentes, com id, data_inicio, data_fim opcional, setor e escala opcional.
- `marcacoes_recentes`: até 20 registros recebidos nos últimos sete dias.
- Com várias alocações, setor/escala do resumo podem ser nulos; consultar a lista e oferecer escolha do vínculo correto.

Setor:

- id, nome, latitude, longitude e raio_metros.
- `politicas.exige_selfie`.
- `politicas.acao_fora_perimetro`: `BLOQUEAR` ou `PENDENTE`.
- `politicas.ignorar_localizacao`.
- `politicas.limite_desvio_relogio_segundos`.

Escala:

- id, nome, modelo, data_referencia opcional, tolerancia_minutos e turnos.
- Turno: hora_inicio, hora_fim, tempo_intervalo em minutos, fim_dia_seguinte e dias_semana ISO 1–7.

Modo relógio:

- `setor`: vínculo do aparelho.
- `funcionarios`: lista com dados básicos e alocações.
- Cada alocação referencia `escala_id`, que pode ser nulo.
- `escalas`: catálogo das escalas referenciadas.
- Não esperar histórico de pontos de toda a equipe nesse payload.

Status informativos com HTTP 200:

`OK`, `SEM_ALOCACAO`, `SEM_FUNCIONARIO`, `SEM_ESCALA`, `ESCALA_SEM_TURNOS`, `MULTIPLAS_ALOCACOES` e `SEM_FUNCIONARIOS`.

Esses estados não são erros HTTP. Tratar nulos e listas vazias sem exceções e sem exibir “erro de conexão”. Um setor/escala nulo no resumo não significa necessariamente ausência de vínculos: observar status e alocacoes.

Construir DTOs tipados com parsing rigoroso de timestamps, enums, números e datas. Validar a carga inteira antes de substituir atomicamente o cache anterior. Em erro de parsing/rede, manter a última carga válida.

A API envia `Cache-Control: private, no-store`; persistir explicitamente a cópia offline, sem depender de cache HTTP.

## 7. Relógio do aparelho e escalas

A implementação Dart existente usa:

`clockOffsetMs = serverTimestampUtc - horarioLocalUtcNoRecebimento`.

Offset positivo indica celular atrasado; hora estimada do servidor = hora local UTC + offset.

Reaproveite esse contrato. Registre data da amostra e qualidade/idade da estimativa. A medida contém latência; se implementar uma estimativa por ponto médio da requisição, explique a mudança e teste sua compatibilidade.

Não alterar o relógio do sistema nem substituir a hora original capturada. Guarde hora do aparelho, offset estimado e informação de disponibilidade da amostra no registro local.

O W09 exige `desvio_relogio_segundos` como inteiro assinado, diferente do offset do fuso. O servidor avalia seu valor absoluto. Documente e teste a convenção de sinal adotada pelo cliente e a conversão ms→s; não converter automaticamente ausência de amostra em desvio zero.

Se não existir primeira carga válida, não inventar empresa, aparelho, alocação ou relógio confiável. Apresente o estado e a necessidade de provisionamento/sincronização inicial. Uma política para cache vencido ou amostra desconhecida precisa ser definida explicitamente; não inventar uma regra silenciosa.

Regras de escala para exibição offline:

- Modelos: 12x36, 24x72, Diurno e 5x2.
- `Legado` é compatibilidade: não inferir turnos desconhecidos.
- 19:00→07:00 cruza meia-noite, mesmo quando fim_dia_seguinte=false.
- Início igual ao fim só representa 24 horas quando fim_dia_seguinte=true.
- Intervalo em minutos reduz jornada líquida, sem deslocar o ciclo.
- Ciclo 12x36: novos inícios a cada 48 horas reais; 24x72: a cada 96.
- Usar data de referência e fuso da empresa, não somente o calendário local do celular.
- Preservar a madrugada de turno iniciado no dia anterior.
- Alocações têm datas de início/fim inclusivas; fim nulo significa vigência aberta.
- Uma escala pode estar presente no sync em dia de folga.
- Conflitos usam intervalos [início, fim): terminar e começar exatamente às 19:00 não sobrepõe.
- A validação definitiva de conflitos e a apuração de feriados, afastamentos e histórico pertencem ao backend.

Não tratar a carga de hoje como garantia de dados completos para todos os dias futuros. Identificar sua vigência e avisar quando estiver desatualizada.

## 8. Captura e fila offline de marcações

A marcação deve ser registrada localmente **antes** da chamada de rede. A confirmação visual “salva no aparelho” só aparece após persistência transacional; nunca confundir isso com aprovação pelo servidor.

Cada evento recebe UUID v4 único no momento da captura, preservado em todas as tentativas.

Persistir:

- Escopo da sessão: origem da API, empresa, conta e aparelho.
- evento_cliente_id, dispositivo_id, alocacao_id e tipo.
- Hora original com timezone explícito.
- Desvio congelado na captura e registrado_offline original.
- Posição, precisão e evidências de permissão indisponível quando aplicável.
- Caminho privado da selfie e bytes finais preparados para upload.
- Metadados de transporte: estado, tentativas, última falha e confirmação remota.

Manter o payload da evidência imutável após captura. Estado de transporte pode mudar sem reescrever o evento. Não recalcular desvio, GPS, hora ou flag offline no reenvio.

Não usar lista em memória como fila definitiva. Usar SQLite com transações e unicidade por escopo/UUID. Um encerramento do app ou reinício do aparelho não pode perder eventos.

Distinguir transporte (`na_fila`, `enviando`, `confirmada`, `erro_requer_acao`) de situação de negócio (`Aceita`, `PendenteAnalise`, `Recusada`). Fotos possuem fila própria.

## 9. Contrato exato W09

`POST /api/mobile/marcacoes/lote`:

```json
{
  "marcacoes": [
    {
      "evento_cliente_id": "f3a06375-02eb-4d08-81d2-ff06f1b3039a",
      "dispositivo_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "alocacao_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      "tipo": "Entrada",
      "ocorrido_em": "2026-10-06T08:00:00-03:00",
      "desvio_relogio_segundos": -15,
      "registrado_offline": true,
      "posicao": {
        "latitude": -8.0,
        "longitude": -35.0,
        "precisao_metros": 5
      }
    }
  ]
}
```

UUIDs acima são ilustrativos. Enviar IDs reais da sessão e da alocação. Aceita também um array direto; padronize o wrapper mostrado.

Tipos exatos: `Entrada`, `InicioIntervalo`, `FimIntervalo`, `Saida`.

`posicao` pode ser omitida/nula. GPS, quando enviado, exige latitude e longitude numéricas; precisão é opcional.

Não enviar situação, distância calculada, empresa_id, usuario_id, recebido_em ou outros campos não previstos. O parser rejeita campos desconhecidos. Campos internos da fila nunca entram no JSON HTTP.

Limites atuais: 500 eventos por lote e 5 MiB por requisição. Use lotes menores e configuráveis para redes instáveis.

O servidor retorna `resultados`, preservando índices e UUIDs:

- HTTP global 200: todos reconhecidos/persistidos.
- HTTP global 207: existe erro individual; processar cada resultado.
- HTTP por item 201: novo registro persistido.
- HTTP por item 200: duplicata reconhecida, com conteúdo original.
- HTTP por item 409: UUID conflitante.
- HTTP por item 422: payload inválido.
- HTTP por item 404: alocação inválida ou inacessível.

Itens persistidos incluem registro_id, evento_cliente_id, persistida, duplicada, situacao, motivos, ocorrido_em, recebido_em, offset_original_minutos, desvio_relogio_segundos, registrado_offline e distancia_centro_metros.

Somente `persistida:true` com resultado coerente identifica confirmação da evidência. Uma situação `Recusada` persistida é confirmada no transporte; não deve ser reenviada indefinidamente.

Timeout, ausência de resposta, falha de conexão e HTTP 503 mantêm os mesmos eventos para retry. Aplicar backoff exponencial com jitter, limite de tentativas por ciclo e sincronização manual.

409/422/404 requerem tratamento específico, sem loop infinito nem geração de novo UUID para esconder o erro. Preservar a evidência para suporte.

Uma resposta parcial, truncada ou sem todos os UUIDs não confirma os eventos ausentes. Serializar confirmação e atualização da fila em transação local. Impedir workers concorrentes de dispararem os mesmos lotes, com recuperação de eventos presos em “enviando” após reinício.

O UUID identifica o evento, não a tentativa. A chave idempotente do servidor inclui empresa e UUID; reenvios com conteúdo diferente são rejeitados.

## 10. Geofencing e decisão do servidor

A distância definitiva é calculada pelo Flask, por Haversine. O aplicativo pode exibir orientação aproximada, mas não decidir definitivamente a situação nem descartar evidências porque prevê recusa.

Políticas:

- Dentro do raio e desvio dentro do limite: Aceita.
- Fora do raio/sem posição com PENDENTE: PendenteAnalise.
- Fora do raio/sem posição com BLOQUEAR: Recusada.
- ignorar_localizacao=true: aceita ausência de posição, sujeita às outras regras.
- Desvio absoluto acima do limite: pendência; igualdade ao limite ainda é permitida.
- Aparelho não autorizado: recusa.
- Recusa prevalece sobre pendência.

Motivos possíveis:

`APARELHO_NAO_REGISTRADO`, `FORA_DO_PERIMETRO`, `LOCALIZACAO_AUSENTE`, `DESVIO_RELOGIO_ACIMA_DO_LIMITE`.

Capturar GPS somente quando necessário ao fluxo, com permissões e timeout. Tratar permissão negada, localização desligada e baixa precisão claramente. Não falsificar coordenadas ou substituir uma captura ausente por 0,0.

## 11. Selfie e imutabilidade

Quando a política exigir selfie, implementar captura pela câmera no fluxo da marcação. A regra visual não equivale a uma validação de completude já implementada no servidor; conferir esse comportamento e registrar lacunas.

Upload:

`POST /api/mobile/marcacoes/{evento_cliente_id}/selfie`.

- multipart/form-data, campo exato `selfie`.
- Mesmo contexto JWT/aparelho da marcação.
- Enviar somente depois de confirmar que a marcação existe no servidor.
- JPEG ou PNG estático, até 2 MiB e 16 megapixels.
- Preparar/comprimir a foto uma vez; repetir exatamente os mesmos bytes.
- 201: primeira selfie; 200: duplicata reconhecida; 409: tentativa de substituir por outra imagem.
- Resposta: selfie_id, evento_cliente_id, sha256, content_type e duplicada.
- Falha no upload da foto não pode apagar nem recriar a marcação.

Guardar fotos em diretório privado persistente, não temporário sujeito a limpeza. Definir retenção após confirmação e proteção de dados locais sem perder evidências pendentes.

Marcações e selfies já recebidas são imutáveis. Não criar funcionalidades para editar/excluir pontos ou substituir selfies. Ajustes W10 são um fluxo separado, cujas rotas ainda precisam ser verificadas/definidas.

## 12. Operação pessoal, relógio e limitações atuais

Modo pessoal: funcionário vê sua identidade, vínculos, escala, marcações e fila; escolhe alocação quando houver mais de uma.

Modo relógio: mostrar setor e seleção de funcionários da carga, com UX apropriada para aparelho compartilhado.

**Importante:** o sync de relógio existe, mas o lote W09 e as selfies atuais autorizam somente o funcionário autenticado. Não aceitam `funcionario_id` arbitrário para a conta de setor.

Portanto, não simular o envio coletivo acrescentando campos ou trocando o JWT pelo UUID de um funcionário. Tratar essa funcionalidade como dependência de um contrato seguro adicional no backend.

Também não assumir endpoints de calendário, espelho, justificativas, feriados, afastamentos, troca de modo ou agenda somente porque existem modelos/Services correspondentes.

O catálogo completo inclui endpoints administrativos de empresas no Web; eles pertencem ao Superadmin e não fazem parte do app de batida do funcionário.

## 13. UX, segurança e ciclo de vida

Aplicar a marca existente: logo Ponto Aqui, azul-marinho `#0B3158`, turquesa `#008E89`, fundos claros e componentes consistentes. Priorizar português, legibilidade, acessibilidade e operação rápida com uma mão.

Telas planejadas:

1. Inicialização/restauração de sessão.
2. Login e estado de aparelho não provisionado.
3. Home pessoal com identificação, vínculo e ação principal.
4. Seleção de Entrada/Início de intervalo/Fim de intervalo/Saída.
5. Captura de localização e selfie conforme política.
6. Confirmação local e resultado de sincronização.
7. Histórico local/recentes, com situação e motivos.
8. Fila com quantidade pendente, última tentativa e sincronização manual.
9. Escala de trabalho/folga.
10. Modo relógio e seleção de funcionário, respeitando as lacunas descritas.

Não exibir “Ponto aceito” antes da decisão remota. Diferenciar “Salvo no aparelho”, “Sincronizado”, “Pendente de análise” e “Recusado”.

O primeiro login exige rede. Sessão/cache já validados podem dar suporte à operação offline conforme política definida, sem prometer aprovação futura. Expiração/revogação não pode apagar eventos locais.

Ao receber 401/403, suspender envios e tratar a sessão. Se o sync invalidar o cache de autorização, preservar separadamente a outbox. Reautenticar a mesma conta antes de reenviar. Logout/troca de conta devem preservar e isolar evidências pendentes, sem mantê-las visíveis a outro usuário.

Sincronizar na abertura, no retorno ao foreground, após captura online, na reconexão e por ação manual. Background é melhoria posterior: Android/iOS podem suspender tarefas; não prometer sincronização imediata com o app encerrado.

Em Android emulador, a API local pode exigir `10.0.2.2`; em aparelho físico, usar endereço acessível na rede e configuração restrita de desenvolvimento. Produção usa HTTPS. CORS do navegador não resolve acesso de rede de um aparelho nativo.

Não adicionar rastreamento contínuo nem biometria facial sem requisito explícito.

## 14. Verificação e critérios de aceite

Criar testes relevantes de domínio, repositórios, persistência, ViewModels e integração com HTTP falso, incluindo:

- DTOs pessoais/relógio, nulos, múltiplas alocações e valores inválidos.
- Offset positivo/negativo, ms→s, timezone e ausência de amostra.
- Turno 19:00→07:00, ciclo 12x36/24x72 e madrugada anterior.
- Fila após encerramento/reinício e rollback de persistência.
- Envio repetido sem trocar UUID ou payload.
- Timeout depois do commit remoto e reconhecimento da duplicata.
- Lote HTTP 207 com sucesso e falha por item.
- Eventos ausentes em resposta parcial.
- Recusa persistida sem retry infinito.
- 401/403 preservando outbox e impedindo envio entre contas/empresas.
- Geolocalização negada/dispensada por política.
- Selfie offline, retry com os mesmos bytes e upload após confirmação.
- Workers concorrentes, pausa/retorno do aplicativo e ausência de conectividade real.

Executar `flutter analyze` e testes adequados. Documentar comandos de instalação, geração de código Drift quando necessária, execução Android/iOS e configuração de ambientes.

Não aplicar migrations no Supabase online nem alterar contratos públicos sem apresentar o impacto e obter a autorização necessária.

## 15. Ordem das entregas

Não gere o aplicativo inteiro de uma vez. Desenvolva em etapas:

1. Auditoria dos contratos, mapa de dependências e arquitetura.
2. Fundação Flutter, tema, configuração, DTOs e persistência.
3. Login e provisionamento de dispositivo, resolvendo as dependências reais do backend.
4. Bootstrap/cache e relógio.
5. Captura transacional e fila offline.
6. Lotes idempotentes e confirmação por item.
7. Selfies e permissões.
8. Histórico e escalas.
9. Modo relógio após definição dos contratos pendentes.
10. Testes integrados e documentação.

**Na primeira resposta, entregue apenas:**

- Diagnóstico do que a API realmente suporta hoje e lacunas encontradas.
- Estrutura de diretórios e responsabilidades das camadas.
- Matriz de endpoints com payloads, respostas, headers e erros.
- Plano incremental com prioridades e critérios de aceite.

Aguarde minha validação dessa fundação antes de implementar telas e alterações de backend. Em cada etapa posterior, produza código compilável, explique as decisões relevantes e mostre a validação executada.

## Referências de arquitetura

- [Flutter: guia de arquitetura e MVVM](https://docs.flutter.dev/app-architecture/guide).
- [Flutter: funcionamento offline-first](https://docs.flutter.dev/app-architecture/design-patterns/offline-first).
- [Drift: transações locais](https://drift.simonbinder.eu/dart_api/transactions/).

