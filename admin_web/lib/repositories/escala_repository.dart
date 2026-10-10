import 'package:dio/dio.dart';

import '../models/escala.dart';
import '../models/management_json.dart';
import 'repository_failure.dart';

class EscalaRepository {
  EscalaRepository(this.dio, {required this.empresaId});
  final Dio dio;
  final String empresaId;
  Escala _parse(Object? value) {
    final dto = Escala.fromJson(value);
    if (dto.empresaId != empresaId) {
      throw const RepositoryFailure(
        'Resposta incompatível com a empresa da sessão.',
      );
    }
    return dto;
  }

  Future<List<Escala>> listar({CancelToken? cancelToken}) =>
      repositoryRequest(() async {
        final response = await dio.get<Object?>(
          'escalas',
          cancelToken: cancelToken,
        );
        final lista = managementObject(response.data)['escalas'];
        if (lista is! List) {
          throw const FormatException('Lista de escalas inválida.');
        }
        return List.unmodifiable(lista.map(_parse));
      });
  Future<Escala> salvar(Escala dto) => repositoryRequest(() async {
    if (dto.empresaId != empresaId) {
      throw const RepositoryFailure('A escala pertence a outra empresa.');
    }
    final response = dto.id.isEmpty
        ? await dio.post<Object?>('escalas', data: dto.toRequestJson())
        : await dio.put<Object?>(
            'escalas/${repositoryResourceId(dto.id)}',
            data: dto.toRequestJson(),
          );
    final saved = _parse(managementObject(response.data)['escala']);
    if (dto.id.isNotEmpty && saved.id != dto.id) {
      throw const FormatException('Escala não confirmada.');
    }
    return saved;
  });
  Future<void> remover(String id) => repositoryRequest(() async {
    final response = await dio.delete<Object?>(
      'escalas/${repositoryResourceId(id)}',
    );
    final json = managementObject(response.data);
    if (json['id'] != id || json['removido'] != true) {
      throw const FormatException('Remoção não confirmada.');
    }
  });
}
