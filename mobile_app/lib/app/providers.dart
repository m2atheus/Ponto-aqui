import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/capture.dart';
import '../core/clock/clock_service.dart';
import '../core/clock/clock_response_observer.dart';
import '../core/clock/sqlite_clock_estimate_store.dart';
import '../features/marcacoes/data/sqlite_mark_repository.dart';
import '../features/marcacoes/domain/mark.dart';

bool demoAllowed({required bool release, required bool enabled}) =>
    !release && enabled;

// Replace via ProviderScope with a validated, cached W08 context in a later story.
final employeeContextProvider = Provider<EmployeeContext?>((ref) {
  if (!demoAllowed(
    release: kReleaseMode,
    enabled: const bool.fromEnvironment('PONTO_AQUI_DEMO'),
  )) {
    return null;
  }
  final now = DateTime.now();
  return EmployeeContext(
    apiOrigin: 'demo://ponto-aqui',
    companyId: 'demo-company',
    userId: 'demo-user',
    employeeId: 'demo-employee',
    deviceId: 'demo-device',
    deviceUuid: 'demo-installation',
    name: 'Funcionário de teste',
    zone: 'America/Sao_Paulo',
    referenceDate: civilDate(now, 'America/Sao_Paulo'),
    allocations: [const Allocation('demo-allocation', '2000-01-01')],
    isDemo: true,
  );
});

final databaseProvider = FutureProvider<MarkDatabase>((ref) async {
  final directory = await getApplicationSupportDirectory();
  var databaseFile = File('${directory.path}/ponto_aqui.sqlite');
  if (!await databaseFile.exists()) {
    // Keep earlier databases accessible without moving pending evidence.
    final previous = await directory
        .list()
        .where(
          (entry) =>
              entry is File &&
              RegExp(r'^app\d+\.sqlite$')
                  .hasMatch(entry.path.split(Platform.pathSeparator).last),
        )
        .cast<File>()
        .toList();
    if (previous.length > 1) {
      throw StateError(
        'Mais de um banco anterior encontrado; recuperação necessária.',
      );
    }
    if (previous.isNotEmpty) databaseFile = previous.single;
  }
  final db = MarkDatabase(NativeDatabase.createInBackground(databaseFile));
  ref.onDispose(() {
    db.close();
  });
  return db;
});

final repositoryProvider = FutureProvider<MarkRepository>(
  (ref) async => SqliteMarkRepository(await ref.watch(databaseProvider.future)),
);

final deviceClockProvider = Provider<Clock>((ref) => DeviceClock());
final monotonicClockProvider = Provider<MonotonicClock>(
  (ref) => StopwatchClock(),
);
final clockServiceProvider =
    FutureProvider.family<ClockService, EmployeeContext>((ref, employee) async {
      final db = await ref.watch(databaseProvider.future);
      final service = ClockService(
        scope: employee.scope,
        clock: ref.watch(deviceClockProvider),
        monotonic: ref.watch(monotonicClockProvider),
        store: SqliteClockEstimateStore(db),
        initialEstimate: employee.estimate,
      );
      await service.restore();
      return service;
    });

// Future mobile HTTP client hooks into this adapter; no client exists yet.
final clockResponseObserverProvider =
    FutureProvider.family<ClockResponseObserver, EmployeeContext>(
      (ref, employee) async => ClockResponseObserver(
        service: await ref.watch(clockServiceProvider(employee).future),
        apiOrigin: Uri.parse(employee.apiOrigin),
      ),
    );

// Connectivity is only an observation of network interfaces, never API reachability.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) async* {
  final source = Connectivity();
  yield await source.checkConnectivity();
  yield* source.onConnectivityChanged;
});
