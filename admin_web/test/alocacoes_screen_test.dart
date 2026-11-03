import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ponto_aqui_admin/app.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/providers/alocacoes_provider.dart';
import 'package:ponto_aqui_admin/providers/api_providers.dart';
import 'package:ponto_aqui_admin/providers/auth_provider.dart';
import 'package:ponto_aqui_admin/router/app_router.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/views/layouts/admin_scaffold.dart';

import 'support/auth_fakes.dart';
import 'support/management_api_fake.dart';

Future<({ManagementApiFake api, GoRouter router, ProviderContainer container})>
mountAlocacoes(
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
  final router = container.read(appRouterProvider)..go('/alocacoes');
  await tester.pumpAndSettle();
  return (api: adapter, router: router, container: container);
}

Future<void> preencherAlocacao(
  WidgetTester tester, {
  String inicio = '01/10/2026',
  String fim = '',
}) async {
  await tester.tap(find.byKey(const Key('alocacao-funcionario')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ana Silva — 001').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('alocacao-setor')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sede').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('alocacao-data-inicio')), inicio);
  await tester.enterText(find.byKey(const Key('alocacao-data-fim')), fim);
}

void main() {
  for (final comEscala in [false, true]) {
    for (final fim in ['', '   ']) {
      testWidgets(
        'fim vazio é nulo; escala=$comEscala; espaços=${fim.isNotEmpty}',
        (tester) async {
          final api = ManagementApiFake()..alocacoes.clear();
          await mountAlocacoes(tester, api: api);
          await tester.tap(find.byKey(const Key('nova-alocacao')));
          await tester.pumpAndSettle();
          await preencherAlocacao(tester, fim: fim);
          if (comEscala) {
            await tester.ensureVisible(
              find.byKey(const Key('alocacao-escala')),
            );
            await tester.tap(find.byKey(const Key('alocacao-escala')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Comercial').last);
            await tester.pumpAndSettle();
          }
          expect(find.text('Fim (opcional)'), findsOneWidget);
          expect(
            find.text(
              'A data de fim é opcional. Se deixada em branco, a alocação terá vigência por tempo indeterminado.',
            ),
            findsOneWidget,
          );
          await tester.ensureVisible(
            find.widgetWithText(FilledButton, 'Salvar'),
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
          await tester.pumpAndSettle();
          final post = api.requests.singleWhere((r) => r.method == 'POST');
          expect((post.data as Map).containsKey('data_fim'), isTrue);
          expect(post.data['data_fim'], isNull);
          expect(post.data['escala_id'], comEscala ? 'escala-1' : isNull);
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('encerrar vínculo ainda exige data final', (tester) async {
    final app = await mountAlocacoes(tester);
    await tester.tap(find.byKey(const Key('encerrar-alocacao-alocacao-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('alocacao-data-fim')), '');
    await tester.tap(find.text('Encerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe a data de fim.'), findsOneWidget);
    expect(app.api.requests.where((r) => r.method == 'PUT'), isEmpty);
  });

  testWidgets(
    'diálogo de encerramento tem só data fim, valida início e cabe em 320 pixels',
    (tester) async {
      final app = await mountAlocacoes(tester, size: const Size(320, 760));
      final abrir = find.byKey(const Key('encerrar-alocacao-alocacao-1'));
      await tester.ensureVisible(abrir);
      await tester.pumpAndSettle();
      await tester.tap(abrir);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.byType(TextFormField)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.byType(DropdownButtonFormField<String>),
        ),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const Key('alocacao-data-fim')),
        '30/09/2026',
      );
      await tester.ensureVisible(
        find.byKey(const Key('encerrar-alocacao-confirmar')),
      );
      await tester.tap(find.byKey(const Key('encerrar-alocacao-confirmar')));
      await tester.pumpAndSettle();
      expect(
        find.text('A data final não pode ser anterior à inicial.'),
        findsOneWidget,
      );
      expect(app.api.requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(
        find.byKey(const Key('alocacao-data-fim')),
        '01/10/2026',
      );
      await tester.ensureVisible(
        find.byKey(const Key('encerrar-alocacao-confirmar')),
      );
      await tester.tap(find.byKey(const Key('encerrar-alocacao-confirmar')));
      await tester.pumpAndSettle();
      expect(app.api.requests.singleWhere((r) => r.method == 'PUT').data, {
        'data_fim': '2026-10-01',
      });
      expect(app.api.alocacoes, hasLength(1));
      expect(app.api.requests.where((r) => r.method == 'DELETE'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'encerramento em andamento bloqueia envio duplo sem mudar os outros campos',
    (tester) async {
      final app = await mountAlocacoes(tester);
      final antes = Map<String, dynamic>.of(app.api.alocacao);
      await tester.tap(find.byKey(const Key('encerrar-alocacao-alocacao-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('alocacao-data-fim')),
        '31/10/2026',
      );
      app.api.writeGate = Completer<void>();
      await tester.tap(find.byKey(const Key('encerrar-alocacao-confirmar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('alocacao-data-fim')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('encerrar-alocacao-confirmar')),
            )
            .onPressed,
        isNull,
      );
      expect(app.api.requests.where((r) => r.method == 'PUT'), hasLength(1));
      app.api.writeGate!.complete();
      await tester.pumpAndSettle();
      final depois = Map<String, dynamic>.of(app.api.alocacao)
        ..['data_fim'] = antes['data_fim'];
      expect(depois, antes);
      expect(app.api.alocacao['data_fim'], '2026-10-31');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lista nomes, cria e encerra com PUT preservando a linha e o Shell',
    (tester) async {
      final api = ManagementApiFake()..alocacoes.clear();
      final app = await mountAlocacoes(tester, api: api);
      final shell = tester.element(find.byType(AdminScaffold));
      expect(find.text('Nenhuma alocação cadastrada.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nova-alocacao')));
      await tester.pumpAndSettle();
      await preencherAlocacao(tester);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Ana Silva'), findsOneWidget);
      expect(find.text('Sede'), findsOneWidget);
      expect(find.text('01/10/2026'), findsOneWidget);
      final post = api.requests.singleWhere((r) => r.method == 'POST');
      expect(post.data, {
        'funcionario_id': 'funcionario-1',
        'setor_id': 'setor-1',
        'data_inicio': '2026-10-01',
        'data_fim': null,
      });

      await tester.tap(find.byKey(const Key('encerrar-alocacao-alocacao-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alocacao-funcionario')), findsNothing);
      expect(find.byKey(const Key('alocacao-data-inicio')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('alocacao-data-fim')),
        '31/10/2026',
      );
      await tester.tap(find.text('Encerrar'));
      await tester.pumpAndSettle();
      expect(find.text('31/10/2026'), findsOneWidget);
      expect(
        find.byKey(const Key('encerrar-alocacao-alocacao-1')),
        findsNothing,
      );
      expect(api.requests.singleWhere((r) => r.method == 'PUT').data, {
        'data_fim': '2026-10-31',
      });
      expect(api.requests.where((r) => r.method == 'DELETE'), isEmpty);
      expect(api.alocacoes, hasLength(1));
      app.container.invalidate(alocacoesProvider);
      await tester.pumpAndSettle();
      expect(find.text('31/10/2026'), findsOneWidget);
      app.router.go('/funcionarios');
      await tester.pumpAndSettle();
      app.router.go('/alocacoes');
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(AdminScaffold)), same(shell));
      expect(find.text('Ana Silva'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inativos aparecem no histórico mas não nos Dropdowns', (
    tester,
  ) async {
    final api = ManagementApiFake();
    api.funcionarios.add({
      ...funcionarioJson(),
      'id': 'funcionario-2',
      'nome': 'Beto Inativo',
      'matricula': '002',
      'ativo': false,
    });
    api.setores.add({
      'id': 'setor-2',
      'nome': 'Setor Inativo',
      'empresa_id': 'empresa-1',
      'ativo': false,
    });
    api.alocacoes.add({
      ...alocacaoJson(),
      'id': 'alocacao-2',
      'funcionario_id': 'funcionario-2',
      'setor_id': 'setor-2',
      'data_fim': '2026-10-31',
    });
    await mountAlocacoes(tester, api: api);
    expect(find.text('Beto Inativo'), findsOneWidget);
    expect(find.text('Setor Inativo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nova-alocacao')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('alocacao-funcionario-input')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Ana Silva — 001'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Beto Inativo — 002'), findsNothing);
    await tester.tap(find.byKey(const Key('alocacao-setor-input')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Sede'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Setor Inativo'), findsNothing);
  });

  testWidgets('sobreposição 409 mantém modal e dados com SnackBar vermelho', (
    tester,
  ) async {
    final app = await mountAlocacoes(tester);
    await tester.tap(find.byKey(const Key('nova-alocacao')));
    await tester.pumpAndSettle();
    await preencherAlocacao(tester);
    app.api.nextStatus = 409;
    app.api.nextBody = {
      'erro': {
        'codigo': 'ALOCACAO_SOBREPOSTA',
        'mensagem': 'Este funcionário já possui alocação nesse setor no período informado.',
      },
    };
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(app.api.alocacoes, hasLength(1));
    final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(
      snackbar.backgroundColor,
      Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.error,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('alocacao-data-inicio')))
          .controller!
          .text,
      '01/10/2026',
    );
  });

  testWidgets('valida seleções, datas inválidas e fim anterior ao início', (
    tester,
  ) async {
    final app = await mountAlocacoes(tester);
    await tester.tap(find.byKey(const Key('nova-alocacao')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Selecione o funcionário.'), findsOneWidget);
    expect(find.text('Selecione o setor.'), findsOneWidget);
    await preencherAlocacao(tester, inicio: '01/10/2026', fim: '30/09/2026');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(
      find.text('A data final não pode ser anterior à inicial.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('alocacao-data-inicio')),
      '30/02/2026',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe uma data válida em DD/MM/AAAA.'), findsWidgets);
    expect(app.api.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets(
    'calendário preenche data no formato brasileiro sem alterar fuso',
    (tester) async {
      await mountAlocacoes(tester);
      await tester.tap(find.byKey(const Key('nova-alocacao')));
      await tester.pumpAndSettle();
      await preencherAlocacao(tester);
      await tester.tap(find.byTooltip('Selecionar data de início'));
      await tester.pumpAndSettle();
      tester
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(DateTime(2026, 10, 15));
      await tester.pump();
      await tester.tap(find.text('Selecionar'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('alocacao-data-inicio')),
            )
            .controller!
            .text,
        '15/10/2026',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('salvamento pendente bloqueia submissão repetida e campos', (
    tester,
  ) async {
    final app = await mountAlocacoes(tester);
    app.api.writeGate = Completer<void>();
    await tester.tap(find.byKey(const Key('nova-alocacao')));
    await tester.pumpAndSettle();
    await preencherAlocacao(tester, fim: '31/10/2026');
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Salvando...'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('alocacao-funcionario-input')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('alocacao-data-fim')))
          .enabled,
      isFalse,
    );
    expect(app.api.requests.where((r) => r.method == 'POST'), hasLength(1));
    app.api.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('falha de encerramento conserva linha em aberto', (tester) async {
    final app = await mountAlocacoes(tester);
    await tester.tap(find.byKey(const Key('encerrar-alocacao-alocacao-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('alocacao-data-fim')),
      '31/10/2026',
    );
    app.api.nextStatus = 503;
    app.api.nextBody = {
      'erro': {'mensagem': 'Banco indisponível'},
    };
    await tester.tap(find.text('Encerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(app.api.alocacao['data_fim'], isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('encerrar-alocacao-alocacao-1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'consulta falha permite repetir e ausência de setores orienta o RH',
    (tester) async {
      final api = ManagementApiFake()..nextStatus = 503;
      await mountAlocacoes(tester, api: api);
      expect(find.text('Tentar novamente'), findsOneWidget);
      api.setores.clear();
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nova-alocacao')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('alocacao-setor-input')));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum resultado encontrado.'), findsOneWidget);
      expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  testWidgets(
    'logout durante gravação não injeta registros na próxima sessão',
    (tester) async {
      final app = await mountAlocacoes(tester);
      app.api.writeGate = Completer<void>();
      await tester.tap(find.byKey(const Key('nova-alocacao')));
      await tester.pumpAndSettle();
      await preencherAlocacao(tester);
      await tester.tap(find.text('Salvar'));
      await tester.pump();
      await app.container.read(authProvider.notifier).logout();
      await tester.pump();
      app.api.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(
        app.container.read(alocacoesProvider).asData?.value.alocacoes,
        isEmpty,
      );
      expect(find.byType(DataTable), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tabela, Dropdowns e modal cabem em 320 pixels', (tester) async {
    await mountAlocacoes(tester, size: const Size(320, 760));
    await tester.ensureVisible(find.byKey(const Key('nova-alocacao')));
    await tester.tap(find.byKey(const Key('nova-alocacao')));
    await tester.pumpAndSettle();
    await preencherAlocacao(tester);
    await tester.ensureVisible(find.text('Salvar'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
