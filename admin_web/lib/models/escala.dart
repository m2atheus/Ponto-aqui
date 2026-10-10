import 'management_json.dart';

class TurnoEscala {
  TurnoEscala({
    required this.inicio,
    required this.fim,
    this.intervalo = 0,
    this.diaSeguinte = false,
    Set<int> dias = const {1, 2, 3, 4, 5},
  }) : dias = Set.unmodifiable(dias);
  final int inicio, fim, intervalo;
  final bool diaSeguinte;
  final Set<int> dias;
  factory TurnoEscala.fromJson(Object? value) {
    final j = managementObject(value);
    final inicio = Escala.lerHorario(
      managementString(j['hora_inicio'], 'hora_inicio'),
    );
    final fim = Escala.lerHorario(managementString(j['hora_fim'], 'hora_fim'));
    final intervalo = j['tempo_intervalo'], dias = j['dias_semana'];
    if (inicio == null ||
        fim == null ||
        intervalo is! int ||
        intervalo < 0 ||
        j['fim_dia_seguinte'] is! bool ||
        dias is! List ||
        dias.isEmpty ||
        dias.any((d) => d is! int || d < 1 || d > 7) ||
        dias.toSet().length != dias.length) {
      throw const FormatException('Turno inválido.');
    }
    return TurnoEscala(
      inicio: inicio,
      fim: fim,
      intervalo: intervalo,
      diaSeguinte: j['fim_dia_seguinte'] as bool,
      dias: dias.cast<int>().toSet(),
    );
  }
  Map<String, dynamic> toJson() => {
    'hora_inicio': Escala.formatarHorario(inicio),
    'hora_fim': Escala.formatarHorario(fim),
    'tempo_intervalo': intervalo,
    'fim_dia_seguinte': diaSeguinte,
    'dias_semana': dias.toList()..sort(),
  };
}

class Escala {
  Escala({
    required this.id,
    required this.empresaId,
    required this.nome,
    required this.modelo,
    required Iterable<TurnoEscala> turnos,
    this.ativa = true,
    this.dataReferencia,
  }) : turnos = List.unmodifiable(turnos);
  final String id, empresaId, nome, modelo;
  final bool ativa;
  final String? dataReferencia;
  final List<TurnoEscala> turnos;
  bool get ciclica => modelo == '12x36' || modelo == '24x72';
  static const modelos = ['5x2', 'Diurno', '12x36', '24x72', 'Legado'];
  static const dias = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  factory Escala.fromJson(Object? value) {
    final j = managementObject(value),
        lista = managementObject(value)['turnos'];
    if (lista is! List ||
        j['ativo'] is! bool ||
        !modelos.contains(j['modelo'])) {
      throw const FormatException('Escala inválida.');
    }
    return Escala(
      id: managementString(j['id'], 'id'),
      empresaId: managementString(j['empresa_id'], 'empresa_id'),
      nome: managementString(j['nome'], 'nome'),
      modelo: j['modelo'] as String,
      ativa: j['ativo'] as bool,
      dataReferencia: j['data_referencia'] == null
          ? null
          : managementDate(j['data_referencia'], 'data_referencia'),
      turnos: lista.map(TurnoEscala.fromJson),
    );
  }
  Map<String, dynamic> toRequestJson() => {
    'nome': nome,
    'ativo': ativa,
    if (modelo != 'Legado') ...{
      'modelo': modelo,
      'data_referencia': dataReferencia,
      'turnos': turnos.map((t) => t.toJson()).toList(),
    },
  };
  static String formatarHorario(int minutos) =>
      '${(minutos ~/ 60).toString().padLeft(2, '0')}:${(minutos % 60).toString().padLeft(2, '0')}';
  static int? lerHorario(String texto) {
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(texto.trim())) {
      return null;
    }
    final partes = texto.trim().split(':');
    return int.parse(partes[0]) * 60 + int.parse(partes[1]);
  }
}
