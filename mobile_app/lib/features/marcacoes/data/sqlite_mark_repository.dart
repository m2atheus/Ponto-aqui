import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/mark.dart';

// Drift low-level SQL API; no code generation is required.
class MarkDatabase extends GeneratedDatabase {
  MarkDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement('''CREATE TABLE marks (
      scope TEXT NOT NULL, event_id TEXT NOT NULL, day TEXT NOT NULL,
      step INTEGER NOT NULL CHECK(step BETWEEN 0 AND 3),
      instant_us INTEGER NOT NULL, evidence TEXT NOT NULL,
      PRIMARY KEY(scope, event_id), UNIQUE(scope, day, step))''');
      await customStatement('''CREATE TABLE transport (
      scope TEXT NOT NULL, event_id TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'na_fila', attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT, acknowledged_at TEXT,
      PRIMARY KEY(scope, event_id),
      FOREIGN KEY(scope,event_id) REFERENCES marks(scope,event_id))''');
      await customStatement(
        "CREATE TRIGGER immutable_marks_update BEFORE UPDATE ON marks BEGIN SELECT RAISE(ABORT, 'immutable evidence'); END",
      );
      await customStatement(
        "CREATE TRIGGER immutable_marks_delete BEFORE DELETE ON marks BEGIN SELECT RAISE(ABORT, 'immutable evidence'); END",
      );
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA synchronous = FULL');
    },
  );
}

class SqliteMarkRepository implements MarkRepository {
  SqliteMarkRepository(this.db);
  final MarkDatabase db;
  Mark decode(QueryRow row) => Mark(
    scope: row.read<String>('scope'),
    day: row.read<String>('day'),
    type: MarkType.values[row.read<int>('step')],
    evidence: jsonDecode(row.read<String>('evidence')) as Map<String, dynamic>,
  );
  @override
  Future<List<Mark>> today(String scope, String day) async =>
      (await db
              .customSelect(
                'SELECT * FROM marks WHERE scope = ? AND day = ? ORDER BY step',
                variables: [Variable(scope), Variable(day)],
              )
              .get())
          .map(decode)
          .toList();
  @override
  Future<Mark?> latest(String scope) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM marks WHERE scope = ? ORDER BY rowid DESC LIMIT 1',
          variables: [Variable(scope)],
        )
        .get();
    return rows.isEmpty ? null : decode(rows.single);
  }

  @override
  Future<void> append(
    Mark mark, {
    required Duration suspiciousWindow,
    String? confirmedPreviousId,
  }) => db.transaction(() async {
    final rows = await today(mark.scope, mark.day);
    if (rows.length >= 4 || mark.type.index != rows.length) {
      throw StateError('A etapa mudou. Atualize as marcações.');
    }
    final previous = await latest(mark.scope);
    if (previous != null &&
        mark.instant.difference(previous.instant) < suspiciousWindow &&
        confirmedPreviousId != previous.id) {
      throw SuspiciousMark(previous, mark.type);
    }
    await db.customStatement('INSERT INTO marks VALUES (?, ?, ?, ?, ?, ?)', [
      mark.scope,
      mark.id,
      mark.day,
      mark.type.index,
      mark.instant.microsecondsSinceEpoch,
      jsonEncode(mark.evidence),
    ]);
    await db.customStatement(
      'INSERT INTO transport(scope,event_id) VALUES (?, ?)',
      [mark.scope, mark.id],
    );
  });
  @override
  Future<List<Mark>> pending(String scope) async =>
      (await db
              .customSelect(
                "SELECT m.* FROM marks m JOIN transport t ON m.scope=t.scope AND m.event_id=t.event_id WHERE m.scope=? AND t.state='na_fila' ORDER BY m.rowid",
                variables: [Variable(scope)],
              )
              .get())
          .map(decode)
          .toList();
}
