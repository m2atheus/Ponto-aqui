import 'management_json.dart';
import 'w06.dart' show SetorResumo;

enum TipoAparelho {
  pessoal('PESSOAL', 'Pessoal'),
  relogio('RELOGIO', 'Relógio Compartilhado');

  const TipoAparelho(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class DispositivoFuncionario {
  const DispositivoFuncionario({
    required this.id,
    required this.deviceUuid,
    required this.nome,
    required this.tipo,
    required this.ativo,
    this.setorId,
    this.ultimoAcesso,
    this.setores = const [],
  });
  final String id;
  final String deviceUuid;
  final String nome;
  final TipoAparelho tipo;
  final bool ativo;
  final String? setorId;
  final DateTime? ultimoAcesso;
  final List<SetorResumo> setores;

  factory DispositivoFuncionario.fromJson(Object? value, String empresaId) {
    final j = managementObject(value);
    if (j['empresa_id'] != empresaId ||
        j['ativo'] is! bool ||
        j['status'] != (j['ativo'] == true ? 'Ativo' : 'Inativo')) {
      throw const FormatException('Vínculo de aparelho inválido.');
    }
    final tipo = TipoAparelho.values
        .where((t) => t.apiValue == j['tipo'])
        .firstOrNull;
    final setor = managementOptionalString(j['setor_id'], 'setor_id');
    final rawSetores = j['setores'] ?? const [];
    if (rawSetores is! List) {
      throw const FormatException('Setores do aparelho inválidos.');
    }
    final setores = rawSetores
        .map((value) {
          final s = managementObject(value);
          if (s['ativo'] is! bool) {
            throw const FormatException('Status do setor inválido.');
          }
          return SetorResumo.fromJson(s);
        })
        .toList(growable: false);
    if (tipo == null ||
        (tipo == TipoAparelho.relogio && setor == null && setores.isEmpty)) {
      throw const FormatException('Tipo de aparelho inválido.');
    }
    final data = managementOptionalString(
      j['ultimo_acesso_em'],
      'ultimo_acesso_em',
    );
    final acesso = data == null ? null : DateTime.tryParse(data);
    if (data != null && acesso == null) {
      throw const FormatException('Último acesso inválido.');
    }
    return DispositivoFuncionario(
      id: managementString(j['id'], 'id'),
      deviceUuid: managementString(j['device_uuid'], 'device_uuid'),
      nome: managementString(j['nome_identificador'], 'nome_identificador'),
      tipo: tipo,
      ativo: j['ativo'] as bool,
      setorId: setor,
      ultimoAcesso: acesso,
      setores: List.unmodifiable(setores),
    );
  }
}

class DispositivosData {
  DispositivosData(this.dispositivos, this.setores, this.temAcessoApp);
  final List<DispositivoFuncionario> dispositivos;
  final List<SetorResumo> setores;
  final bool temAcessoApp;
}
