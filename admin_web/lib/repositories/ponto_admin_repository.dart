import 'package:dio/dio.dart';

import '../models/management_json.dart';
import 'repository_failure.dart';

enum TipoBatida {
  entrada('ENTRADA', 'Entrada'),
  inicioIntervalo('INICIO_INTERVALO', 'Início do intervalo'),
  fimIntervalo('FIM_INTERVALO', 'Fim do intervalo'),
  saida('SAIDA', 'Saída');

  const TipoBatida(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class PontoAdminRepository {
  PontoAdminRepository(this._dio, {required this.empresaId});
  final Dio _dio;
  final String empresaId;

  String _endpoint(String acao) {
    final base = Uri.parse(_dio.options.baseUrl);
    final path = base.path.replaceFirst(
      RegExp(r'/api/web/?$'),
      '/api/v1/admin/$acao',
    );
    // URL absoluta no mesmo servidor: mantém o interceptor JWT existente.
    // Preserva também um prefixo de proxy anterior a /api/web/.
    return base.path == path
        ? base.resolve('/api/v1/admin/$acao').toString()
        : base.replace(path: path, query: null, fragment: null).toString();
  }

  Future<void> inserirPontoManual({
    required String usuarioId,
    required DateTime novaDataHora,
    required String motivoTexto,
    required TipoBatida tipo,
  }) => _salvar('ponto-manual', {
    'usuario_id': repositoryResourceId(usuarioId),
    'nova_data_hora': novaDataHora.toUtc().toIso8601String(),
    'motivo_texto': motivoTexto.trim(),
    'tipo': tipo.apiValue,
  });

  Future<void> corrigirPontoExistente({
    required String registroOriginalId,
    required DateTime novaDataHora,
    required String motivoTexto,
  }) => _salvar('ponto-correcao', {
    'registro_original_id': repositoryResourceId(registroOriginalId),
    'nova_data_hora': novaDataHora.toUtc().toIso8601String(),
    'motivo_texto': motivoTexto.trim(),
  });

  Future<void> _salvar(
    String acao,
    Map<String, dynamic> payload,
  ) => repositoryRequest(() async {
    final motivo = payload['motivo_texto'] as String;
    if (motivo.isEmpty || motivo.length > 5000) {
      throw const RepositoryFailure(
        'Informe uma justificativa de até 5000 caracteres.',
      );
    }
    final response = await _dio.post<Object?>(_endpoint(acao), data: payload);
    final ajuste = managementObject(managementObject(response.data)['ajuste']);
    managementString(ajuste['id'], 'id');
    managementString(ajuste['gestor_aprovador_id'], 'gestor_aprovador_id');
    if (response.statusCode != 201 ||
        ajuste['empresa_id'] != empresaId ||
        ajuste['status_analise'] != 'APROVADO' ||
        (acao == 'ponto-manual' &&
            (ajuste['usuario_id'] != payload['usuario_id'] ||
                ajuste['registro_original_id'] != null ||
                ajuste['tipo'] != payload['tipo'])) ||
        (acao == 'ponto-correcao' &&
            ajuste['registro_original_id'] !=
                payload['registro_original_id'])) {
      throw const FormatException('Ajuste não confirmado pela API.');
    }
    final salvo = DateTime.tryParse(
      managementString(ajuste['nova_data_hora'], 'nova_data_hora'),
    );
    if (salvo == null ||
        !salvo.isUtc ||
        !salvo.isAtSameMomentAs(
          DateTime.parse(payload['nova_data_hora'] as String),
        )) {
      throw const FormatException('Horário do ajuste não confirmado.');
    }
  });
}
