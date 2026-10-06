import 'package:dio/dio.dart';

import '../models/management_json.dart';
import '../models/setor.dart';
import 'repository_failure.dart';

class SetorRepository {
  SetorRepository(this._dio, {required this.empresaId});
  final Dio _dio;
  final String empresaId;

  Setor _parse(Object? value) {
    final dto = Setor.fromJson(value);
    if (dto.empresaId != empresaId) {
      throw const RepositoryFailure(
        'Resposta incompatível com a empresa da sessão.',
      );
    }
    return dto;
  }

  void _validarEmpresa(Setor dto) {
    if (dto.empresaId != empresaId) {
      throw const RepositoryFailure(
        'O setor não pertence à empresa da sessão.',
      );
    }
  }

  Setor _single(Object? value) {
    final json = managementObject(value);
    final dto = _parse(json.containsKey('setor') ? json['setor'] : json);
    if (!dto.possuiPerimetro) {
      throw const FormatException('A API retornou apenas um resumo do setor.');
    }
    return dto;
  }

  Future<List<Setor>> listar({CancelToken? cancelToken}) =>
      repositoryRequest(() async {
        final response = await _dio.get<Object?>(
          'setores',
          cancelToken: cancelToken,
        );
        final raw = response.data;
        final items = raw is List ? raw : managementObject(raw)['setores'];
        if (items is! List) {
          throw const FormatException('Lista de setores inválida.');
        }
        return List<Setor>.unmodifiable(items.map(_parse));
      });

  Future<Setor> criar(Setor dto) => repositoryRequest(() async {
    _validarEmpresa(dto);
    final response = await _dio.post<Object?>(
      'setores',
      data: dto.toRequestJson(),
    );
    return _single(response.data);
  });

  Future<Setor> atualizar(Setor dto) => repositoryRequest(() async {
    _validarEmpresa(dto);
    final id = repositoryResourceId(dto.id);
    final response = await _dio.put<Object?>(
      'setores/$id',
      data: dto.toRequestJson(),
    );
    final saved = _single(response.data);
    if (saved.id != dto.id) {
      throw const FormatException('Setor diferente na resposta.');
    }
    return saved;
  });

  Future<void> remover(Setor dto) => repositoryRequest(() async {
    _validarEmpresa(dto);
    final id = repositoryResourceId(dto.id);
    final response = await _dio.delete<Object?>('setores/$id');
    if (response.statusCode == 204) return;
    final json = managementObject(response.data);
    if (json['removido'] != true || json['id'] != dto.id) {
      throw const FormatException('Remoção não confirmada pela API.');
    }
  });
}
