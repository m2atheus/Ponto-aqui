import 'package:dio/dio.dart';

import '../../models/auth_session.dart';

import '../storage/token_storage.dart';

Dio createDioClient({
  required String baseUrl,
  required TokenStorage tokenStorage,
}) {
  final apiUri = Uri.parse(baseUrl);

  if (!{'http', 'https'}.contains(apiUri.scheme) ||
      apiUri.host.isEmpty ||
      apiUri.hasQuery ||
      apiUri.hasFragment ||
      apiUri.userInfo.isNotEmpty) {
    throw ArgumentError('API_BASE_URL deve ser uma URL HTTP(S) válida.');
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        // URLs absolutas para outro servidor não recebem o JWT.
        if (options.uri.origin != apiUri.origin) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              message: 'Destino diferente da API configurada.',
            ),
          );
          return;
        }

        // A autenticação é centralizada; cabeçalhos antigos são descartados.
        options.headers.removeWhere(
          (key, _) => key.toLowerCase() == 'authorization',
        );

        // Reservado para chamadas públicas, como o futuro login.
        if (options.extra['skipAuth'] == true) {
          handler.next(options);
          return;
        }

        String? token;
        try {
          token = await tokenStorage.readAccessToken();
        } catch (_) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.unknown,
              message: 'Não foi possível acessar a sessão local.',
            ),
          );
          return;
        }

        if (token != null && token.trim().isNotEmpty) {
          if (AuthSession.isMockToken(token)) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message: 'A sessão de teste permite apenas navegação visual.',
              ),
            );
            return;
          }
          options.headers['Authorization'] = 'Bearer ${token.trim()}';
        }
        handler.next(options);
      },
    ),
  );

  return dio;
}
