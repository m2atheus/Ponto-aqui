import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/capture.dart';
import '../domain/mark.dart';

class MarkViewModel extends ChangeNotifier {
  MarkViewModel({
    required this.repository,
    required this.context,
    required this.clock,
    required this.offline,
    this.suspiciousWindow = const Duration(seconds: 30),
    String Function()? newId,
  }) : newId = newId ?? const Uuid().v4;
  final MarkRepository repository;
  final EmployeeContext context;
  final Clock clock;
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
    final tappedAt = clock.now(); // capture before any await
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
      final estimate = context.estimate;
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
          'clock_estimate_state': estimate == null ? 'unmeasured' : 'available',
          'clock_measured_at': estimate?.measuredAt.toUtc().toIso8601String(),
          'clock_sample_age_ms': estimate == null
              ? null
              : tappedAt.difference(estimate.measuredAt).inMilliseconds,
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
