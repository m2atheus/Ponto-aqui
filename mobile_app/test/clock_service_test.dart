import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:ponto_aqui_mobile/core/capture.dart';
import 'package:ponto_aqui_mobile/core/clock/clock_service.dart';
import 'package:ponto_aqui_mobile/core/clock/clock_response_observer.dart';
import 'package:ponto_aqui_mobile/core/clock/sqlite_clock_estimate_store.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/data/sqlite_mark_repository.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/presentation/mark_view_model.dart';

import 'support/clock_fakes.dart';

void main() {
  tz.initializeTimeZones();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late TestTime time;
  late MarkDatabase db;
  late SqliteClockEstimateStore store;
  late ClockService service;
  late ClockResponseObserver observer;
  setUp(() {
    time = TestTime();
    db = MarkDatabase(NativeDatabase.memory());
    store = SqliteClockEstimateStore(db);
    service = time.service(store: store);
    observer = ClockResponseObserver(
      service: service,
      apiOrigin: Uri.parse('https://api.example'),
    );
  });
  tearDown(() async => db.close());

  test(
    'offset by receipt preserves both signs, truncation and request latency',
    () async {
      for (final offset in [1599, -1599, 999, -999, 0, 120999, -120999]) {
        final sent = observer.begin();
        time.advance(const Duration(milliseconds: 250));
        final received = service.read();
        final server = received.wall.add(Duration(milliseconds: offset));
        expect(
          await observer.response(
            uri: Uri.parse('https://api.example/api/v1/mobile/sync'),
            statusCode: 200,
            sent: sent,
            received: received,
            body: {'server_timestamp': server.toIso8601String()},
          ),
          MeasurementResult.accepted,
        );
        final sample = service.snapshot(service.read());
        expect(sample.estimate!.offsetMs, offset);
        expect(sample.estimate!.seconds, offset ~/ 1000);
        expect(sample.estimate!.roundTripMs, 250);
        time.advance(const Duration(seconds: 3));
        expect(service.snapshot(service.read()).ageMs, 3000);
        expect((await store.load(service.scope))!.offsetMs, offset);
      }
    },
  );

  test(
    'strict excess matches backend below equal above and negative',
    () async {
      for (final entry in {
        119999: false,
        120000: false,
        120999: false,
        121000: true,
        -121000: true,
        -120999: false,
      }.entries) {
        await measure(service, entry.key);
        expect(service.snapshot(service.read()).exceeds(120), entry.value);
      }
      expect(service.snapshot(service.read()).exceeds(null), false);
    },
  );

  test('current endpoints without time cannot supply a new estimate or reuse receipt', () async {
    await measure(service, 7000);
    for (final path in [
      '/api/mobile/auth/login',
      '/api/mobile/auth/me',
      '/api/mobile/marcacoes/lote',
      '/api/mobile/marcacoes/event/selfie',
    ]) {
      final sent = observer.begin();
      time.advance(const Duration(seconds: 1));
      expect(
        await observer.response(
          uri: Uri.parse('https://api.example$path'),
          statusCode: 200,
          sent: sent,
          received: service.read(),
          body: {
            'recebido_em': '2020-01-01T00:00:00Z',
            'server_timestamp': time.wall.value.toIso8601String(),
          },
        ),
        MeasurementResult.missingReference,
      );
    }
    expect(service.snapshot(service.read()).estimate!.offsetMs, 7000);
  });

  test(
    'header is case insensitive, payload must agree and origin must match',
    () async {
      final moment = observer.begin();
      final body = {'server_timestamp': '2026-10-19T11:00:05Z'};
      Future<MeasurementResult> response(
        Uri uri,
        Map<String, String> headers,
      ) => observer.response(
        uri: uri,
        statusCode: 200,
        sent: moment,
        received: service.read(),
        headers: headers,
        body: body,
      );
      final uri = Uri.parse('https://api.example/api/v1/mobile/sync');
      expect(
        await response(uri, {
          'x-server-timestamp': '2026-10-19T11:00:05.000000Z',
        }),
        MeasurementResult.accepted,
      );
      expect(
        await response(uri, {'X-Server-Timestamp': '2026-10-19T11:00:06Z'}),
        MeasurementResult.invalidReference,
      );
      expect(
        await response(
          Uri.parse('https://elsewhere.example/api/v1/mobile/sync'),
          {},
        ),
        MeasurementResult.wrongOrigin,
      );
      expect(
        await response(Uri.parse('http://api.example/api/v1/mobile/sync'), {}),
        MeasurementResult.wrongOrigin,
      );
      expect((await store.load(service.scope))!.offsetMs, 5000);
    },
  );

  test(
    'invalid absent and error references retain last valid persisted sample',
    () async {
      await measure(service, -12345);
      for (final value in [
        'garbage',
        '2026-10-19T11:00:00',
        '2026-02-30T11:00:00Z',
        '2026-10-19T25:00:00Z',
        '2026-10-19T11:00:00+00:00',
        123,
      ]) {
        final moment = observer.begin();
        expect(
          await observer.response(
            uri: Uri.parse('https://api.example/api/v1/mobile/sync'),
            statusCode: 200,
            sent: moment,
            received: moment,
            body: {'server_timestamp': value},
          ),
          MeasurementResult.invalidReference,
        );
      }
      final sent = observer.begin();
      expect(
        await observer.response(
          uri: Uri.parse('https://api.example/api/v1/mobile/sync'),
          statusCode: 503,
          sent: sent,
          received: service.read(),
          headers: {'X-Server-Timestamp': time.wall.value.toIso8601String()},
        ),
        MeasurementResult.missingReference,
      );
      // A transport timeout produces no response callback and no sample.
      await expectLater(
        Future<void>.error(TimeoutException('test timeout')),
        throwsA(isA<TimeoutException>()),
      );
      expect((await store.load(service.scope))!.offsetMs, -12345);
      expect(service.snapshot(service.read()).estimate!.offsetMs, -12345);
    },
  );

  test('storage failure leaves the previous sample intact', () async {
    await measure(service, 1000);
    await db.customStatement(
      "CREATE TRIGGER fail_clock BEFORE UPDATE ON clock_estimates BEGIN SELECT RAISE(ABORT, 'test disk failure'); END",
    );
    final moment = service.read();
    expect(
      await service.observe(
        serverTimestamp: moment.wall.add(const Duration(seconds: 9)),
        sent: moment,
        received: moment,
        source: 'server_timestamp',
      ),
      MeasurementResult.storageFailure,
    );
    expect(service.snapshot(service.read()).estimate!.offsetMs, 1000);
    expect((await store.load(service.scope))!.offsetMs, 1000);
  });

  test('wall jumps forward and backward invalidate current estimate until another sample', () async {
    for (final jump in [const Duration(hours: 1), const Duration(hours: -2)]) {
      await measure(service, 4000);
      time.wall.value = time.wall.value.add(jump);
      final snapshot = service.snapshot(service.read());
      expect(snapshot.availability, ClockAvailability.stale);
      expect(snapshot.estimate, isNull);
      expect(snapshot.lastEstimate!.offsetMs, 4000);
      await measure(service, 2000);
      expect(
        service.snapshot(service.read()).availability,
        ClockAvailability.available,
      );
    }
  });

  test(
    'civil change during communication rejects measurement and keeps history',
    () async {
      await measure(service, 5000);
      for (final change in [
        const Duration(minutes: 5),
        const Duration(minutes: -10),
      ]) {
        final sent = service.read();
        time.advance(const Duration(seconds: 1));
        time.wall.value = time.wall.value.add(change);
        final receipt = service.read();
        expect(
          await service.observe(
            serverTimestamp: DateTime.utc(2026, 10, 19, 11),
            sent: sent,
            received: receipt,
            source: 'server_timestamp',
          ),
          MeasurementResult.invalidContinuity,
        );
        expect(
          service.snapshot(service.read()).availability,
          ClockAvailability.stale,
        );
        expect((await store.load(service.scope))!.offsetMs, 5000);
      }
    },
  );

  test(
    'monotonic reset and application suspension never imply continuity',
    () async {
      await measure(service, 2000);
      time.mono.token = Object();
      expect(
        service.snapshot(service.read()).availability,
        ClockAvailability.stale,
      );
      await measure(service, 2000);
      time.advance(const Duration(seconds: 5));
      time.mono.value = Duration.zero;
      expect(
        service.snapshot(service.read()).availability,
        ClockAvailability.stale,
      );
      await measure(service, 2000);
      service.invalidateContinuity();
      expect(
        service.snapshot(service.read()).availability,
        ClockAvailability.stale,
      );
    },
  );

  test(
    'old suspended request cannot invalidate a newer accepted sample',
    () async {
      final old = service.read();
      service.invalidateContinuity();
      await measure(service, 3000);
      expect(
        await service.observe(
          serverTimestamp: old.wall,
          sent: old,
          received: service.read(),
          source: 'server_timestamp',
        ),
        MeasurementResult.invalidContinuity,
      );
      expect(service.snapshot(service.read()).estimate!.offsetMs, 3000);
    },
  );

  test('older response cannot replace newest sample', () async {
    final sent = service.read();
    time.advance(const Duration(seconds: 1));
    final oldReceipt = service.read();
    time.advance(const Duration(seconds: 1));
    await measure(service, 5000);
    expect(
      await service.observe(
        serverTimestamp: oldReceipt.wall,
        sent: sent,
        received: oldReceipt,
        source: 'server_timestamp',
      ),
      MeasurementResult.olderResponse,
    );
    expect((await store.load(service.scope))!.offsetMs, 5000);
  });

  test(
    'new reference and wall changes never rewrite old event evidence',
    () async {
      final repo = SqliteMarkRepository(db);
      final vm = MarkViewModel(
        repository: repo,
        context: temporalEmployee(),
        clock: time.wall,
        clockService: service,
        offline: () => true,
      );
      addTearDown(vm.dispose);
      await vm.load();
      await vm.register();
      final unknown = Map.of(vm.marks.single.evidence);
      expect(unknown['desvio_relogio_segundos'], isNull);
      time.advance(const Duration(minutes: 1));
      await measure(service, -15000);
      await vm.register();
      final known = Map.of(vm.marks.last.evidence);
      expect(known['desvio_relogio_segundos'], -15);
      time.wall.value = time.wall.value.add(const Duration(hours: 1));
      vm.refreshTime();
      await measure(service, 60000);
      final stored = await repo.today(service.scope, '2026-10-19');
      expect(stored.first.evidence, unknown);
      expect(stored.last.evidence, known);
    },
  );

  test(
    'scope isolates temporal state for API company account and device',
    () async {
      await measure(service, 2500);
      for (final employee in [
        temporalEmployee(origin: 'https://other.example'),
        temporalEmployee(company: 'other'),
        temporalEmployee(account: 'other'),
        temporalEmployee(device: 'other'),
      ]) {
        final other = time.service(scope: employee.scope, store: store);
        await other.restore();
        expect(
          other.snapshot(other.read()).availability,
          ClockAvailability.unmeasured,
        );
        expect(await store.load(employee.scope), isNull);
      }
    },
  );

  test(
    'real SQLite reopen preserves sample but does not persist monotonic anchor',
    () async {
      final directory = await Directory.systemTemp.createTemp('ponto-clock-');
      final file = File('${directory.path}/state.sqlite');
      final first = MarkDatabase(NativeDatabase(file));
      final writer = time.service(store: SqliteClockEstimateStore(first));
      await measure(writer, -5000);
      await first.close();
      final second = MarkDatabase(NativeDatabase(file));
      try {
        final reader = TestTime().service(
          store: SqliteClockEstimateStore(second),
        );
        await reader.restore();
        final restored = reader.snapshot(reader.read());
        expect(restored.lastEstimate!.offsetMs, -5000);
        expect(
          restored.lastEstimate!.serverTimestamp,
          DateTime.utc(2026, 10, 19, 10, 59, 55),
        );
        expect(restored.availability, ClockAvailability.stale);
        expect(restored.ageMs, isNull);
        expect(restored.estimate, isNull);
      } finally {
        await second.close();
        for (final entry in await directory.list().toList()) {
          await entry.delete();
        }
        await directory.delete();
      }
    },
  );

  test('imported estimate without live anchor is explicitly stale', () {
    final imported = time.service(seed: ClockEstimate(5000, time.wall.value));
    expect(
      imported.snapshot(imported.read()).availability,
      ClockAvailability.stale,
    );
  });
}
