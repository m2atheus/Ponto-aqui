import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ponto_aqui_admin/app.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/providers/api_providers.dart';
import 'package:ponto_aqui_admin/providers/auth_provider.dart';
import 'package:ponto_aqui_admin/providers/empresas_provider.dart';
import 'package:ponto_aqui_admin/router/app_router.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/views/layouts/admin_scaffold.dart';
import 'package:ponto_aqui_admin/views/layouts/sidebar.dart';

import 'support/auth_fakes.dart';

Future<({GoRouter router, MemoryTokenStorage storage, AuthAdapter adapter})>
_mount(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  UserRole? role,
  MemoryTokenStorage? sharedStorage,
  AuthAdapter? sharedAdapter,
  bool mockEnabled = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final storage = sharedStorage ?? MemoryTokenStorage();
  final adapter = sharedAdapter ?? AuthAdapter();
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
        mockAuthEnabledProvider.overrideWithValue(mockEnabled),
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
  return (router: router, storage: storage, adapter: adapter);
}

Future<void> _login(
  WidgetTester tester, {
  String email = 'admin@teste.com',
  String password = 'admin',
}) async {
  await tester.enterText(find.byKey(const Key('login-email')), email);
  await tester.enterText(find.byKey(const Key('login-password')), password);
  await tester.tap(find.text('Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Drawer abaixo de 800 navega e redimensiona preservando a rota', (
    tester,
  ) async {
    final app = await _mount(
      tester,
      role: UserRole.rh,
      size: const Size(799, 760),
    );
    final shell = tester.element(find.byType(AdminScaffold));
    final scaffoldFinder = find.descendant(
      of: find.byType(AdminScaffold),
      matching: find.byType(Scaffold),
    );
    expect(tester.widget<Scaffold>(scaffoldFinder).drawer, isNotNull);
    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Empresas'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Setores'));
    await tester.pumpAndSettle();
    expect(app.router.routeInformationProvider.value.uri.path, '/setores');
    expect(tester.state<ScaffoldState>(scaffoldFinder).isDrawerOpen, isFalse);
    expect(tester.element(find.byType(AdminScaffold)), same(shell));

    tester.view.physicalSize = const Size(800, 760);
    await tester.pumpAndSettle();
    expect(tester.widget<Scaffold>(scaffoldFinder).drawer, isNull);
    expect(find.byTooltip('Abrir menu'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Setores'), findsOneWidget);
    expect(app.router.routeInformationProvider.value.uri.path, '/setores');

    tester.view.physicalSize = const Size(320, 760);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Dashboard'));
    await tester.pumpAndSettle();
    expect(app.router.routeInformationProvider.value.uri.path, '/dashboard');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards do RH ficam empilhados e com largura útil no celular', (
    tester,
  ) async {
    await _mount(tester, role: UserRole.rh, size: const Size(320, 760));
    Rect card(String titulo) => tester.getRect(
      find.ancestor(of: find.text(titulo), matching: find.byType(Card)).first,
    );
    final funcionarios = card('Total de Funcionários');
    final setores = card('Total de Setores');
    final escalas = card('Escalas Ativas');
    expect(funcionarios.width, closeTo(272, 0.1));
    expect(setores.left, funcionarios.left);
    expect(setores.top, greaterThanOrEqualTo(funcionarios.bottom + 16));
    expect(escalas.top, greaterThanOrEqualTo(setores.bottom + 16));
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 760),
    const Size(1024, 518),
    const Size(1024, 768),
  ]) {
    testWidgets('login com a marca funciona em ${size.width}px', (
      tester,
    ) async {
      await _mount(tester, size: size);
      expect(find.bySemanticsLabel('Ponto Aqui'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('login-email')));
      await tester.enterText(
        find.byKey(const Key('login-email')),
        'rh@teste.com',
      );
      await tester.enterText(find.byKey(const Key('login-password')), 'admin');
      await tester.ensureVisible(find.text('Entrar'));
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminScaffold), findsOneWidget);
      expect(find.text('Total de Funcionários'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets(
      'login de produção mantém formulário acessível em ${size.width}px',
      (tester) async {
        await _mount(tester, size: size, mockEnabled: false);
        expect(find.textContaining('Acessos de teste:'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Entrar'));
        await tester.tap(find.text('Entrar'));
        await tester.pumpAndSettle();
        expect(find.text('Informe um e-mail válido.'), findsOneWidget);
        expect(find.text('Informe a senha.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final role in UserRole.values) {
    testWidgets('Dashboard exibe apenas os cards do perfil ${role.name}', (
      tester,
    ) async {
      await _mount(tester, role: role);
      expect(
        find.text('Total de Empresas Cadastradas'),
        role == UserRole.superadmin ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Total de Funcionários'),
        role == UserRole.rh ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Total de Setores'),
        role == UserRole.rh ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Escalas Ativas'),
        role == UserRole.rh ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Justificativas Pendentes de Aprovação'),
        role == UserRole.gestor ? findsOneWidget : findsNothing,
      );
      if (role == UserRole.superadmin) {
        await tester.tap(find.text('Cadastrar Empresa'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byKey(const Key('empresa-email')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Superadmin não vê módulos internos nem acessa suas URLs', (
    tester,
  ) async {
    final app = await _mount(tester, role: UserRole.superadmin);
    expect(find.widgetWithText(ListTile, 'Empresas'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Escalas'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Setores'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Equipe'), findsNothing);
    for (final path in [
      '/escalas',
      '/setores',
      '/funcionarios',
      '/alocacoes',
      '/relatorios',
      '/equipe',
      '/justificativas',
    ]) {
      app.router.go(path);
      await tester.pumpAndSettle();
      expect(
        app.router.routeInformationProvider.value.uri.path,
        '/acesso-negado',
      );
    }
  });

  testWidgets('Empresas valida, cadastra, edita e desativa com confirmação', (
    tester,
  ) async {
    final app = await _mount(tester, role: UserRole.superadmin);
    app.router.go('/empresas');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova Empresa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe a razão social.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('empresa-nome')),
      'Empresa Nova',
    );
    await tester.enterText(
      find.byKey(const Key('empresa-cnpj')),
      '11222333000181',
    );
    await tester.enterText(
      find.byKey(const Key('empresa-email')),
      'RH@NOVA.COM',
    );
    await tester.enterText(
      find.byKey(const Key('empresa-admin-nome')),
      'RH Nova',
    );
    await tester.enterText(
      find.byKey(const Key('empresa-admin-senha')),
      'senha-inicial-segura',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('CNPJ já cadastrado.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('empresa-cnpj')),
      '12345678000195',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows, hasLength(3));
    expect(find.text('rh@nova.com'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('editar-empresa-empresa-3')),
    );
    await tester.tap(find.byKey(const Key('editar-empresa-empresa-3')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('empresa-nome')),
      'Empresa Editada',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Empresa Editada'), findsOneWidget);
    final button = find.byKey(const Key('desativar-empresa-empresa-3'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminApp)),
    );
    expect(container.read(empresasProvider).asData!.value.last.ativa, isTrue);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desativar'));
    await tester.pumpAndSettle();
    expect(container.read(empresasProvider).asData!.value.last.ativa, isFalse);
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows, hasLength(3));
    app.router.go('/dashboard');
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(
      app.adapter.requests.any(
        (request) =>
            request.method == 'POST' && request.uri.path.endsWith('/empresas'),
      ),
      isTrue,
    );
    expect(
      app.adapter.requests.any((request) => request.method == 'PUT'),
      isTrue,
    );
    expect(
      app.adapter.requests.any((request) => request.method == 'PATCH'),
      isTrue,
    );
    // Reinicia a árvore/providers: a nova sessão consulta os dados do servidor.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final reloaded = await _mount(
      tester,
      role: UserRole.superadmin,
      sharedStorage: app.storage,
      sharedAdapter: app.adapter,
    );
    reloaded.router.go('/empresas');
    await tester.pumpAndSettle();
    expect(find.text('Empresa Editada'), findsOneWidget);
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Falha da API mantém o formulário aberto sem cadastro local', (
    tester,
  ) async {
    final app = await _mount(tester, role: UserRole.superadmin);
    app.router.go('/empresas');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova Empresa'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('empresa-nome')),
      'Não persistida',
    );
    await tester.enterText(
      find.byKey(const Key('empresa-cnpj')),
      '12345678000195',
    );
    await tester.enterText(find.byKey(const Key('empresa-admin-nome')), 'RH');
    await tester.enterText(
      find.byKey(const Key('empresa-email')),
      'rh@erro.com',
    );
    await tester.enterText(
      find.byKey(const Key('empresa-admin-senha')),
      'SenhaForte123',
    );
    app.adapter.statusCode = 503;
    app.adapter.response = {
      'erro': {'mensagem': 'Banco indisponível.'},
    };
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Banco indisponível.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(app.adapter.empresas, hasLength(2));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows, hasLength(2));
  });

  testWidgets('Superadmin mockado não cadastra empresas nem chama a API', (
    tester,
  ) async {
    final app = await _mount(tester);
    await _login(tester);
    app.router.go('/empresas');
    await tester.pumpAndSettle();
    expect(
      find.text('Entre com uma conta real de Superadmin para acessar o banco.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Nova Empresa'),
          )
          .onPressed,
      isNull,
    );
    expect(
      app.adapter.requests.where(
        (request) => request.uri.path.contains('/empresas'),
      ),
      isEmpty,
    );
  });

  for (final role in [UserRole.superadmin, UserRole.rh]) {
    testWidgets('Tabela e formulário de ${role.name} cabem em tela estreita', (
      tester,
    ) async {
      final app = await _mount(tester, role: role, size: const Size(320, 568));
      app.router.go(role == UserRole.superadmin ? '/empresas' : '/escalas');
      await tester.pumpAndSettle();
      expect(
        find.byType(DataTable),
        role == UserRole.superadmin ? findsOneWidget : findsNothing,
      );
      await tester.tap(
        find.text(role == UserRole.superadmin ? 'Nova Empresa' : 'Nova Escala'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

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
      expect(find.text('Relatórios'), findsOneWidget);
      expect(find.text('Equipe'), findsOneWidget);
      for (final path in [
        '/setores',
        '/escalas',
        '/funcionarios',
        '/alocacoes',
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
    app.router.go('/empresas');
    await tester.pumpAndSettle();
    expect(app.router.routeInformationProvider.value.uri.path, '/login');
    await _login(tester);
    expect(app.router.routeInformationProvider.value.uri.path, '/empresas');
  });

  for (final path in ['/empresas', '/empresas/nova']) {
    testWidgets(
      'login real do RH abre Dashboard se retorno $path exige outro perfil',
      (tester) async {
        final app = await _mount(tester, mockEnabled: false);
        app.router.go(path);
        await tester.pumpAndSettle();
        expect(
          app.router.routeInformationProvider.value.uri.queryParameters['from'],
          path,
        );
        app.adapter.response = sessionFor(UserRole.rh).toJson();
        await _login(tester, email: 'rh@empresa.com', password: 'senha-segura');
        expect(
          app.router.routeInformationProvider.value.uri.path,
          '/dashboard',
        );
        expect(find.text('Acesso negado'), findsNothing);
        expect(find.text('Total de Funcionários'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('login real do RH retoma página permitida com filtros', (
    tester,
  ) async {
    final app = await _mount(tester, mockEnabled: false);
    app.router.go('/funcionarios?busca=Ana');
    await tester.pumpAndSettle();
    app.adapter.response = sessionFor(UserRole.rh).toJson();
    await _login(tester, email: 'rh@empresa.com', password: 'senha-segura');
    expect(
      app.router.routeInformationProvider.value.uri.toString(),
      '/funcionarios?busca=Ana',
    );
    expect(find.text('Acesso negado'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'troca de Superadmin para RH não herda página restrita da sessão anterior',
    (tester) async {
      final app = await _mount(
        tester,
        role: UserRole.superadmin,
        mockEnabled: false,
      );
      app.router.go('/empresas');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sair'));
      await tester.pumpAndSettle();
      app.adapter.response = sessionFor(UserRole.rh).toJson();
      await _login(tester, email: 'rh@empresa.com', password: 'senha-segura');
      expect(app.router.routeInformationProvider.value.uri.path, '/dashboard');
      expect(find.text('Acesso negado'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Empresas'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
