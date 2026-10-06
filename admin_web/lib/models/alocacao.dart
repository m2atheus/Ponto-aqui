import 'management_json.dart';

class Alocacao {
  const Alocacao({
    required this.id,
    required this.funcionarioId,
    required this.setorId,
    required this.dataInicio,
    this.dataFim,
    this.empresaId,
    this.escalaId,
  });

  final String id;
  final String funcionarioId;
  final String setorId;
  // Datas civis ISO, sem conversão para timezone do navegador.
  final String dataInicio;
  final String? dataFim;
  final String? empresaId;
  final String? escalaId;

  factory Alocacao.fromJson(Object? value) {
    final json = managementObject(value);
    final inicio = managementDate(json['data_inicio'], 'data_inicio');
    final fim = json['data_fim'] == null
        ? null
        : managementDate(json['data_fim'], 'data_fim');
    if (fim != null && fim.compareTo(inicio) < 0) {
      throw const FormatException('Fim anterior ao início da alocação.');
    }
    return Alocacao(
      id: managementString(json['id'], 'id'),
      funcionarioId: managementString(json['funcionario_id'], 'funcionario_id'),
      setorId: managementString(json['setor_id'], 'setor_id'),
      dataInicio: inicio,
      dataFim: fim,
      empresaId: managementOptionalString(json['empresa_id'], 'empresa_id'),
      escalaId: managementOptionalString(json['escala_id'], 'escala_id'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'funcionario_id': funcionarioId,
    'setor_id': setorId,
    'data_inicio': dataInicio,
    'data_fim': dataFim,
    if (empresaId != null) 'empresa_id': empresaId,
    if (escalaId != null) 'escala_id': escalaId,
  };

  Map<String, dynamic> toRequestJson() => {
    'funcionario_id': funcionarioId,
    'setor_id': setorId,
    'data_inicio': dataInicio,
    'data_fim': dataFim,
    if (escalaId != null) 'escala_id': escalaId,
  };
}
