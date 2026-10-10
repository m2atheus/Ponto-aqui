import 'package:dio/dio.dart';

class RepositoryFailure implements Exception {
  const RepositoryFailure(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;
  @override
  String toString() => message;
}

String repositoryResourceId(String value) {
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
    throw const RepositoryFailure(
      'Identificador inválido. Atualize o cadastro.',
    );
  }
  return value;
}

RepositoryFailure _httpFailure(DioException error) {
  final status = error.response?.statusCode;
  final body = error.response?.data;
  final detail = body is Map ? body['erro'] : null;
  final code = detail is Map && detail['codigo'] is String
      ? detail['codigo'] as String
      : null;
  String? message;
  if ({400, 404, 409, 413, 422}.contains(status) && detail is Map) {
    final value = detail['mensagem'];
    if (value is String &&
        value.trim().isNotEmpty &&
        value.length <= 500 &&
        !RegExp(
          r'<[^>]*>|Traceback|SQLAlchemy|psycopg|IntegrityError|SELECT\s|INSERT\s|UPDATE\s|DELETE\s',
          caseSensitive: false,
        ).hasMatch(value)) {
      message = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }
  message ??= switch (status) {
    400 || 422 => 'Confira os dados informados e tente novamente.',
    401 => 'Sessão expirada. Entre novamente.',
    403 => 'Seu perfil não tem permissão para realizar esta operação.',
    404 =>
      'Recurso não encontrado na API. Confira o endereço e atualize a lista.',
    409 =>
      'O cadastro conflita com dados existentes. Revise os dados informados.',
    413 =>
      'O arquivo excede o tamanho permitido. Selecione um anexo de até 10 MB.',
    _ => switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        'A API demorou para responder. Tente novamente.',
      DioExceptionType.connectionError =>
        'Não foi possível conectar à API. Confira sua conexão.',
      DioExceptionType.cancel =>
        'A operação foi interrompida. Atualize a tela.',
      _ => 'Não foi possível concluir a operação. Tente novamente.',
    },
  };
  return RepositoryFailure(message, statusCode: status, code: code);
}

Future<T> repositoryRequest<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on DioException catch (error) {
    throw _httpFailure(error);
  } on FormatException {
    throw const RepositoryFailure(
      'A API retornou dados inválidos para este cadastro.',
    );
  } on TypeError {
    throw const RepositoryFailure(
      'A API retornou dados inválidos para este cadastro.',
    );
  }
}
