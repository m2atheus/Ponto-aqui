import 'package:dio/dio.dart';

import '../models/management_json.dart';
import '../models/dispositivo.dart';
export '../models/dispositivo.dart';
import '../models/w06.dart' show SetorResumo;
import 'repository_failure.dart';

class DispositivoRepository {
  DispositivoRepository(this.dio, {required this.empresaId});
  final Dio dio;
  final String empresaId;

  String _url(String funcionarioId, [String suffix = '']) {
    final path =
        'funcionarios/${repositoryResourceId(funcionarioId)}/dispositivos$suffix';
    final base = Uri.parse(dio.options.baseUrl);
    final prefixo = base.path.replaceFirst(
      RegExp(r'/api/web/?$'),
      '/api/v1/admin/$path',
    );
    return prefixo == base.path
        ? base.resolve('/api/v1/admin/$path').toString()
        : base.replace(path: prefixo, query: null, fragment: null).toString();
  }

  Future<DispositivosData> listar(
    String funcionarioId, {
    CancelToken? cancelToken,
  }) => repositoryRequest(() async {
    final response = await dio.get<Object?>(
      _url(funcionarioId),
      cancelToken: cancelToken,
    );
    final j = managementObject(response.data);
    if (j['dispositivos'] is! List ||
        j['setores_disponiveis'] is! List ||
        j['tem_acesso_app'] is! bool) {
      throw const FormatException('Lista de aparelhos inválida.');
    }
    return DispositivosData(
      List.unmodifiable(
        (j['dispositivos'] as List).map(
          (v) => DispositivoFuncionario.fromJson(v, empresaId),
        ),
      ),
      List.unmodifiable(
        (j['setores_disponiveis'] as List).map(SetorResumo.fromJson),
      ),
      j['tem_acesso_app'] as bool,
    );
  });

  Future<void> vincular(
    String funcionarioId, {
    required String deviceUuid,
    required TipoAparelho tipo,
    String? nome,
    String? setorId,
    bool converterParaRelogio = false,
  }) => repositoryRequest(() async {
    final response = await dio.post<Object?>(
      _url(funcionarioId),
      data: {
        'device_uuid': deviceUuid.trim(),
        'tipo': tipo.apiValue,
        if (nome != null && nome.trim().isNotEmpty)
          'nome_identificador': nome.trim(),
        if (tipo == TipoAparelho.relogio && setorId != null)
          'setor_id': repositoryResourceId(setorId),
        if (converterParaRelogio) 'converter_para_relogio': true,
      },
    );
    final dto = DispositivoFuncionario.fromJson(
      managementObject(response.data)['dispositivo'],
      empresaId,
    );
    if (response.statusCode != 201 ||
        !dto.ativo ||
        dto.tipo != tipo ||
        dto.deviceUuid.toLowerCase() != deviceUuid.trim().toLowerCase()) {
      throw const FormatException('Autorização não confirmada.');
    }
  });

  Future<void> revogar(
    String funcionarioId,
    String dispositivoId,
  ) => repositoryRequest(() async {
    final response = await dio.post<Object?>(
      _url(funcionarioId, '/${repositoryResourceId(dispositivoId)}/revogar'),
    );
    final dto = DispositivoFuncionario.fromJson(
      managementObject(response.data)['dispositivo'],
      empresaId,
    );
    if (response.statusCode != 200 || dto.id != dispositivoId || dto.ativo) {
      throw const FormatException('Revogação não confirmada.');
    }
  });
}
