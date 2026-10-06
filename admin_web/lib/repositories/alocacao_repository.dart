import 'package:dio/dio.dart';

import '../models/alocacao.dart';
import '../models/management_json.dart';
import 'repository_failure.dart';

class AlocacaoRepository {
  AlocacaoRepository(this._dio, {required this.empresaId});
  final Dio _dio;
  final String empresaId;

  Alocacao _parse(Object? value) {
    final dto = Alocacao.fromJson(value);
    _validate(dto);
    return dto;
  }

  void _validate(Alocacao dto) {
    if (dto.empresaId != null && dto.empresaId != empresaId) {
      throw const RepositoryFailure(
        'A alocação não pertence à empresa da sessão.',
      );
    }
    managementString(dto.funcionarioId, 'funcionario_id');
    managementString(dto.setorId, 'setor_id');
    final inicio = managementDate(dto.dataInicio, 'data_inicio');
    if (dto.dataFim != null &&
        managementDate(dto.dataFim, 'data_fim').compareTo(inicio) < 0) {
      throw const RepositoryFailure(
        'A data final não pode ser anterior à inicial.',
      );
    }
  }

  Future<List<Alocacao>> listar({
    String? funcionarioId,
    CancelToken? cancelToken,
  }) => repositoryRequest(() async {
    final response = await _dio.get<Object?>(
      'alocacoes',
      queryParameters: {'funcionario_id': ?funcionarioId},
      cancelToken: cancelToken,
    );
    final raw = response.data;
    final items = raw is List ? raw : managementObject(raw)['alocacoes'];
    if (items is! List) {
      throw const FormatException('Lista de alocações inválida.');
    }
    return List<Alocacao>.unmodifiable(items.map(_parse));
  });

  Alocacao _single(Object? raw) {
    final json = managementObject(raw);
    return _parse(json.containsKey('alocacao') ? json['alocacao'] : json);
  }

  Future<Alocacao> criar(Alocacao dto) => repositoryRequest(() async {
    _validate(dto);
    // Sobreposição é validada pela API, inclusive entre chamadas concorrentes.
    final response = await _dio.post<Object?>(
      'alocacoes',
      data: dto.toRequestJson(),
    );
    return _single(response.data);
  });

  Future<Alocacao> atualizar(Alocacao dto) => repositoryRequest(() async {
    _validate(dto);
    final id = repositoryResourceId(dto.id);
    if (dto.dataFim == null) {
      throw const RepositoryFailure(
        'Informe a data de encerramento da alocação.',
      );
    }
    // PUT encerra o vínculo. Uma troca de setor/escala exige NOVA alocação.
    final response = await _dio.put<Object?>(
      'alocacoes/$id',
      data: {'data_fim': dto.dataFim},
    );
    final saved = _single(response.data);
    if (saved.id != dto.id ||
        saved.funcionarioId != dto.funcionarioId ||
        saved.setorId != dto.setorId ||
        saved.dataInicio != dto.dataInicio ||
        saved.dataFim != dto.dataFim ||
        saved.escalaId != dto.escalaId) {
      throw const FormatException(
        'Histórico da alocação alterado ou encerramento não confirmado.',
      );
    }
    return saved;
  });
}
