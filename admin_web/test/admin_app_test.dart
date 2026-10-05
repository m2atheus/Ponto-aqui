import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ponto_aqui_admin/app.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/providers/api_providers.dart';
import 'package:ponto_aqui_admin/providers/auth_provider.dart';
import 'package:ponto_aqui_admin/router/app_router.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/views/layouts/admin_scaffold.dart';
import 'package:ponto_aqui_admin/views/layouts/sidebar.dart';

import 'support/auth_fakes.dart';

Future<({GoRouter router, MemoryTokenStorage storage})> _mount(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  UserRole? role,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final storage = MemoryTokenStorage();
  final adapter = AuthAdapter();
  if (role != null) {
    final session = sessionFor(role);
    storage.session = session.toJson();
    adapter.response = {'usuario': session.user.toJson()};
  }
  final Dio dio = createDioClient(
    baseUrl: 'https://api.example.com/api/web/',
    tokenStorage: storage,
  )..httpClientAdapter = adapter;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    dio.close(force: true);
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(storage),
        dioProvider.overrideWithValue(dio),
        mockAuthEnabledProvider.overrideWithValue(true),
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  final router = ProviderScope.containerOf(
    tester.element(find.byType(AdminApp)),
  ).read(appRouterProvider);
  router.go('/dashboard');
  await tester.pumpAndSettle();
  return (router: router, storage: storage);
}

Future<void> _login(WidgetTester tester, {String password = 'admin'}) async {
  await tester.enterText(
    find.byKey(const Key('login-email')),
    'admin@teste.com',
  );
  await tester.enterText(find.byKey(const Key('login-password')), password);
  await tester.tap(find.text('Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('visitante faz login mock, persiste sessão e encerra acesso', (
    tester,
  ) async {
    final app = await _mount(tester);
    expect(app.router.routeInformationProvider.value.uri.path, '/login');
    await _login(tester, password: 'errada');
    expect(find.text('E-mail ou senha inválidos.'), findsOneWidget);
    expect(find.byType(AdminScaffold), findsNothing);
    await _login(tester);
    expect(app.router.routeInformationProvider.value.uri.path, '/dashboard');
    expect(find.text('SUPERADMIN'), findsOneWidget);
    expect(find.text('Cadastrar Empresa'), findsOneWidget);
    expect(app.storage.session?['is_mock'], isTrue);
    await tester.tap(find.byTooltip('Sair'));
    await tester.pumpAndSettle();
    expect(app.storage.session, isNull);
    expect(app.router.routeInformationProvider.value.uri.path, '/login');
    app.router.go('/setores');
    await tester.pumpAndSettle();
    expect(app.router.routeInformationProvider.value.uri.path, '/login');
    expect(tester.takeException(), isNull);
  });

  testWidgets('navegação troca o miolo e preserva Shell e Sidebar', (
    tester,
  ) async {
    final app = await _mount(tester, role: UserRole.rh);
    final shell = tester.element(find.byType(AdminScaffold));
    final sidebar = tester.element(find.byType(Sidebar));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminApp)),
    );
    await tester.tap(find.widgetWithText(ListTile, 'Setores'));
    await tester.pumpAndSettle();
    expect(app.router.routeInformationProvider.value.uri.path, '/setores');
    expect(tester.element(find.byType(AdminScaffold)), same(shell));
    expect(tester.element(find.byType(Sidebar)), same(sidebar));
    await tester.tap(find.widgetWithText(ListTile, 'Escalas'));
    await tester.pumpAndSettle();
    expect(app.router.routeInformationProvider.value.uri.path, '/escalas');
    expect(container.read(appRouterProvider), same(app.router));
    expect(tester.element(find.byType(Sidebar)), same(sidebar));
    expect(find.byType(Drawer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RH não vê cadastro de empresa e URL direta é bloqueada', (
    tester,
  ) async {
    final app = await _mount(tester, role: UserRole.rh);
    expect(find.text('Cadastrar Empresa'), findsNothing);
    expect(find.text('Setores'), findsOneWidget);
    app.router.go('/empresas/nova');
    await tester.pumpAndSettle();
    expect(
      app.router.routeInformationProvider.value.uri.path,
      '/acesso-negado',
    );
    expect(find.text('Acesso negado'), findsOneWidget);
  });

  testWidgets(
    'Gestor só vê módulos permitidos e não acessa cadastros por URL',
    (tester) async {
      final app = await _mount(tester, role: UserRole.gestor);
      expect(find.text('Cadastrar Empresa'), findsNothing);
      expect(find.text('Setores'), findsNothing);
      expect(find.text('Escalas'), findsNothing);
      expect(find.text('Funcionários'), findsNothing);
      expect(find.text('Relatórios'), findsNothing);
      expect(find.text('Equipe'), findsOneWidget);
      for (final path in [
        '/setores',
        '/escalas',
        '/funcionarios',
        '/alocacoes',
        '/relatorios',
      ]) {
        app.router.go(path);
        await tester.pumpAndSettle();
        expect(
          app.router.routeInformationProvider.value.uri.path,
          '/acesso-negado',
        );
      }
      app.router.go('/justificativas');
      await tester.pumpAndSettle();
      expect(
        app.router.routeInformationProvider.value.uri.path,
        '/justificativas',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('login retoma a URL protegida solicitada', (tester) async {
    final app = await _mount(tester);
    app.router.go('/escalas');
    await tester.pumpAndSettle();
    expect(app.router.routeInformationProvider.value.uri.path, '/login');
    await _login(tester);
    expect(app.router.routeInformationProvider.value.uri.path, '/escalas');
  });

  testWidgets('parâmetro de retorno externo não redireciona para outro site', (
    tester,
  ) async {
    final app = await _mount(tester);
    app.router.go('/login?from=https%3A%2F%2Foutro.example.com');
    await tester.pumpAndSettle();
    await _login(tester);
    expect(app.router.routeInformationProvider.value.uri.path, '/dashboard');
  });

  testWidgets('menu compacto abre e fecha sem overflow', (tester) async {
    await _mount(tester, size: const Size(320, 568), role: UserRole.rh);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Painel Administrativo'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Dashboard'));
    await tester.pumpAndSettle();
    final scaffold = tester.state<ScaffoldState>(
      find.descendant(
        of: find.byType(AdminScaffold),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.isDrawerOpen, isFalse);
    expect(find.text('Visão geral de ponto e jornada.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('URL desconhecida permite voltar ao Dashboard', (tester) async {
    final app = await _mount(tester, role: UserRole.rh);
    app.router.go('/inexistente');
    await tester.pumpAndSettle();
    expect(find.text('Página não encontrada.'), findsOneWidget);
    await tester.tap(find.text('Abrir Dashboard'));
    await tester.pumpAndSettle();
    expect(app.router.routeInformationProvider.value.uri.path, '/dashboard');
    expect(find.byType(AdminScaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
