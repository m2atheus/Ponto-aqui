import 'dart:convert';

enum UserRole {
  superadmin,
  rh,
  gestor;

  String get apiValue => name.toUpperCase();
  bool get canManageCompany => this == superadmin || this == rh;
  static UserRole fromApi(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'SUPERADMIN' => superadmin,
        'RH' => rh,
        'GESTOR' => gestor,
        _ => throw const FormatException('Perfil sem acesso ao painel.'),
      };
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.companyId,
  });
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String? companyId;
  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final role = UserRole.fromApi(json['papel']);
    final companyId = json['empresa_id'] as String?;
    if (role != UserRole.superadmin &&
        (companyId == null || companyId.isEmpty)) {
      throw const FormatException('Empresa ausente na sessão.');
    }
    return AuthUser(
      id: json['id'] as String,
      name: json['nome'] as String,
      email: json['email'] as String,
      role: role,
      companyId: companyId,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': name,
    'email': email,
    'papel': role.apiValue,
    'empresa_id': companyId,
  };
}

class AuthSession {
  AuthSession({
    required this.accessToken,
    required this.user,
    this.isMock = false,
  }) : expiresAt = expirationOf(accessToken);
  final String accessToken;
  final AuthUser user;
  final bool isMock;
  final DateTime expiresAt;
  static const mockSignature = 'ponto-aqui-mock';
  static bool isMockToken(String token) => token.endsWith('.$mockSignature');
  // exp controla apenas a expiração local; a assinatura é validada pelo Flask.
  static DateTime expirationOf(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw const FormatException('JWT inválido.');
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;
    final exp = payload['exp'];
    if (exp is! int) throw const FormatException('JWT sem expiração.');
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
  }

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'usuario': user.toJson(),
    'is_mock': isMock,
  };
  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['access_token'] as String,
    user: AuthUser.fromJson(json['usuario'] as Map<String, dynamic>),
    isMock: json['is_mock'] == true,
  );
}
