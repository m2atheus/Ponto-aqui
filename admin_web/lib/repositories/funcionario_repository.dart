import 'package:dio/dio.dart';

import '../models/funcionario.dart';
import '../models/management_json.dart';
import 'repository_failure.dart';

class FuncionarioRepository {
  FuncionarioRepository(this._dio, {required this.empresaId});
  final Dio _dio;
  final String empresaId;

  Future<void> resetarSenha(String funcionarioId, String novaSenha) =>
      repositoryRequest(() async {
        if (novaSenha.length < 8 ||
            novaSenha.length > 1024 ||
            novaSenha.trim().isEmpty) {
          throw const RepositoryFailure(
            'A senha deve conter entre 8 e 1024 caracteres e não pode conter apenas espaços.',
          );
        }
        final id = repositoryResourceId(funcionarioId);
        final base = Uri.parse(_dio.options.baseUrl);
        final endpoint = '/api/v1/admin/funcionarios/$id/resetar-senha';
        final path = base.path.replaceFirst(RegExp(r'/api/web/?$'), endpoint);
        final url = base.path == path
            ? base.resolve(endpoint).toString()
            : base.replace(path: path, query: null, fragment: null).toString();
        final response = await _dio.put<Object?>(
          url,
          data: {'nova_senha': novaSenha},
        );
        final dto = managementObject(response.data);
        if (response.statusCode != 200 ||
            dto['funcionario_id'] != id ||
            dto['empresa_id'] != empresaId ||
            dto['usuario_id'] is! String ||
            (dto['usuario_id'] as String).isEmpty) {
          throw const FormatException(
            'Redefinição de senha não confirmada pela API.',
          );
        }
      });

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

  Future<List<Funcionario>> buscar(
    String texto, {
    CancelToken? cancelToken,
    bool? ativo,
  }) => repositoryRequest(() async {
    final q = texto.trim();
    final response = await _dio.get<Object?>(
      'funcionarios/busca',
      queryParameters: {'q': q, if (ativo != null) 'ativo': ativo.toString()},
      cancelToken: cancelToken,
    );
    final items = managementObject(response.data)['funcionarios'];
    if (items is! List || items.length > 20) {
      throw const FormatException('Resultados de busca inválidos.');
    }
    return List<Funcionario>.unmodifiable(items.map(_parse));
  });

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

  Future<Funcionario> reativarFuncionario(String id) =>
      repositoryRequest(() async {
        final resourceId = repositoryResourceId(id);
        final response = await _dio.put<Object?>(
          'funcionarios/$resourceId',
          data: {'ativo': true},
        );
        final saved = _single(response.data);
        if (saved.id != id || !saved.ativo) {
          throw const FormatException('Reativação não confirmada pela API.');
        }
        return saved;
      });

  Future<Funcionario> vincularAcessoApp(
    String funcionarioId,
    String email,
    String senha,
  ) => repositoryRequest(() async {
    final id = repositoryResourceId(funcionarioId);
    final base = Uri.parse(_dio.options.baseUrl);
    final endpoint = '/api/v1/funcionarios/$id/vincular-acesso';
    final path = base.path.replaceFirst(RegExp(r'/api/web/?$'), endpoint);
    // Mantém o servidor, o prefixo do proxy e o interceptor JWT existentes.
    final url = base.path == path
        ? base.resolve(endpoint).toString()
        : base.replace(path: path, query: null, fragment: null).toString();
    final response = await _dio.post<Object?>(
      url,
      data: {'email': email.trim().toLowerCase(), 'senha': senha},
    );
    final json = managementObject(response.data);
    final saved = _parse(json['funcionario']);
    final usuario = managementObject(json['usuario']);
    if (response.statusCode != 201 ||
        saved.id != id ||
        saved.usuarioId == null ||
        usuario['id'] != saved.usuarioId ||
        usuario['empresa_id'] != empresaId ||
        usuario['papel'] != 'FUNCIONARIO') {
      throw const FormatException('Vinculação não confirmada pela API.');
    }
    return saved;
  });
}
