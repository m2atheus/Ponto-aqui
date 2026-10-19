import 'dart:convert';

import '../../../core/capture.dart';

enum MarkType {
  entrada('Entrada', 'Entrada'),
  inicioIntervalo('InicioIntervalo', 'Saída para intervalo'),
  fimIntervalo('FimIntervalo', 'Retorno do intervalo'),
  saida('Saida', 'Saída');

  const MarkType(this.api, this.label);
  final String api;
  final String label;
}

class Allocation {
  const Allocation(this.id, this.start, {this.end});
  final String id;
  final String start;
  final String? end;
  bool validOn(String day) =>
      start.compareTo(day) <= 0 && (end == null || end!.compareTo(day) >= 0);
}

class EmployeeContext {
  EmployeeContext({
    required this.apiOrigin,
    required this.companyId,
    required this.userId,
    required this.employeeId,
    required this.deviceId,
    required this.deviceUuid,
    required this.name,
    required this.zone,
    required this.referenceDate,
    required List<Allocation> allocations,
    this.selectedAllocationId,
    this.estimate,
    this.clockLimitSeconds,
    this.crossesMidnight = false,
    this.isDemo = false,
  }) : allocations = List.unmodifiable(allocations);
  final String apiOrigin, companyId, userId, employeeId, deviceId, deviceUuid;
  final String name, zone, referenceDate;
  final List<Allocation> allocations;
  final String? selectedAllocationId;
  final ClockEstimate? estimate;
  // W08 setor.politicas.limite_desvio_relogio_segundos; absent means unknown.
  final int? clockLimitSeconds;
  final bool crossesMidnight, isDemo;
  String get scope => jsonEncode([apiOrigin, companyId, userId, deviceId]);
  Allocation allocationOn(String day) {
    final valid = allocations.where((a) => a.validOn(day)).toList();
    if (selectedAllocationId != null) {
      return valid.firstWhere(
        (a) => a.id == selectedAllocationId,
        orElse: () => throw StateError('Alocação selecionada sem vigência.'),
      );
    }
    if (valid.length != 1) {
      throw StateError('Selecione uma alocação válida antes de registrar.');
    }
    return valid.single;
  }
}

class Mark {
  Mark({
    required this.scope,
    required this.day,
    required this.type,
    required Map<String, Object?> evidence,
  }) : evidence = Map.unmodifiable(evidence);
  final String scope, day;
  final MarkType type;
  final Map<String, Object?> evidence;
  String get id => evidence['evento_cliente_id'] as String;
  String get occurredIso => evidence['ocorrido_em'] as String;
  DateTime get instant => DateTime.parse(occurredIso);
  String get originalTime => occurredIso.substring(11, 19);
  Map<String, Object?> w09Payload() {
    if (evidence['is_demo'] == true) {
      throw StateError('Registros de demonstração não podem ser enviados.');
    }
    if (evidence['desvio_relogio_segundos'] == null ||
        evidence['registrado_offline'] == null) {
      throw StateError(
        'Evidência sem estimativa/conectividade: contrato W09 pendente.',
      );
    }
    return {
      for (final key in const [
        'evento_cliente_id',
        'dispositivo_id',
        'alocacao_id',
        'tipo',
        'ocorrido_em',
        'desvio_relogio_segundos',
        'registrado_offline',
        'posicao',
      ])
        key: evidence[key],
    };
  }
}

abstract interface class MarkRepository {
  Future<List<Mark>> today(String scope, String day);
  Future<Mark?> latest(String scope);
  Future<void> append(
    Mark mark, {
    required Duration suspiciousWindow,
    String? confirmedPreviousId,
  });
  Future<List<Mark>> pending(String scope);
}

class SuspiciousMark implements Exception {
  const SuspiciousMark(this.previous, this.next);
  final Mark previous;
  final MarkType next;
}
