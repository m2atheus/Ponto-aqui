import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ponto_aqui_admin/app.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/models/management_mock.dart';
import 'package:ponto_aqui_admin/providers/api_providers.dart';
import 'package:ponto_aqui_admin/providers/auth_provider.dart';
import 'package:ponto_aqui_admin/providers/management_mock_provider.dart';
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
  for (final size in [const Size(320, 760), const Size(1024, 768)]) {
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

  testWidgets('Escalas valida horário e dias, edita e remove com confirmação', (
    tester,
  ) async {
    final app = await _mount(tester, role: UserRole.rh);
    app.router.go('/escalas');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova Escala'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('escala-nome')), 'Noturna');
    await tester.enterText(find.byKey(const Key('escala-entrada')), '25:00');
    for (var day = 1; day <= 5; day++) {
      await tester.tap(find.byKey(Key('dia-$day')));
    }
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Use HH:mm entre 00:00 e 23:59.'), findsOneWidget);
    expect(find.text('Selecione ao menos um dia.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('escala-entrada')), '22:00');
    await tester.enterText(find.byKey(const Key('escala-saida')), '06:00');
    await tester.tap(find.byKey(const Key('dia-7')));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('06:00 (+1 dia)'), findsOneWidget);
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows, hasLength(3));
    app.router.go('/dashboard');
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    app.router.go('/escalas');
    await tester.pumpAndSettle();
    final edit = find.byKey(const Key('editar-escala-escala-3'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('escala-nome')), 'Comercial');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Nome de escala já cadastrado.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('escala-nome')),
      'Noturna Revisada',
    );
    await tester.tap(find.text('Escala ativa'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    app.router.go('/dashboard');
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    app.router.go('/escalas');
    await tester.pumpAndSettle();
    final remove = find.byKey(const Key('remover-escala-escala-3'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Noturna Revisada'), findsOneWidget);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    expect(find.text('Noturna Revisada'), findsNothing);
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final role in [UserRole.superadmin, UserRole.rh]) {
    testWidgets('Tabela e formulário de ${role.name} cabem em tela estreita', (
      tester,
    ) async {
      final app = await _mount(tester, role: role, size: const Size(320, 568));
      app.router.go(role == UserRole.superadmin ? '/empresas' : '/escalas');
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
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

  testWidgets('Troca de empresa descarta escalas da sessão anterior', (
    tester,
  ) async {
    final app = await _mount(tester, role: UserRole.rh);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminApp)),
    );
    final notifier = container.read(escalasMockProvider.notifier);
    final first = container.read(escalasMockProvider).first;
    notifier.salvar(
      EscalaMock(
        id: '',
        empresaId: first.empresaId,
        nome: 'Exclusiva da Empresa A',
        entradaMinutos: 600,
        saidaMinutos: 1080,
        diasSemana: {2},
      ),
    );
    expect(container.read(escalasMockProvider), hasLength(3));
    app.adapter.response = {
      'access_token': sessionFor(UserRole.rh).accessToken,
      'usuario': {
        ...sessionFor(UserRole.rh).user.toJson(),
        'id': 'usuario-2',
        'empresa_id': 'empresa-2',
        'email': 'rh2@empresa.com',
      },
    };
    await tester.runAsync(
      () => container
          .read(authProvider.notifier)
          .login('rh2@empresa.com', 'senha'),
    );
    await tester.pumpAndSettle();
    final escalas = container.read(escalasMockProvider);
    expect(escalas, hasLength(2));
    expect(escalas.every((escala) => escala.empresaId == 'empresa-2'), isTrue);
    expect(
      escalas.any((escala) => escala.nome == 'Exclusiva da Empresa A'),
      isFalse,
    );
    expect(
      () => container.read(escalasMockProvider.notifier).remover(first),
      throwsStateError,
    );
  });
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
    app.router.go('/empresas');
    await tester.pumpAndSettle();
    expect(app.router.routeInformationProvider.value.uri.path, '/login');
    await _login(tester);
    expect(app.router.routeInformationProvider.value.uri.path, '/empresas');
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
