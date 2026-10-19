import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/capture.dart';
import '../../../core/clock/clock_service.dart';
import '../domain/mark.dart';

class MarkViewModel extends ChangeNotifier {
  MarkViewModel({
    required this.repository,
    required this.context,
    required this.clock,
    required this.offline,
    this.suspiciousWindow = const Duration(seconds: 30),
    ClockService? clockService,
    String Function()? newId,
  }) : newId = newId ?? const Uuid().v4,
       clockService =
           clockService ??
           ClockService(
             scope: context.scope,
             clock: clock,
             monotonic: StopwatchClock(),
             initialEstimate: context.estimate,
           ) {
    if (this.clockService.scope != context.scope) {
      throw ArgumentError('Estimativa temporal de outro contexto.');
    }
    refreshTime(notify: false);
  }
  final MarkRepository repository;
  final EmployeeContext context;
  final Clock clock;
  final ClockService clockService;
  late ClockMoment preview;
  late ClockSnapshot timeState;
  String? get clockWarning => timeState.warning(context.clockLimitSeconds);
  String? get confirmationOccurredIso => _awaitingConfirmation?.occurredIso;

  void refreshTime({bool notify = true}) {
    preview = clockService.read();
    timeState = clockService.snapshot(preview);
    if (notify) notifyListeners();
  }

  // null means observation unavailable; no network access is required.
  final bool? Function() offline;
  final String Function() newId;
  final Duration suspiciousWindow;
  List<Mark> marks = const [];
  String? day, error, message;
  bool busy = false, ready = false;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Mark? _awaitingConfirmation;
  String? _previousId;
  SuspiciousMark? confirmation;
  MarkType? get next => marks.length < 4 ? MarkType.values[marks.length] : null;

  String captureDay(DateTime time) {
    final current = civilDate(time, context.zone);
    if (context.crossesMidnight) {
      throw StateError(
        'Jornada atravessa meia-noite: contexto de jornada necessário.',
      );
    }
    if (!context.isDemo && current != context.referenceDate) {
      throw StateError(
        'Contexto W08 desatualizado. Atualize a data de referência.',
      );
    }
    context.allocationOn(current);
    return current;
  }

  Future<void> load() async {
    if (busy) return;
    refreshTime(notify: false);
    busy = true;
    notifyListeners();
    try {
      final reference = captureDay(clock.now());
      final stored = await repository.today(context.scope, reference);
      day = reference;
      marks = List.unmodifiable(stored);
      ready = true;
      error = null;
    } catch (e) {
      ready = false;
      marks = const [];
      day = null;
      error = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> register() async {
    if (busy || !ready || confirmation != null) return;
    final moment = clockService
        .read(); // Freeze time and estimate before any await.
    final tappedAt = moment.wall;
    final temporal = clockService.snapshot(moment);
    final observedOffline = offline();
    busy = true;
    error = message = null;
    notifyListeners();
    try {
      final reference = captureDay(tappedAt);
      final persisted = await repository.today(context.scope, reference);
      if (persisted.length == 4) {
        marks = persisted;
        day = reference;
        return;
      }
      final type = MarkType.values[persisted.length];
      final estimate = temporal.estimate;
      final mark = Mark(
        scope: context.scope,
        day: reference,
        type: type,
        evidence: {
          'is_demo': context.isDemo,
          'evento_cliente_id': newId(),
          'dispositivo_id': context.deviceId,
          'device_uuid': context.deviceUuid,
          'empresa_id': context.companyId,
          'usuario_id': context.userId,
          'funcionario_id': context.employeeId,
          'api_origin': context.apiOrigin,
          'alocacao_id': context.allocationOn(reference).id,
          'tipo': type.api,
          'ocorrido_em': explicitIso(tappedAt),
          'instant_utc': tappedAt.toUtc().toIso8601String(),
          'offset_original_minutos': tappedAt.timeZoneOffset.inMinutes,
          'desvio_relogio_segundos': estimate?.seconds,
          'clock_offset_ms': estimate?.offsetMs,
          'clock_estimate_state': temporal.availability.name,
          'clock_estimate_reason': temporal.reason,
          'clock_measured_at': temporal.lastEstimate?.measuredAt
              .toUtc()
              .toIso8601String(),
          'clock_sample_age_ms': temporal.ageMs,
          'clock_last_offset_ms': temporal.lastEstimate?.offsetMs,
          'clock_server_timestamp': temporal.lastEstimate?.serverTimestamp
              ?.toIso8601String(),
          'clock_round_trip_ms': temporal.lastEstimate?.roundTripMs,
          'clock_measurement_source': temporal.lastEstimate?.source,
          'registrado_offline': observedOffline,
          'posicao': null,
          'location_state': 'unavailable',
          'created_local_at': explicitIso(tappedAt),
        },
      );
      await save(mark);
    } catch (e) {
      error = 'Não foi possível salvar o ponto no aparelho. $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> save(Mark mark, {String? confirmedPreviousId}) async {
    final previousMarks = await repository.today(mark.scope, mark.day);
    try {
      await repository.append(
        mark,
        suspiciousWindow: suspiciousWindow,
        confirmedPreviousId: confirmedPreviousId,
      );
    } on SuspiciousMark catch (e) {
      _awaitingConfirmation = mark;
      _previousId = e.previous.id;
      confirmation = e;
      return;
    }
    // append completes only after commit. Never call a transport here.
    day = mark.day;
    marks = List.unmodifiable([...previousMarks, mark]);
    message = 'Ponto salvo no aparelho';
  }

  Future<void> confirm(bool accepted) async {
    if (busy || confirmation == null) return;
    final mark = _awaitingConfirmation!;
    final previousId = _previousId;
    confirmation = null;
    _awaitingConfirmation = null;
    _previousId = null;
    if (!accepted) {
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      if (captureDay(clock.now()) != mark.day) {
        throw StateError(
          'A data mudou durante a confirmação. Registre novamente.',
        );
      }
      await save(mark, confirmedPreviousId: previousId);
    } catch (e) {
      error = 'Não foi possível salvar o ponto no aparelho. $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
