import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/auth_session.dart';
import 'storage/token_storage.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthService {
  AuthService(
    this._dio,
    this._storage, {
    required this.enableMock,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final Dio _dio;
  final TokenStorage _storage;
  final bool enableMock;
  final DateTime Function() _now;

  Future<AuthSession> login(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthFailure('Informe o e-mail e a senha.');
    }
    try {
      final AuthSession session;
      if (enableMock && normalizedEmail == 'admin@teste.com') {
        if (password != 'admin') {
          throw const AuthFailure('E-mail ou senha inválidos.');
        }
        session = _mockSession();
      } else {
        final response = await _dio.post<Map<String, dynamic>>(
          'auth/login',
          data: {'email': normalizedEmail, 'senha': password},
          options: Options(extra: {'skipAuth': true}),
        );
        session = AuthSession.fromJson({...response.data!, 'is_mock': false});
        if (AuthSession.isMockToken(session.accessToken)) {
          throw const FormatException('Token de teste retornado pela API.');
        }
      }
      if (!session.expiresAt.isAfter(_now())) {
        throw const AuthFailure('Sessão expirada. Entre novamente.');
      }
      await _storage.saveSession(session.toJson());
      return session;
    } on AuthFailure {
      rethrow;
    } on DioException catch (error) {
      throw _networkFailure(error);
    } on FormatException {
      throw const AuthFailure(
        'A API retornou uma sessão inválida ou um perfil sem acesso.',
      );
    } on TypeError {
      throw const AuthFailure('A resposta de autenticação da API é inválida.');
    } catch (_) {
      throw const AuthFailure(
        'Não foi possível salvar a sessão neste navegador.',
      );
    }
  }

  Future<AuthSession?> restoreSession() async {
    try {
      final json = await _storage.readSession();
      if (json == null) return null;
      final cached = AuthSession.fromJson(json);
      if (!cached.expiresAt.isAfter(_now())) return await _discardSession();
      if (cached.isMock || AuthSession.isMockToken(cached.accessToken)) {
        if (!enableMock ||
            !cached.isMock ||
            !AuthSession.isMockToken(cached.accessToken) ||
            cached.user.role != UserRole.superadmin ||
            cached.user.email != 'admin@teste.com') {
          return await _discardSession();
        }
        return cached;
      }
      // A API confirma o papel; privilégios salvos no navegador não são confiáveis.
      final response = await _dio.get<Map<String, dynamic>>('auth/me');
      final session = AuthSession(
        accessToken: cached.accessToken,
        user: AuthUser.fromJson(
          response.data!['usuario'] as Map<String, dynamic>,
        ),
      );
      await _storage.saveSession(session.toJson());
      return session;
    } on DioException catch (error) {
      if ([401, 403, 404].contains(error.response?.statusCode)) {
        return await _discardSession();
      }
      throw _networkFailure(error);
    } on FormatException {
      return await _discardSession();
    } on TypeError {
      return await _discardSession();
    } catch (_) {
      throw const AuthFailure('Não foi possível recuperar a sessão local.');
    }
  }

  Future<void> logout() async {
    try {
      await _storage.clearAccessToken();
    } catch (_) {
      throw const AuthFailure('Não foi possível remover a sessão local.');
    }
  }

  Future<AuthSession?> _discardSession() async {
    await _storage.clearAccessToken();
    return null;
  }

  AuthSession _mockSession() {
    final expires = _now().add(const Duration(hours: 8));
    String encode(Map<String, dynamic> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${encode({'alg': 'none', 'typ': 'JWT'})}.'
        '${encode({'sub': 'mock-superadmin', 'role': 'SUPERADMIN', 'exp': expires.millisecondsSinceEpoch ~/ 1000})}.${AuthSession.mockSignature}';
    return AuthSession(
      accessToken: token,
      isMock: true,
      user: const AuthUser(
        id: 'mock-superadmin',
        name: 'Superusuário Teste',
        email: 'admin@teste.com',
        role: UserRole.superadmin,
      ),
    );
  }

  AuthFailure _networkFailure(DioException error) =>
      switch (error.response?.statusCode) {
        401 => const AuthFailure('E-mail ou senha inválidos.'),
        403 => const AuthFailure('Este usuário não tem acesso ao painel.'),
        404 => const AuthFailure(
          'O endpoint de autenticação ainda não está disponível na API.',
        ),
        _ => const AuthFailure(
          'Não foi possível conectar à API. Tente novamente.',
        ),
      };
}
