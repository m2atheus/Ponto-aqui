import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  TokenStorage(this._preferences);

  final SharedPreferencesAsync _preferences;

  static const _accessTokenKey = 'ponto_aqui_access_token';
  static const _sessionKey = 'ponto_aqui_session';

  Future<String?> readAccessToken() async {
    final session = await readSession();
    return session == null
        ? _preferences.getString(_accessTokenKey)
        : session['access_token'] as String?;
  }

  Future<void> saveAccessToken(String token) async {
    await _preferences.remove(_sessionKey);
    await _preferences.setString(_accessTokenKey, token);
  }

  Future<void> clearAccessToken() async {
    await _preferences.remove(_sessionKey);
    await _preferences.remove(_accessTokenKey);
  }

  Future<Map<String, dynamic>?> readSession() async {
    final value = await _preferences.getString(_sessionKey);
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  // Token e perfil são persistidos juntos para evitar sessões parciais.
  Future<void> saveSession(Map<String, dynamic> session) async {
    await _preferences.remove(_accessTokenKey);
    await _preferences.setString(_sessionKey, jsonEncode(session));
  }
}
