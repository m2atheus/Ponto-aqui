import 'package:ponto_aqui_mobile/core/capture.dart';
import 'package:ponto_aqui_mobile/core/clock/clock_service.dart';
import 'package:ponto_aqui_mobile/features/marcacoes/domain/mark.dart';

class MutableClock implements Clock {
  DateTime value = DateTime.utc(2026, 10, 19, 11);
  @override
  DateTime now() => value;
}

class MutableMonotonic implements MonotonicClock {
  Duration value = Duration.zero;
  Object token = Object();
  @override
  Duration get elapsed => value;
  @override
  Object get continuity => token;
}

class TestTime {
  final wall = MutableClock();
  final mono = MutableMonotonic();
  void advance(Duration duration) {
    wall.value = wall.value.add(duration);
    mono.value += duration;
  }

  ClockService service({
    String? scope,
    ClockEstimateStore? store,
    ClockEstimate? seed,
  }) => ClockService(
    scope: scope ?? temporalEmployee().scope,
    clock: wall,
    monotonic: mono,
    store: store,
    initialEstimate: seed,
  );
}

EmployeeContext temporalEmployee({
  String account = 'account',
  String company = 'company',
  String origin = 'https://api.example',
  String device = 'device',
  int? limit = 120,
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
  referenceDate: '2026-10-19',
  allocations: [const Allocation('assignment', '2026-01-01')],
  clockLimitSeconds: limit,
  estimate: estimate,
);

Future<void> measure(ClockService service, int offsetMs) async {
  final moment = service.read();
  await service.observe(
    serverTimestamp: moment.wall.add(Duration(milliseconds: offsetMs)),
    sent: moment,
    received: moment,
    source: 'server_timestamp',
  );
}
