import '../capture.dart';

abstract interface class MonotonicClock {
  Duration get elapsed;
  Object get continuity;
}

class StopwatchClock implements MonotonicClock {
  final Stopwatch _watch = Stopwatch()..start();
  @override
  final Object continuity = Object();
  @override
  Duration get elapsed => _watch.elapsed;
}

abstract interface class ClockEstimateStore {
  Future<ClockEstimate?> load(String scope);
  Future<void> save(String scope, ClockEstimate estimate);
}

enum ClockAvailability { unmeasured, available, stale }

enum MeasurementResult {
  accepted,
  missingReference,
  invalidReference,
  invalidContinuity,
  olderResponse,
  storageFailure,
  wrongOrigin,
}

class ClockMoment {
  const ClockMoment(this.wall, this.elapsed, this.continuity, this.generation);
  final DateTime wall;
  final Duration elapsed;
  final Object continuity;
  final int generation;
}

class ClockSnapshot {
  const ClockSnapshot(
    this.availability, {
    this.lastEstimate,
    this.ageMs,
    this.reason,
  });
  final ClockAvailability availability;
  final ClockEstimate? lastEstimate;
  final int? ageMs;
  final String? reason;
  ClockEstimate? get estimate =>
      availability == ClockAvailability.available ? lastEstimate : null;
  bool exceeds(int? limitSeconds) =>
      limitSeconds != null &&
      estimate != null &&
      estimate!.seconds.abs() > limitSeconds;
  String? warning(int? limitSeconds) {
    if (availability == ClockAvailability.unmeasured) {
      return 'Desvio desconhecido: ainda não foi possível comparar o relógio com a hora do servidor.';
    }
    if (availability == ClockAvailability.stale) {
      return 'Desvio desconhecido: a última estimativa está desatualizada. '
          'É necessário comparar novamente com a hora do servidor.';
    }
    if (exceeds(limitSeconds)) {
      return 'O relógio do aparelho está fora de hora. Você pode registrar o ponto; '
          'a divergência de horário será encaminhada para análise.';
    }
    return null;
  }
}

class ClockService {
  ClockService({
    required this.scope,
    required this.clock,
    required this.monotonic,
    this.store,
    ClockEstimate? initialEstimate,
    this.changeTolerance = const Duration(seconds: 2),
  }) : _last = initialEstimate;
  final String scope;
  final Clock clock;
  final MonotonicClock monotonic;
  final ClockEstimateStore? store;
  // Measurement tolerance, not a business rule or proof of tampering.
  final Duration changeTolerance;
  ClockEstimate? _last;
  ClockMoment? _anchor;
  String? _staleReason;
  int _generation = 0;
  Future<void> _writes = Future.value();

  ClockMoment read() => ClockMoment(
    clock.now(),
    monotonic.elapsed,
    monotonic.continuity,
    _generation,
  );

  Future<void> restore() async {
    try {
      _last = await store?.load(scope) ?? _last;
      _anchor = null; // Monotonic readings are never persisted across runs.
      _staleReason = _last == null ? null : 'continuity_lost';
    } catch (_) {
      _anchor = null;
      _staleReason = 'storage_unavailable';
    }
  }

  void invalidateContinuity([String reason = 'app_suspended']) {
    _generation++;
    _anchor = null;
    _staleReason = reason;
  }

  bool _continuous(ClockMoment from, ClockMoment to) =>
      identical(from.continuity, to.continuity) &&
      from.generation == to.generation &&
      to.generation == _generation &&
      to.elapsed >= from.elapsed &&
      (to.wall.difference(from.wall) - (to.elapsed - from.elapsed)).abs() <=
          changeTolerance;

  ClockSnapshot snapshot(ClockMoment moment) {
    if (_last == null) {
      return ClockSnapshot(ClockAvailability.unmeasured, reason: _staleReason);
    }
    final anchor = _anchor;
    if (anchor == null || !_continuous(anchor, moment)) {
      if (anchor != null) invalidateContinuity('wall_or_monotonic_changed');
      return ClockSnapshot(
        ClockAvailability.stale,
        lastEstimate: _last,
        reason: _staleReason ?? 'continuity_lost',
      );
    }
    return ClockSnapshot(
      ClockAvailability.available,
      lastEstimate: _last,
      ageMs: (moment.elapsed - anchor.elapsed).inMilliseconds,
    );
  }

  Future<MeasurementResult> observe({
    required DateTime serverTimestamp,
    required ClockMoment sent,
    required ClockMoment received,
    required String source,
  }) {
    final result = _writes.then((_) async {
      if (!_continuous(sent, received)) {
        if (sent.generation == _generation &&
            received.generation == _generation) {
          invalidateContinuity('changed_during_request');
        }
        return MeasurementResult.invalidContinuity;
      }
      final anchor = _anchor;
      if (anchor != null &&
          identical(anchor.continuity, received.continuity) &&
          received.elapsed < anchor.elapsed) {
        return MeasurementResult.olderResponse;
      }
      final sample = ClockEstimate(
        serverTimestamp
            .toUtc()
            .difference(received.wall.toUtc())
            .inMilliseconds,
        received.wall,
        serverTimestamp: serverTimestamp.toUtc(),
        roundTripMs: (received.elapsed - sent.elapsed).inMilliseconds,
        source: source,
      );
      try {
        await store?.save(scope, sample);
      } catch (_) {
        return MeasurementResult.storageFailure;
      }
      _last = sample;
      // Suspension or a clock jump during disk I/O must not resurrect continuity.
      if (received.generation == _generation) {
        _anchor = received;
        _staleReason = null;
      }
      return MeasurementResult.accepted;
    });
    _writes = result.then((_) {});
    return result;
  }
}
