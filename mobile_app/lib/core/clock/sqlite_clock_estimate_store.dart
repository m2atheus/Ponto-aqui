import 'package:drift/drift.dart';

import '../../features/marcacoes/data/sqlite_mark_repository.dart';
import '../capture.dart';
import 'clock_service.dart';

class SqliteClockEstimateStore implements ClockEstimateStore {
  SqliteClockEstimateStore(this.db);
  final MarkDatabase db;
  @override
  Future<ClockEstimate?> load(String scope) async {
    final row = await db
        .customSelect(
          'SELECT * FROM clock_estimates WHERE scope = ?',
          variables: [Variable(scope)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return ClockEstimate(
      row.read<int>('offset_ms'),
      DateTime.parse(row.read<String>('measured_at')),
      serverTimestamp: DateTime.parse(row.read<String>('server_timestamp')),
      roundTripMs: row.read<int>('round_trip_ms'),
      source: row.read<String>('source'),
    );
  }

  @override
  Future<void> save(String scope, ClockEstimate estimate) =>
      db.transaction(() async {
        await db.customStatement(
          '''INSERT INTO clock_estimates
      (scope, offset_ms, measured_at, server_timestamp, round_trip_ms, source)
      VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(scope) DO UPDATE SET
      offset_ms=excluded.offset_ms, measured_at=excluded.measured_at,
      server_timestamp=excluded.server_timestamp, round_trip_ms=excluded.round_trip_ms,
      source=excluded.source''',
          [
            scope,
            estimate.offsetMs,
            estimate.measuredAt.toUtc().toIso8601String(),
            estimate.serverTimestamp!.toUtc().toIso8601String(),
            estimate.roundTripMs!,
            estimate.source,
          ],
        );
      });
}
