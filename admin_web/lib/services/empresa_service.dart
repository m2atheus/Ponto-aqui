import 'package:dio/dio.dart';

import '../models/empresa.dart';

class EmpresaFailure implements Exception {
  const EmpresaFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class EmpresaService {
  EmpresaService(this._dio);
  final Dio _dio;

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map && data['erro'] is Map) {
        final message = data['erro']['mensagem'];
        if (message is String) throw EmpresaFailure(message);
      }
      throw EmpresaFailure(
        error.response?.statusCode == 401
            ? 'Sessão expirada. Entre novamente.'
            : 'Não foi possível acessar o banco. Verifique a API e tente novamente.',
      );
    } on TypeError {
      throw const EmpresaFailure('A API retornou dados de empresa inválidos.');
    }
  }

  Future<List<Empresa>> listar({CancelToken? cancelToken}) =>
      _request(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          'empresas',
          cancelToken: cancelToken,
        );
        return (response.data!['empresas'] as List)
            .map((item) => Empresa.fromJson(item as Map<String, dynamic>))
            .toList();
      });

  Future<Empresa> salvar(Empresa empresa, {String? senhaInicial}) =>
      _request(() async {
        final dados = empresa.toJson();
        if (senhaInicial != null && senhaInicial.isNotEmpty) {
          dados['admin_senha'] = senhaInicial;
        }
        final response = empresa.id.isEmpty
            ? await _dio.post<Map<String, dynamic>>('empresas', data: dados)
            : await _dio.put<Map<String, dynamic>>(
                'empresas/${empresa.id}',
                data: dados,
              );
        return Empresa.fromJson(
          response.data!['empresa'] as Map<String, dynamic>,
        );
      });

  Future<Empresa> desativar(Empresa empresa) => _request(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      'empresas/${empresa.id}',
      data: {'ativo': false},
    );
    return Empresa.fromJson(response.data!['empresa'] as Map<String, dynamic>);
  });
}
