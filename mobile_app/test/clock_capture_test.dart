import 'dart:async';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:ponto_aqui_mobile/core/clock/clock_service.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/data/mark_receipt.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/data/sqlite_mark_repository.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/domain/mark.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/presentation/mark_screen.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/presentation/mark_view_model.dart';

import 'support/clock_fakes.dart';

class GatedReads implements MarkRepository {
  GatedReads(this.delegate);
  final MarkRepository delegate;
  Completer<void>? gate;
  @override
  Future<List<Mark>> today(String scope, String day) async {
    if (gate != null) await gate!.future;
    return delegate.today(scope, day);
  }

  @override
  Future<Mark?> latest(String scope) => delegate.latest(scope);
  @override
  Future<List<Mark>> pending(String scope) => delegate.pending(scope);
  @override
  Future<void> append(
    Mark mark, {
    required Duration suspiciousWindow,
    String? confirmedPreviousId,
  }) => delegate.append(
    mark,
    suspiciousWindow: suspiciousWindow,
    confirmedPreviousId: confirmedPreviousId,
  );
}

void main() {
  tz.initializeTimeZones();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late TestTime time;
  late MarkDatabase db;
  late SqliteMarkRepository repo;
  late ClockService service;
  setUp(() {
    time = TestTime();
    db = MarkDatabase(NativeDatabase.memory());
    repo = SqliteMarkRepository(db);
    service = time.service();
  });
  tearDown(() async => db.close());

  Future<void> mount(WidgetTester tester, {int? limit = 120}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MarkScreen(
          repository: repo,
          employee: temporalEmployee(limit: limit),
          clockService: service,
          offline: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'device time is visible before capture and ticks without confirmation',
    (tester) async {
      await mount(tester);
      expect(find.text('Hora do aparelho: 11:00:00'), findsOneWidget);
      expect(find.textContaining('Desvio desconhecido: ainda'), findsOneWidget);
      time.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Hora do aparelho: 11:00:01'), findsOneWidget);
      await tester.tap(find.text('Registrar entrada'));
      await tester.pumpAndSettle();
      expect(find.text('Ponto salvo no aparelho'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await repo.pending(service.scope))
            .single
            .evidence['desvio_relogio_segundos'],
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final offset in [121000, -121000]) {
    testWidgets(
      'large drift $offset warns accessibly and still persists with one tap',
      (tester) async {
        await tester.runAsync(() => measure(service, offset));
        await mount(tester);
        expect(
          find.textContaining('O relógio do aparelho está fora de hora.'),
          findsOneWidget,
        );
        final warning = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(const Key('clock-warning')),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(warning.properties.liveRegion, true);
        await tester.tap(find.text('Registrar entrada'));
        await tester.pumpAndSettle();
        expect(
          (await repo.pending(service.scope))
              .single
              .evidence['desvio_relogio_segundos'],
          offset ~/ 1000,
        );
        expect(find.text('Ponto salvo no aparelho'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'equal limit has no excessive warning and absent policy invents no threshold',
    (tester) async {
      await tester.runAsync(() => measure(service, 120999));
      await mount(tester);
      expect(find.byKey(const Key('clock-warning')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => measure(service, 999999));
      await mount(tester, limit: null);
      expect(
        find.text('Limite de desvio da empresa ainda não disponível.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('O relógio do aparelho está fora de hora.'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'close-tap dialog displays frozen time and preserves drift across new measurement',
    (tester) async {
      await tester.runAsync(() => measure(service, 15000));
      final initial = MarkViewModel(
        repository: repo,
        context: temporalEmployee(),
        clock: time.wall,
        clockService: service,
        offline: () => true,
      );
      await tester.runAsync(() async {
        await initial.load();
        await initial.register();
      });
      initial.dispose();
      time.advance(const Duration(seconds: 2));
      await mount(tester);
      await tester.tap(find.text('Registrar saída para intervalo'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Horário capturado: 2026-10-19T11:00:02.000+00:00'),
        findsOneWidget,
      );
      time.advance(const Duration(minutes: 2));
      await tester.runAsync(() => measure(service, -7000));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      final event = (await repo.pending(service.scope)).last;
      expect(event.instant, DateTime.utc(2026, 10, 19, 11, 0, 2));
      expect(event.evidence['desvio_relogio_segundos'], 15);
      expect(event.evidence['clock_sample_age_ms'], 2000);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('resume marks estimate stale but allows valid local capture', (
    tester,
  ) async {
    await tester.runAsync(() => measure(service, 1000));
    await mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    time.advance(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('última estimativa está desatualizada'),
      findsOneWidget,
    );
    await tester.tap(find.text('Registrar entrada'));
    await tester.pumpAndSettle();
    final event = (await repo.pending(service.scope)).single;
    expect(event.evidence['clock_estimate_state'], 'stale');
    expect(event.evidence['desvio_relogio_segundos'], isNull);
    expect(event.evidence['clock_last_offset_ms'], 1000);
    await tester.pumpWidget(const SizedBox());
  });

  test('tap snapshot is frozen before the first repository await', () async {
    await measure(service, 15000);
    final gated = GatedReads(repo);
    final vm = MarkViewModel(
      repository: gated,
      context: temporalEmployee(),
      clock: time.wall,
      clockService: service,
      offline: () => true,
    );
    addTearDown(vm.dispose);
    await vm.load();
    gated.gate = Completer<void>();
    final saving = vm.register();
    time.advance(const Duration(minutes: 5));
    await measure(service, -20000);
    gated.gate!.complete();
    await saving;
    final mark = vm.marks.single;
    expect(mark.instant, DateTime.utc(2026, 10, 19, 11));
    expect(mark.evidence['desvio_relogio_segundos'], 15);
    expect(mark.evidence['clock_measured_at'], '2026-10-19T11:00:00.000Z');
    expect(vm.message, 'Ponto salvo no aparelho');
  });

  test('payload and controlled receipt keep all three times distinct without forged receipt', () async {
    await measure(service, -15000);
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
    final event = vm.marks.single;
    final payload = event.w09Payload();
    expect(payload['ocorrido_em'], '2026-10-19T11:00:00.000+00:00');
    expect(payload['desvio_relogio_segundos'], -15);
    expect(payload.containsKey('recebido_em'), false);
    final receiptJson = <String, Object?>{
      'evento_cliente_id': event.id,
      'persistida': true,
      'http_status': 201,
      'ocorrido_em': '2026-10-19T11:00:00Z',
      'recebido_em': '2026-10-19T11:30:00.123456Z',
      'desvio_relogio_segundos': -15,
      'registrado_offline': true,
      'offset_original_minutos': 0,
      'situacao': 'PendenteAnalise',
    };
    final receipt = MarkReceipt.verify(event, receiptJson);
    expect(receipt.deviceTime, event.instant);
    expect(receipt.driftSeconds, -15);
    expect(receipt.receivedAt, DateTime.utc(2026, 10, 19, 11, 30, 0, 123, 456));
    expect(receipt.situation, 'PendenteAnalise');
    time.advance(const Duration(hours: 1));
    await measure(service, 8000);
    expect(event.w09Payload(), payload);
    // Replay may contain an old receipt; it is never interpreted as current server time.
    expect(
      MarkReceipt.verify(event, {
        ...receiptJson,
        'http_status': 200,
      }).receivedAt,
      receipt.receivedAt,
    );
    for (final change in <Map<String, Object?>>[
      {'evento_cliente_id': 'different'},
      {'desvio_relogio_segundos': 0},
      {'ocorrido_em': '2026-10-19T12:00:00Z'},
      {'recebido_em': '2026-10-19T11:00:00'},
      {'persistida': false},
      {'http_status': 422},
      {'offset_original_minutos': -180},
    ]) {
      expect(
        () => MarkReceipt.verify(event, {...receiptJson, ...change}),
        throwsFormatException,
      );
    }
  });
}
