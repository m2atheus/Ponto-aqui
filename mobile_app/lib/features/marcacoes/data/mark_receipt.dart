import '../../../core/capture.dart';
import '../domain/mark.dart';

// Validation hook for a future transport. A receipt is not a current clock sample.
class MarkReceipt {
  const MarkReceipt._(
    this.eventId,
    this.deviceTime,
    this.driftSeconds,
    this.receivedAt,
    this.situation,
  );
  final String eventId;
  final DateTime deviceTime, receivedAt;
  final int driftSeconds;
  final String situation;

  factory MarkReceipt.verify(Mark mark, Map<String, Object?> response) {
    final original = mark.w09Payload();
    final occurred = parseExplicitTimestamp(response['ocorrido_em']);
    final receipt = parseExplicitTimestamp(response['recebido_em']);
    final drift = response['desvio_relogio_segundos'];
    final situation = response['situacao'];
    if (response['evento_cliente_id'] != mark.id ||
        response['persistida'] != true ||
        ![200, 201].contains(response['http_status']) ||
        occurred == null ||
        occurred != mark.instant ||
        receipt == null ||
        drift is! int ||
        drift != original['desvio_relogio_segundos'] ||
        response['offset_original_minutos'] !=
            mark.evidence['offset_original_minutos'] ||
        response['registrado_offline'] != original['registrado_offline'] ||
        !['Aceita', 'PendenteAnalise', 'Recusada'].contains(situation)) {
      throw const FormatException(
        'Confirmação temporal incompatível com a marcação original.',
      );
    }
    return MarkReceipt._(
      mark.id,
      occurred,
      drift,
      receipt,
      situation as String,
    );
  }
}
