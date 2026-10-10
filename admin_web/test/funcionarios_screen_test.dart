import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ponto_aqui_admin/app.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/providers/api_providers.dart';
import 'package:ponto_aqui_admin/providers/auth_provider.dart';
import 'package:ponto_aqui_admin/providers/funcionarios_provider.dart';
import 'package:ponto_aqui_admin/router/app_router.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/views/layouts/admin_scaffold.dart';
import 'package:ponto_aqui_admin/views/widgets/responsive_table_container.dart';

import 'support/auth_fakes.dart';
import 'support/management_api_fake.dart';

Future<({ManagementApiFake api, GoRouter router, ProviderContainer container})>
mountFuncionarios(
  WidgetTester tester, {
  ManagementApiFake? api,
  Size size = const Size(1440, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final adapter = api ?? ManagementApiFake();
  final storage = MemoryTokenStorage()
    ..session = sessionFor(UserRole.rh).toJson();
  final dio = createDioClient(
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
        dioProvider.overrideWithValue(dio),
        tokenStorageProvider.overrideWithValue(storage),
        mockAuthEnabledProvider.overrideWithValue(true),
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AdminApp)),
  );
  final router = container.read(appRouterProvider)..go('/funcionarios');
  await tester.pumpAndSettle();
  return (api: adapter, router: router, container: container);
}

Future<void> preencher(
  WidgetTester tester, {
  String nome = 'Beto Souza',
  String matricula = '002',
  String cargo = 'Motorista',
}) async {
  await tester.enterText(find.byKey(const Key('funcionario-nome')), nome);
  await tester.enterText(
    find.byKey(const Key('funcionario-matricula')),
    matricula,
  );
  await tester.enterText(find.byKey(const Key('funcionario-cargo')), cargo);
}

void main() {
  testWidgets(
    'reativação confirma, bloqueia envio duplo e persiste após recarregar',
    (tester) async {
      final api = ManagementApiFake();
      api.funcionarios.single.addAll({
        'ativo': false,
        'usuario_id': 'conta-existente',
      });
      final app = await mountFuncionarios(tester, api: api);
      final acao = find.byKey(const Key('reativar-funcionario-funcionario-1'));
      await tester.tap(acao);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(api.requests.where((r) => r.method == 'PUT'), isEmpty);

      api.writeGate = Completer<void>();
      await tester.tap(acao);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reativar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<IconButton>(acao).onPressed, isNull);
      expect(api.funcionarios.single['ativo'], isFalse);
      expect(api.requests.where((r) => r.method == 'PUT'), hasLength(1));
      api.writeGate!.complete();
      await tester.pumpAndSettle();
      final put = api.requests.singleWhere((r) => r.method == 'PUT');
      expect(put.uri.path, '/api/web/funcionarios/funcionario-1');
      expect(put.data, {'ativo': true});
      expect(put.headers['Authorization'], startsWith('Bearer '));
      expect(api.funcionarios.single['ativo'], isTrue);
      expect(
        app.container.read(funcionariosProvider).requireValue.single.usuarioId,
        'conta-existente',
      );
      expect(find.text('Funcionário reativado.'), findsOneWidget);
      expect(
        find.byKey(const Key('desativar-funcionario-funcionario-1')),
        findsOneWidget,
      );
      expect(api.alocacoes, hasLength(1));
      await tester.tap(find.byTooltip('Atualizar funcionários'));
      await tester.pumpAndSettle();
      expect(
        app.container.read(funcionariosProvider).requireValue.single.ativo,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'erro na reativação mantém status inativo e informa a mensagem da API',
    (tester) async {
      final api = ManagementApiFake();
      api.funcionarios.single['ativo'] = false;
      final app = await mountFuncionarios(tester, api: api);
      await tester.tap(
        find.byKey(const Key('reativar-funcionario-funcionario-1')),
      );
      await tester.pumpAndSettle();
      api.nextStatus = 400;
      api.nextBody = {
        'erro': {'mensagem': 'Não foi possível reativar este cadastro.'},
      };
      await tester.tap(find.text('Reativar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Não foi possível reativar este cadastro.'),
        findsOneWidget,
      );
      expect(
        app.container.read(funcionariosProvider).requireValue.single.ativo,
        isFalse,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('reativar-funcionario-funcionario-1')),
            )
            .onPressed,
        isNotNull,
      );
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(
        snack.backgroundColor,
        Theme.of(tester.element(find.byType(DataTable))).colorScheme.error,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'arrastar tabela no celular revela colunas sem mover a página na horizontal',
    (tester) async {
      await mountFuncionarios(tester, size: const Size(320, 760));
      final horizontal = find.descendant(
        of: find.byType(ResponsiveTableContainer),
        matching: find.byType(SingleChildScrollView),
      );
      final scroll = tester.widget<SingleChildScrollView>(horizontal);
      expect(scroll.controller!.offset, 0);
      await tester.drag(horizontal, const Offset(-240, 0));
      await tester.pumpAndSettle();
      expect(scroll.controller!.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lista, cria, edita, desativa e recarrega mantendo o Shell', (
    tester,
  ) async {
    final app = await mountFuncionarios(tester);
    final shell = tester.element(find.byType(AdminScaffold));
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Ana Silva'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);

    await tester.tap(find.byKey(const Key('novo-funcionario')));
    await tester.pumpAndSettle();
    await preencher(tester);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Beto Souza'), findsOneWidget);

    await tester.tap(find.byKey(const Key('editar-funcionario-funcionario-2')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('funcionario-nome')))
          .controller!
          .text,
      'Beto Souza',
    );
    await preencher(tester, nome: 'Roberto Souza');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Roberto Souza'), findsOneWidget);
    expect(find.text('Beto Souza'), findsNothing);

    await tester.tap(
      find.byKey(const Key('desativar-funcionario-funcionario-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desativar'));
    await tester.pumpAndSettle();
    expect(app.api.funcionarios.last['ativo'], isFalse);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('reativar-funcionario-funcionario-2')),
          )
          .onPressed,
      isNotNull,
    );

    app.router.go('/dashboard');
    await tester.pumpAndSettle();
    app.router.go('/funcionarios');
    app.container.invalidate(funcionariosProvider);
    await tester.pumpAndSettle();
    expect(find.text('Roberto Souza'), findsOneWidget);
    expect(tester.element(find.byType(AdminScaffold)), same(shell));
    expect(
      app.api.requests.where(
        (r) => r.uri.path.contains('/funcionarios') && r.method == 'DELETE',
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'campos obrigatórios barram envio e desativação exige confirmação',
    (tester) async {
      final app = await mountFuncionarios(tester);
      await tester.tap(find.byKey(const Key('novo-funcionario')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Informe o nome.'), findsOneWidget);
      expect(find.text('Informe a matrícula.'), findsOneWidget);
      expect(app.api.requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('desativar-funcionario-funcionario-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(app.api.requests.where((r) => r.method == 'PUT'), isEmpty);
    },
  );

  testWidgets(
    'matrícula repetida exibe SnackBar vermelho e preserva formulário',
    (tester) async {
      final app = await mountFuncionarios(tester);
      await tester.tap(find.byKey(const Key('novo-funcionario')));
      await tester.pumpAndSettle();
      await preencher(tester, matricula: '001');
      app.api.nextStatus = 409;
      app.api.nextBody = {
        'erro': {
          'codigo': 'matricula_duplicada',
          'mensagem': 'Esta matrícula já está cadastrada na empresa.',
        },
      };
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('funcionario-nome')))
            .controller!
            .text,
        'Beto Souza',
      );
      expect(
        find.text('Esta matrícula já está cadastrada na empresa.'),
        findsWidgets,
      );
      final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(
        snackbar.backgroundColor,
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.error,
      );
      expect(app.api.funcionarios, hasLength(1));
    },
  );

  testWidgets('formulário bloqueia submissões repetidas durante POST', (
    tester,
  ) async {
    final app = await mountFuncionarios(tester);
    app.api.writeGate = Completer<void>();
    await tester.tap(find.byKey(const Key('novo-funcionario')));
    await tester.pumpAndSettle();
    await preencher(tester);
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Salvando...'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('funcionario-nome')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Salvando...'),
          )
          .onPressed,
      isNull,
    );
    expect(app.api.requests.where((r) => r.method == 'POST'), hasLength(1));
    app.api.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Beto Souza'), findsOneWidget);
  });

  testWidgets('falha de desativação mantém funcionário ativo e avisa o RH', (
    tester,
  ) async {
    final app = await mountFuncionarios(tester);
    app.api.nextStatus = 400;
    app.api.nextBody = {
      'erro': {'mensagem': 'Não é possível desativar este cadastro.'},
    };
    await tester.tap(
      find.byKey(const Key('desativar-funcionario-funcionario-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desativar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Não é possível desativar este cadastro.'),
      findsOneWidget,
    );
    expect(app.api.funcionarios.single['ativo'], isTrue);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('desativar-funcionario-funcionario-1')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'falha no GET permite tentar novamente e lista vazia é informativa',
    (tester) async {
      final api = ManagementApiFake()..nextStatus = 503;
      final app = await mountFuncionarios(tester, api: api);
      expect(find.text('Tentar novamente'), findsOneWidget);
      api.funcionarios.clear();
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum funcionário cadastrado.'), findsOneWidget);
      expect(app.container.read(funcionariosProvider).hasError, isFalse);
    },
  );

  testWidgets('resposta de POST após logout não atualiza a sessão', (
    tester,
  ) async {
    final app = await mountFuncionarios(tester);
    app.api.writeGate = Completer<void>();
    await tester.tap(find.byKey(const Key('novo-funcionario')));
    await tester.pumpAndSettle();
    await preencher(tester);
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await app.container.read(authProvider.notifier).logout();
    await tester.pump();
    app.api.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(app.container.read(authProvider).asData?.value, isNull);
    expect(app.container.read(funcionariosProvider).asData?.value, isEmpty);
    expect(find.text('Beto Souza'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabela e formulário cabem em 320 pixels sem overflow', (
    tester,
  ) async {
    await mountFuncionarios(tester, size: const Size(320, 760));
    expect(find.byType(DataTable), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('novo-funcionario')));
    await tester.tap(find.byKey(const Key('novo-funcionario')));
    await tester.pumpAndSettle();
    await preencher(tester);
    await tester.ensureVisible(find.text('Salvar'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Beto Souza'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
