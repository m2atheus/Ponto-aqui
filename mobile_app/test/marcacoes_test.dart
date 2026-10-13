import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as timezone;
import 'package:ponto_aqui_mobile/app/providers.dart';
import 'package:ponto_aqui_mobile/core/capture.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/data/sqlite_mark_repository.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/domain/mark.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/presentation/mark_screen.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/presentation/mark_view_model.dart';

class FakeClock implements Clock {
  FakeClock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}

EmployeeContext employee({
  String account = 'account',
  String origin = 'https://api.example',
  String company = 'company',
  String device = 'registered-device',
  List<Allocation>? allocations,
  String? selected,
  bool overnight = false,
  bool demo = true,
  ClockEstimate? estimate,
}) => EmployeeContext(
  apiOrigin: origin,
  companyId: company,
  userId: account,
  employeeId: 'employee-$account',
  deviceId: device,
  deviceUuid: 'installation',
  name: 'Funcionário de teste',
  zone: 'America/Sao_Paulo',
  referenceDate: '2026-10-13',
  allocations: allocations ?? [const Allocation('assignment', '2026-01-01')],
  selectedAllocationId: selected,
  crossesMidnight: overnight,
  isDemo: demo,
  estimate: estimate,
);

class ControlledRepository implements MarkRepository {
  ControlledRepository(this.delegate);
  final MarkRepository delegate;
  Completer<void>? gate;
  bool fail = false;
  int writes = 0;
  @override
  Future<void> append(
    Mark mark, {
    required Duration suspiciousWindow,
    String? confirmedPreviousId,
  }) async {
    writes++;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('disk full');
    await delegate.append(
      mark,
      suspiciousWindow: suspiciousWindow,
      confirmedPreviousId: confirmedPreviousId,
    );
  }

  @override
  Future<List<Mark>> today(String scope, String day) =>
      delegate.today(scope, day);
  @override
  Future<Mark?> latest(String scope) => delegate.latest(scope);
  @override
  Future<List<Mark>> pending(String scope) => delegate.pending(scope);
}

void main() {
  tz.initializeTimeZones();
  // Tests deliberately open independent executors; none shares a connection.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late MarkDatabase db;
  late SqliteMarkRepository repository;
  late FakeClock clock;
  late MarkViewModel vm;
  setUp(() async {
    db = MarkDatabase(NativeDatabase.memory());
    repository = SqliteMarkRepository(db);
    clock = FakeClock(DateTime.utc(2026, 10, 13, 11, 0, 0, 123));
    vm = MarkViewModel(
      repository: repository,
      context: employee(),
      clock: clock,
      offline: () => true,
    );
    await vm.load();
  });
  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  test('CA1 empty SQLite reconstructs Entrada', () {
    expect(vm.marks, isEmpty);
    expect(vm.next, MarkType.entrada);
    expect(vm.day, '2026-10-13');
  });
  test('CA2 CA3 CA4 CA5 four single taps persist original times and unique UUID v4', () async {
    final ids = <String>{};
    for (final type in MarkType.values) {
      expect(vm.next, type);
      final tapped = clock.value;
      await vm.register();
      final mark = vm.marks.last;
      expect(mark.type, type);
      expect(mark.instant, tapped);
      expect(mark.originalTime, '11:0${type.index}:00');
      expect(
        mark.id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      ids.add(mark.id);
      clock.value = clock.value.add(const Duration(minutes: 1));
    }
    expect(ids.length, 4);
    expect(vm.next, isNull);
    expect(vm.message, 'Ponto salvo no aparelho');
    await vm.register();
    expect((await repository.pending(employee().scope)).length, 4);
  });
  test(
    'CA6 offline evidence keeps unavailable clock and GPS, with no transport',
    () async {
      await vm.register();
      final mark = (await repository.pending(employee().scope)).single;
      expect(mark.evidence['registrado_offline'], true);
      expect(mark.evidence['desvio_relogio_segundos'], isNull);
      expect(mark.evidence['clock_estimate_state'], 'unmeasured');
      expect(mark.evidence['posicao'], isNull);
      expect(mark.w09Payload, throwsStateError);
    },
  );
  test('unknown connectivity is not fabricated as online', () async {
    final other = MarkViewModel(
      repository: repository,
      context: employee(),
      clock: clock,
      offline: () => null,
    );
    addTearDown(other.dispose);
    await other.load();
    await other.register();
    expect(other.marks.single.evidence['registrado_offline'], isNull);
  });
  test(
    'offline capture never opens HTTP before or after local persistence',
    () async {
      var requests = 0;
      await HttpOverrides.runZoned(
        () async {
          await vm.register();
          expect(vm.message, 'Ponto salvo no aparelho');
          expect((await repository.pending(employee().scope)).length, 1);
        },
        createHttpClient: (_) {
          requests++;
          throw StateError('HTTP forbidden during local capture');
        },
      );
      expect(requests, 0);
    },
  );
  test('CA7 real file SQLite survives close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp('ponto-aqui-test-');
    final file = File('${directory.path}/marks.sqlite');
    final first = MarkDatabase(NativeDatabase(file));
    final writer = MarkViewModel(
      repository: SqliteMarkRepository(first),
      context: employee(),
      clock: clock,
      offline: () => true,
    );
    await writer.load();
    await writer.register();
    final id = writer.marks.single.id;
    writer.dispose();
    await first.close();
    expect(await file.length(), greaterThan(0));
    final second = MarkDatabase(NativeDatabase(file));
    final reader = MarkViewModel(
      repository: SqliteMarkRepository(second),
      context: employee(),
      clock: clock,
      offline: () => true,
    );
    await reader.load();
    expect(reader.marks.single.id, id);
    expect(reader.next, MarkType.inicioIntervalo);
    expect(reader.marks.single.instant, clock.value);
    reader.dispose();
    await second.close();
    // Delete only the exact test files in the newly created temporary directory.
    for (final entry in await directory.list().toList()) {
      await entry.delete();
    }
    await directory.delete();
  });
  test('concurrent taps blocked and success waits for persistence', () async {
    final controlled = ControlledRepository(repository)
      ..gate = Completer<void>();
    final other = MarkViewModel(
      repository: controlled,
      context: employee(),
      clock: clock,
      offline: () => true,
    );
    addTearDown(other.dispose);
    await other.load();
    final first = other.register();
    await other.register();
    await Future<void>.delayed(Duration.zero);
    expect(controlled.writes, 1);
    expect(other.busy, true);
    expect(other.message, isNull);
    expect(await repository.pending(employee().scope), isEmpty);
    clock.value = clock.value.add(const Duration(hours: 2));
    controlled.gate!.complete();
    await first;
    expect(
      other.marks.single.instant,
      DateTime.utc(2026, 10, 13, 11, 0, 0, 123),
    );
    expect(other.message, 'Ponto salvo no aparelho');
  });
  test(
    'suspicious consecutive tap requires named explicit confirmation',
    () async {
      await vm.register();
      clock.value = clock.value.add(const Duration(seconds: 2));
      await vm.register();
      expect(vm.confirmation!.next, MarkType.inicioIntervalo);
      expect(vm.marks.length, 1);
      clock.value = clock.value.add(const Duration(seconds: 20));
      await vm.confirm(true);
      expect(vm.marks.length, 2);
      expect(vm.marks.last.instant, DateTime.utc(2026, 10, 13, 11, 0, 2, 123));
    },
  );
  test('cancel confirmation does not create a mark', () async {
    await vm.register();
    await vm.register();
    await vm.confirm(false);
    expect((await repository.pending(employee().scope)).length, 1);
    expect(vm.confirmation, isNull);
  });
  test('failed SQLite transaction rolls back evidence and transport', () async {
    await db.customStatement(
      "CREATE TRIGGER fail_transport BEFORE INSERT ON transport BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
    );
    await vm.register();
    expect(vm.error, contains('Não foi possível salvar'));
    expect(vm.message, isNull);
    expect(vm.marks, isEmpty);
    expect(await repository.today(employee().scope, vm.day!), isEmpty);
    expect(await repository.pending(employee().scope), isEmpty);
  });
  test('immutable SQLite evidence rejects update and delete', () async {
    await vm.register();
    expect(
      () => db.customStatement('UPDATE marks SET evidence = evidence'),
      throwsA(anything),
    );
    expect(() => db.customStatement('DELETE FROM marks'), throwsA(anything));
  });
  test('time passing and reload do not change original evidence', () async {
    await vm.register();
    final before = Map.of(vm.marks.single.evidence);
    clock.value = clock.value.add(const Duration(hours: 4));
    await vm.load();
    expect(vm.marks.single.evidence, before);
    expect(vm.next, MarkType.inicioIntervalo);
  });
  test(
    'scope isolates account, API, company and device in history and outbox',
    () async {
      await vm.register();
      for (final other in [
        employee(account: 'other'),
        employee(origin: 'https://other.example'),
        employee(company: 'other'),
        employee(device: 'other'),
      ]) {
        expect(await repository.today(other.scope, '2026-10-13'), isEmpty);
        expect(await repository.pending(other.scope), isEmpty);
      }
    },
  );
  test('day change retains previous evidence and starts new Entrada', () async {
    await vm.register();
    final id = vm.marks.single.id;
    clock.value = DateTime.utc(2026, 10, 14, 11);
    await vm.load();
    expect(vm.next, MarkType.entrada);
    await vm.register();
    expect(vm.marks.single.day, '2026-10-14');
    expect(
      (await repository.today(employee().scope, '2026-10-13')).single.id,
      id,
    );
  });
  test(
    'company zone controls day even when device UTC is on next day',
    () async {
      clock.value = DateTime.utc(2026, 10, 14, 1);
      await vm.load();
      await vm.register();
      expect(vm.marks.single.day, '2026-10-13');
      expect(vm.marks.single.occurredIso, endsWith('+00:00'));
    },
  );
  test('multiple allocations require selected valid allocation', () async {
    final allocations = [
      const Allocation('one', '2026-01-01'),
      const Allocation('two', '2026-01-01'),
    ];
    expect(
      () => employee(allocations: allocations).allocationOn('2026-10-13'),
      throwsStateError,
    );
    expect(
      employee(
        allocations: allocations,
        selected: 'two',
      ).allocationOn('2026-10-13').id,
      'two',
    );
    expect(
      () => employee(
        allocations: allocations,
        selected: 'absent',
      ).allocationOn('2026-10-13'),
      throwsStateError,
    );
  });
  test('expired allocation and stale real context block capture', () async {
    expect(
      () => employee(
        allocations: [const Allocation('old', '2026-01-01', end: '2026-10-12')],
      ).allocationOn('2026-10-13'),
      throwsStateError,
    );
    final other = MarkViewModel(
      repository: repository,
      context: employee(demo: false),
      clock: clock,
      offline: () => true,
    );
    addTearDown(other.dispose);
    clock.value = DateTime.utc(2026, 10, 14, 11);
    await other.load();
    expect(other.ready, false);
    expect(other.error, contains('desatualizado'));
  });
  test('overnight limitation is explicit and does not mix dates', () async {
    final other = MarkViewModel(
      repository: repository,
      context: employee(overnight: true),
      clock: clock,
      offline: () => true,
    );
    addTearDown(other.dispose);
    await other.load();
    expect(other.ready, false);
    expect(other.error, contains('meia-noite'));
  });
  test(
    'W08 signed milliseconds become W09 seconds, unknown remains absent',
    () {
      expect(ClockEstimate(1599, clock.value).seconds, 1);
      expect(ClockEstimate(-1599, clock.value).seconds, -1);
      expect(ClockEstimate(-999, clock.value).seconds, 0);
    },
  );
  test(
    'W09 payload excludes internal fields and preserves original evidence',
    () async {
      final other = MarkViewModel(
        repository: repository,
        context: employee(
          demo: false,
          estimate: ClockEstimate(-15000, clock.value),
        ),
        clock: clock,
        offline: () => true,
      );
      addTearDown(other.dispose);
      await other.load();
      await other.register();
      final payload = other.marks.single.w09Payload();
      expect(payload.length, 8);
      expect(payload['desvio_relogio_segundos'], -15);
      expect(payload['dispositivo_id'], 'registered-device');
      expect(payload.containsKey('usuario_id'), false);
      expect(payload.containsKey('device_uuid'), false);
    },
  );
  test('demo is forbidden in production regardless of flag', () {
    expect(demoAllowed(release: true, enabled: true), false);
    expect(demoAllowed(release: false, enabled: false), false);
    expect(demoAllowed(release: false, enabled: true), true);
  });
  test('explicit ISO preserves nonzero offset and original microseconds', () {
    final local = timezone.TZDateTime(
      timezone.getLocation('America/Sao_Paulo'),
      2026,
      10,
      13,
      8,
      0,
      0,
      123,
      456,
    );
    expect(explicitIso(local), '2026-10-13T08:00:00.123456-03:00');
    expect(
      DateTime.parse(explicitIso(local)).microsecondsSinceEpoch,
      local.microsecondsSinceEpoch,
    );
  });
  test(
    'repository rejects duplicate step and event after reconstruction',
    () async {
      await vm.register();
      final mark = vm.marks.single;
      await expectLater(
        repository.append(mark, suspiciousWindow: Duration.zero),
        throwsStateError,
      );
      expect((await repository.pending(employee().scope)).length, 1);
    },
  );
  test('two independent view models cannot persist the same step', () async {
    final other = MarkViewModel(
      repository: repository,
      context: employee(),
      clock: clock,
      offline: () => true,
    );
    addTearDown(other.dispose);
    await other.load();
    await Future.wait([vm.register(), other.register()]);
    expect((await repository.pending(employee().scope)).length, 1);
  });
  test(
    'demo evidence cannot become W09 payload even with measurements',
    () async {
      final other = MarkViewModel(
        repository: repository,
        context: employee(estimate: ClockEstimate(0, clock.value)),
        clock: clock,
        offline: () => true,
      );
      addTearDown(other.dispose);
      await other.load();
      await other.register();
      expect(other.marks.single.w09Payload, throwsStateError);
    },
  );
  test('confirmation across day change is rejected', () async {
    await vm.register();
    await vm.register();
    clock.value = clock.value.add(const Duration(days: 1));
    await vm.confirm(true);
    expect(vm.error, contains('data mudou'));
    expect((await repository.pending(employee().scope)).length, 1);
  });
  testWidgets(
    'CA1 CA3 CA4 screen uses SQLite and confirms original hour after one tap',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MarkScreen(
            repository: repository,
            employee: employee(),
            clock: clock,
            offline: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Próxima marcação'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Registrar entrada'), 200);
      await tester.tap(find.text('Registrar entrada'));
      await tester.pumpAndSettle();
      expect(find.text('11:00:00'), findsOneWidget);
      expect(find.text('Ponto salvo no aparelho'), findsOneWidget);
      expect((await repository.pending(employee().scope)).length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('screen names next type in confirmation and cancels safely', (
    tester,
  ) async {
    await vm.register();
    await tester.pumpWidget(
      MaterialApp(
        home: MarkScreen(
          repository: repository,
          employee: employee(),
          clock: clock,
          offline: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Registrar saída para intervalo'),
      200,
    );
    await tester.tap(find.text('Registrar saída para intervalo'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar ponto consecutivo'), findsOneWidget);
    expect(
      find.textContaining('Deseja registrar saída para intervalo'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect((await repository.pending(employee().scope)).length, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
