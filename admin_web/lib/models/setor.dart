import 'management_json.dart';

class Setor {
  const Setor({
    required this.id,
    required this.nome,
    required this.empresaId,
    required this.ativo,
    this.endereco,
    this.latitude,
    this.longitude,
    this.raioMetros,
    this.exigeSelfie = false,
    this.acaoForaPerimetro = 'BLOQUEAR',
    this.ignorarLocalizacao = false,
  });
  final String id;
  final String nome;
  final String empresaId;
  final bool ativo;
  final String? endereco;
  // O GET resumido usado por Alocações pode não enviar o perímetro.
  // Nunca se inventa uma coordenada para editar um resumo antigo.
  final double? latitude;
  final double? longitude;
  final double? raioMetros;
  final bool exigeSelfie;
  final String acaoForaPerimetro;
  final bool ignorarLocalizacao;
  bool get possuiPerimetro =>
      latitude != null && longitude != null && raioMetros != null;

  static double? _numero(Object? value, String campo) {
    if (value == null) return null;
    final parsed = value is num
        ? value.toDouble()
        : value is String
        ? double.tryParse(value)
        : null;
    if (parsed == null || !parsed.isFinite) {
      throw FormatException('$campo deve ser numérico.');
    }
    return parsed;
  }

  static bool _booleano(Map<String, dynamic> json, String campo, bool padrao) {
    if (!json.containsKey(campo)) return padrao;
    if (json[campo] is! bool) {
      throw FormatException('$campo deve ser booleano.');
    }
    return json[campo] as bool;
  }

  factory Setor.fromJson(Object? value) {
    final json = managementObject(value);
    if (json['ativo'] is! bool) {
      throw const FormatException('ativo deve ser booleano.');
    }
    final latitude = _numero(
      json['latitude'] ?? json['latitude_centro'],
      'latitude',
    );
    final longitude = _numero(
      json['longitude'] ?? json['longitude_centro'],
      'longitude',
    );
    final raio = _numero(json['raio_metros'], 'raio_metros');
    final algumaCoordenada =
        latitude != null || longitude != null || raio != null;
    if (algumaCoordenada &&
        (latitude == null || longitude == null || raio == null)) {
      throw const FormatException('Perímetro incompleto.');
    }
    if ((latitude != null && latitude.abs() > 90) ||
        (longitude != null && longitude.abs() > 180) ||
        (raio != null && raio <= 0)) {
      throw const FormatException('Coordenadas ou raio inválidos.');
    }
    final acao = json.containsKey('acao_fora_perimetro')
        ? managementString(json['acao_fora_perimetro'], 'acao_fora_perimetro')
        : 'BLOQUEAR';
    if (!{'BLOQUEAR', 'PENDENTE'}.contains(acao)) {
      throw const FormatException('Política inválida.');
    }
    return Setor(
      id: managementString(json['id'], 'id'),
      nome: managementString(json['nome'], 'nome'),
      empresaId: managementString(json['empresa_id'], 'empresa_id'),
      ativo: json['ativo'] as bool,
      endereco: managementOptionalString(json['endereco'], 'endereco'),
      latitude: latitude,
      longitude: longitude,
      raioMetros: raio,
      exigeSelfie: _booleano(json, 'exige_selfie', false),
      acaoForaPerimetro: acao,
      ignorarLocalizacao: _booleano(json, 'ignorar_localizacao', false),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'empresa_id': empresaId,
    'ativo': ativo,
    'nome': nome,
    'endereco': endereco,
    'latitude': latitude,
    'longitude': longitude,
    'raio_metros': raioMetros,
    'exige_selfie': exigeSelfie,
    'acao_fora_perimetro': acaoForaPerimetro,
    'ignorar_localizacao': ignorarLocalizacao,
  };

  Map<String, dynamic> toRequestJson() {
    if (!possuiPerimetro ||
        !latitude!.isFinite ||
        latitude!.abs() > 90 ||
        !longitude!.isFinite ||
        longitude!.abs() > 180 ||
        !raioMetros!.isFinite ||
        raioMetros! <= 0 ||
        !{'BLOQUEAR', 'PENDENTE'}.contains(acaoForaPerimetro)) {
      throw const FormatException(
        'Informe coordenadas, raio positivo e políticas válidas.',
      );
    }
    return {
      'nome': nome.trim(),
      'endereco': endereco?.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'raio_metros': raioMetros,
      'exige_selfie': exigeSelfie,
      'acao_fora_perimetro': acaoForaPerimetro,
      'ignorar_localizacao': ignorarLocalizacao,
    };
  }
}
