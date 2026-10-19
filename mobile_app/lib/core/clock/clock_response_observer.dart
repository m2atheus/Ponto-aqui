import '../capture.dart';
import 'clock_service.dart';

// Adapter for a future HTTP response hook. Does not issue requests or read receipts.
class ClockResponseObserver {
  ClockResponseObserver({required this.service, required this.apiOrigin});
  final ClockService service;
  final Uri apiOrigin;
  ClockMoment begin() => service.read();

  Future<MeasurementResult> response({
    required Uri uri,
    required int statusCode,
    required ClockMoment sent,
    required ClockMoment received,
    Map<String, String> headers = const {},
    Map<String, Object?> body = const {},
  }) async {
    if (!['http', 'https'].contains(apiOrigin.scheme) ||
        uri.origin != apiOrigin.origin) {
      return MeasurementResult.wrongOrigin;
    }
    if (statusCode < 200 || statusCode >= 300) {
      return MeasurementResult.missingReference;
    }
    final headerValues = headers.entries
        .where((e) => e.key.toLowerCase() == 'x-server-timestamp')
        .toList();
    if (headerValues.length > 1) return MeasurementResult.invalidReference;
    final header = headerValues.isEmpty ? null : headerValues.single.value;
    final payload = uri.path == '/api/v1/mobile/sync'
        ? body['server_timestamp']
        : null;
    if (header == null && payload == null) {
      return MeasurementResult.missingReference;
    }
    DateTime? parse(Object? raw) =>
        raw is String && raw.endsWith('Z') ? parseExplicitTimestamp(raw) : null;
    final headerTime = parse(header);
    final payloadTime = parse(payload);
    if ((header != null && headerTime == null) ||
        (payload != null && payloadTime == null) ||
        (headerTime != null &&
            payloadTime != null &&
            headerTime != payloadTime)) {
      return MeasurementResult.invalidReference;
    }
    return service.observe(
      serverTimestamp: (headerTime ?? payloadTime)!,
      sent: sent,
      received: received,
      source: headerTime != null ? 'X-Server-Timestamp' : 'server_timestamp',
    );
  }
}
