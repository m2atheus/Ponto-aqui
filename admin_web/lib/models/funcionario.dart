import 'management_json.dart';

class Funcionario {
  const Funcionario({
    required this.id,
    required this.nome,
    required this.matricula,
    required this.cargo,
    required this.empresaId,
    this.ativo = true,
    this.usuarioId,
  });

  final String id;
  final String nome;
  final String matricula;
  // Cargo é nullable no modelo Flask; cadastro não implica criar uma conta.
  final String? cargo;
  final String empresaId;
  final bool ativo;
  final String? usuarioId;
  bool get temAcessoApp => usuarioId != null;

  factory Funcionario.fromJson(Object? value) {
    final json = managementObject(value);
    final ativo = json.containsKey('ativo') ? json['ativo'] : true;
    if (ativo is! bool) throw const FormatException('ativo deve ser booleano.');
    return Funcionario(
      id: managementString(json['id'], 'id'),
      nome: managementString(json['nome'], 'nome'),
      matricula: managementString(json['matricula'], 'matricula'),
      cargo: managementOptionalString(json['cargo'], 'cargo'),
      empresaId: managementString(json['empresa_id'], 'empresa_id'),
      ativo: ativo,
      usuarioId: json['usuario_id'] == null
          ? null
          : managementString(json['usuario_id'], 'usuario_id'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': nome,
    'matricula': matricula,
    'cargo': cargo,
    'empresa_id': empresaId,
    'ativo': ativo,
    if (usuarioId != null) 'usuario_id': usuarioId,
  };

  // IDs e empresa são somente leitura; o servidor deriva a empresa do JWT.
  Map<String, dynamic> toRequestJson() => {
    'nome': nome,
    'matricula': matricula,
    'cargo': cargo,
  };
}
