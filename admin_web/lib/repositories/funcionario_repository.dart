import 'package:dio/dio.dart';

import '../models/funcionario.dart';
import '../models/management_json.dart';
import 'repository_failure.dart';

class FuncionarioRepository {
  FuncionarioRepository(this._dio, {required this.empresaId});
  final Dio _dio;
  final String empresaId;

  Funcionario _parse(Object? value) {
    final dto = Funcionario.fromJson(value);
    if (dto.empresaId != empresaId) {
      throw const RepositoryFailure(
        'Resposta incompatível com a empresa da sessão.',
      );
    }
    return dto;
  }

  void _validate(Funcionario dto) {
    if (dto.empresaId != empresaId) {
      throw const RepositoryFailure(
        'O funcionário não pertence à empresa da sessão.',
      );
    }
  }

  Future<List<Funcionario>> listar({CancelToken? cancelToken}) =>
      repositoryRequest(() async {
        final response = await _dio.get<Object?>(
          'funcionarios',
          cancelToken: cancelToken,
        );
        final raw = response.data;
        final items = raw is List ? raw : managementObject(raw)['funcionarios'];
        if (items is! List) {
          throw const FormatException('Lista de funcionários inválida.');
        }
        return List<Funcionario>.unmodifiable(items.map(_parse));
      });

  Funcionario _single(Object? raw) {
    final json = managementObject(raw);
    return _parse(json.containsKey('funcionario') ? json['funcionario'] : json);
  }

  Future<Funcionario> criar(Funcionario dto) => repositoryRequest(() async {
    _validate(dto);
    final response = await _dio.post<Object?>(
      'funcionarios',
      data: dto.toRequestJson(),
    );
    return _single(response.data);
  });

  Future<Funcionario> atualizar(Funcionario dto) => repositoryRequest(() async {
    _validate(dto);
    final id = repositoryResourceId(dto.id);
    final response = await _dio.put<Object?>(
      'funcionarios/$id',
      data: dto.toRequestJson(),
    );
    final saved = _single(response.data);
    if (saved.id != dto.id) {
      throw const FormatException('Funcionário diferente na resposta.');
    }
    return saved;
  });

  Future<Funcionario> desativar(Funcionario dto) => repositoryRequest(() async {
    _validate(dto);
    final id = repositoryResourceId(dto.id);
    final response = await _dio.put<Object?>(
      'funcionarios/$id',
      data: {'ativo': false},
    );
    final saved = _single(response.data);
    if (saved.id != dto.id || saved.ativo) {
      throw const FormatException('Desativação não confirmada pela API.');
    }
    return saved;
  });
}
