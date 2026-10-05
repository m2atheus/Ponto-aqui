import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/services/auth_service.dart';

import 'support/auth_fakes.dart';

void main() {
  late MemoryTokenStorage storage;
  late AuthAdapter adapter;
  late Dio dio;
  late AuthService service;
  setUp(() {
    storage = MemoryTokenStorage();
    adapter = AuthAdapter();
    dio = createDioClient(
      baseUrl: 'https://api.example.com/api/web/',
      tokenStorage: storage,
    )..httpClientAdapter = adapter;
    service = AuthService(dio, storage, enableMock: true);
  });
  tearDown(() => dio.close(force: true));

  test('superusuário persiste perfil e JWT sem acessar a rede', () async {
    final session = await service.login(' ADMIN@TESTE.COM ', 'admin');
    expect(session.isMock, isTrue);
    expect(session.user.role, UserRole.superadmin);
    expect(session.accessToken.split('.'), hasLength(3));
    expect(storage.session?['access_token'], session.accessToken);
    expect(adapter.requests, isEmpty);
    expect((await service.restoreSession())?.user.role, UserRole.superadmin);
    expect(adapter.requests, isEmpty);
    await service.logout();
    expect(storage.session, isNull);
  });

  test(
    'senha incorreta do usuário de teste não autentica nem chama API',
    () async {
      await expectLater(
        service.login('admin@teste.com', 'errada'),
        throwsA(isA<AuthFailure>()),
      );
      expect(storage.session, isNull);
      expect(adapter.requests, isEmpty);
    },
  );

  test('mock desativado usa API e não atribui SUPERADMIN', () async {
    final real = sessionFor(UserRole.rh);
    adapter.response = real.toJson();
    service = AuthService(dio, storage, enableMock: false);
    final result = await service.login('admin@teste.com', 'admin');
    expect(result.user.role, UserRole.rh);
    expect(result.isMock, isFalse);
    expect(adapter.requests.single.uri.path, '/api/web/auth/login');
    expect(adapter.requests.single.data, {
      'email': 'admin@teste.com',
      'senha': 'admin',
    });
    expect(
      adapter.requests.single.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('authorization')),
    );
  });

  test(
    'restauração confirma o papel no servidor mesmo com cache adulterado',
    () async {
      final cached = sessionFor(UserRole.superadmin);
      storage.session = cached.toJson();
      final actual = sessionFor(UserRole.gestor);
      adapter.response = {'usuario': actual.user.toJson()};
      final restored = await service.restoreSession();
      expect(restored?.user.role, UserRole.gestor);
      expect(restored?.user.companyId, 'empresa-1');
      expect(adapter.requests.single.uri.path, '/api/web/auth/me');
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer ${cached.accessToken}',
      );
      expect((storage.session?['usuario'] as Map)['papel'], 'GESTOR');
    },
  );

  test('sessão expirada é removida antes de consultar a API', () async {
    storage.session = sessionFor(
      UserRole.rh,
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    ).toJson();
    expect(await service.restoreSession(), isNull);
    expect(storage.session, isNull);
    expect(adapter.requests, isEmpty);
  });

  test('build sem mock descarta sessão de teste persistida', () async {
    await service.login('admin@teste.com', 'admin');
    final production = AuthService(dio, storage, enableMock: false);
    expect(await production.restoreSession(), isNull);
    expect(storage.session, isNull);
    expect(adapter.requests, isEmpty);
  });

  test('API rejeitando token limpa a sessão persistida', () async {
    storage.session = sessionFor(UserRole.rh).toJson();
    adapter.statusCode = 401;
    expect(await service.restoreSession(), isNull);
    expect(storage.session, isNull);
  });

  test('perfil sem acesso e RH sem empresa são rejeitados', () async {
    for (final user in [
      {...sessionFor(UserRole.rh).user.toJson(), 'papel': 'Funcionario'},
      {...sessionFor(UserRole.rh).user.toJson(), 'empresa_id': null},
    ]) {
      adapter.response = {
        'access_token': sessionFor(UserRole.rh).accessToken,
        'usuario': user,
      };
      await expectLater(
        service.login('usuario@empresa.com', 'senha'),
        throwsA(isA<AuthFailure>()),
      );
      expect(storage.session, isNull);
    }
  });

  test('falha ao persistir não retorna uma sessão autenticada', () async {
    storage.failWrites = true;
    await expectLater(
      service.login('admin@teste.com', 'admin'),
      throwsA(isA<AuthFailure>()),
    );
    expect(storage.session, isNull);
  });
}
