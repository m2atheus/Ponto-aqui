import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/services/storage/token_storage.dart';

class MemoryTokenStorage implements TokenStorage {
  Map<String, dynamic>? session;
  bool failWrites = false;
  @override
  Future<String?> readAccessToken() async =>
      session?['access_token'] as String?;
  @override
  Future<void> saveAccessToken(String token) async =>
      session = {'access_token': token};
  @override
  Future<void> clearAccessToken() async => session = null;
  @override
  Future<Map<String, dynamic>?> readSession() async => session == null
      ? null
      : jsonDecode(jsonEncode(session)) as Map<String, dynamic>;
  @override
  Future<void> saveSession(Map<String, dynamic> value) async {
    if (failWrites) throw StateError('storage failed');
    session = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }
}

class AuthAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Map<String, dynamic> response = {};
  int statusCode = 200;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(response),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AuthSession sessionFor(UserRole role, {DateTime? expiresAt}) {
  final expires = expiresAt ?? DateTime.now().add(const Duration(hours: 1));
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': 'usuario-1',
            'exp': expires.millisecondsSinceEpoch ~/ 1000,
          }),
        ),
      )
      .replaceAll('=', '');
  return AuthSession(
    accessToken: 'header.$payload.test-signature',
    user: AuthUser(
      id: 'usuario-1',
      name: 'Usuário Teste',
      email: 'usuario@empresa.com',
      role: role,
      companyId: role == UserRole.superadmin ? null : 'empresa-1',
    ),
  );
}
