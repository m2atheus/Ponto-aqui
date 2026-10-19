# Ponto Aqui — incompatibilidades e integração futura

O parser `app/services/ponto_payload.py` exige desvio inteiro assinado e offline
booleano: rejeita null/ausência. A captura local representa ausência de
amostra de relógio/conectividade sem fabricar evidências. `w09Payload()` bloqueia
serialização desses eventos. Não se deve converter ausência em zero/false ou
recalcular dados após captura. A equipe precisa definir tratamento contratual
antes do transporte futuro. Nenhuma alteração unilateral foi feita no backend.

W08 usa `clockOffsetMs = serverTimestampUtc - deviceUtcAtReceipt`. Positivo significa
aparelho atrasado. Conversão `offsetMs ~/ 1000`, truncando para zero e preservando
sinal: +1599 ms → +1 s; -1599 ms → -1 s. Offset UTC é um campo distinto. Timestamp
e idade da amostra são congelados; a medida contém latência e pode envelhecer.

`w09Payload()` contém apenas evento_cliente_id, dispositivo_id, alocacao_id, tipo,
ocorrido_em, desvio_relogio_segundos, registrado_offline e posicao. Metadados ficam
fora do JSON HTTP. Eventos demo são bloqueados mesmo com medições completas.

usuario_id = Usuarios.id; funcionario_id = Funcionarios.id. dispositivo_id = linha
previamente autorizada; device_uuid = instalação, utilizada no header W08. O futuro
bootstrap deve canonicalizar a origem da API (sem aliases/paths/barra final variantes).

O futuro transportador consulta `pending(scope)` somente na sessão correspondente.
Evidências são imutáveis; somente `transport` pode receber estado/tentativas/falhas/
confirmação remota. Não existe envio HTTP nesta etapa.

## Proposta para evidência de relógio desconhecida

Proposta para análise do responsável pelo backend, **não implementada**:

- Parser: permitir `desvio_relogio_segundos: null` de forma explícita, mantendo
  inteiro assinado quando conhecido; definir se ausência deve continuar inválida.
- Schema: permitir null sem default zero em `RegistrosPonto.desvio_relogio_segundos`;
  migration e compatibilidade com consumidores precisam de revisão própria.
- Constraints: revisar `aceita_consistente` e tornar explícito que desconhecido
  não pode ser automaticamente aceito; SQL com NULL não deve aprovar por acidente.
- Classificação: propor `PendenteAnalise` com motivo específico de desvio desconhecido,
  preservando recusas por outras políticas. `Marcacao.desvio` precisaria aceitar
  ausência e `GeofencingService` deveria ramificar antes de executar `abs()`.
  Decisão final é da equipe de negócio.
- Serialização: retornar null de forma consistente nos resultados e adaptar o
  cliente somente após aprovação. A guarda atual de `w09Payload()` permanece.
- Hash idempotente: representar desconhecido como null canônico, distinto de zero;
  preservar a canonicalização/hashes dos eventos conhecidos já persistidos. Reenvio
  com UUID antigo e evidência diferente continua conflitante. Nenhuma amostra posterior
  pode preencher o desvio original desconhecido.

Conectividade desconhecida também é incompatível com o booleano obrigatório
preexistente; sua política pertence à integração de conectividade/transporte.
Os eventos ficam preservados e pendentes, sem transmissão artificial com zero/false.

O recebimento por evento é produzido pelo servidor, pode ser antigo em reenvios
e nunca é referência de hora atual. A matriz de fontes e a integração temporal
estão em [timekeeping.md](timekeeping.md).
