import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_mobile/core/clock/sqlite_clock_estimate_store.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/data/sqlite_mark_repository.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/domain/mark.dart';

import 'support/clock_fakes.dart';

class LegacyMarkDatabase extends MarkDatabase {
  LegacyMarkDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      final schema = await File('test/fixtures/mark_schema_v1.sql')
          .readAsString();
      for (final statement in schema.split('-- split')) {
        await customStatement(statement);
      }
    },
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test(
    'schema v1 upgrade preserves original JSON, outbox and immutable triggers',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ponto-migration-',
      );
      final file = File('${directory.path}/existing.sqlite');
      final legacy = LegacyMarkDatabase(NativeDatabase(file));
      final scope = temporalEmployee().scope;
      final evidence = {
        'evento_cliente_id': 'original-event',
        'ocorrido_em': '2026-10-19T08:00:00.123456-03:00',
        'desvio_relogio_segundos': -15,
        'clock_estimate_state': 'available',
        'registrado_offline': true,
      };
      await SqliteMarkRepository(legacy).append(
        Mark(
          scope: scope,
          day: '2026-10-19',
          type: MarkType.entrada,
          evidence: evidence,
        ),
        suspiciousWindow: Duration.zero,
      );
      await legacy.customStatement(
        "UPDATE transport SET attempts=3, last_error='prior failure'",
      );
      final originalJson =
          (await legacy.customSelect('SELECT evidence FROM marks').getSingle())
              .read<String>('evidence');
      expect(
        (await legacy.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        1,
      );
      await legacy.close();
      final upgraded = MarkDatabase(NativeDatabase(file));
      try {
        final repo = SqliteMarkRepository(upgraded);
        expect((await repo.pending(scope)).single.evidence, evidence);
        expect(
          (await upgraded
                  .customSelect('SELECT evidence FROM marks')
                  .getSingle())
              .read<String>('evidence'),
          originalJson,
        );
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          2,
        );
        final transport =
            (await upgraded.customSelect('SELECT * FROM transport').getSingle())
                .data;
        expect(transport['attempts'], 3);
        expect(transport['last_error'], 'prior failure');
        expect(transport['state'], 'na_fila');
        final service = TestTime().service(
          store: SqliteClockEstimateStore(upgraded),
        );
        await measure(service, 7000);
        expect(
          (await SqliteClockEstimateStore(upgraded).load(scope))!.offsetMs,
          7000,
        );
        expect((await repo.pending(scope)).single.evidence, evidence);
        await expectLater(
          upgraded.customStatement('UPDATE marks SET evidence=evidence'),
          throwsA(anything),
        );
        await expectLater(
          upgraded.customStatement('DELETE FROM marks'),
          throwsA(anything),
        );
        expect(
          await upgraded.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await upgraded.close();
        for (final entry in await directory.list().toList()) {
          await entry.delete();
        }
        await directory.delete();
      }
    },
  );
}
