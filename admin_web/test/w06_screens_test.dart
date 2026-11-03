import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/app.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/models/w06.dart';
import 'package:ponto_aqui_admin/providers/api_providers.dart';
import 'package:ponto_aqui_admin/providers/w06_provider.dart';
import 'package:ponto_aqui_admin/router/app_router.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';

import 'support/auth_fakes.dart';
import 'support/w06_api_fake.dart';

Future<ProviderContainer> mount(
  WidgetTester tester,
  String path, {
  UserRole role = UserRole.rh,
  W06ApiFake? api,
  Future<AnexoLocal?> Function()? picker,
  Size size = const Size(1440, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final storage = MemoryTokenStorage()..session = sessionFor(role).toJson();
  final dio = createDioClient(
    baseUrl: 'https://api.example.com/api/web/',
    tokenStorage: storage,
  )..httpClientAdapter = api ?? W06ApiFake(role: role);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    dio.close(force: true);
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        tokenStorageProvider.overrideWithValue(storage),
        if (picker != null)
          selecionarAtestadoProvider.overrideWithValue(picker),
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AdminApp)),
  );
  container.read(appRouterProvider).go(path);
  await tester.pumpAndSettle();
  return container;
}

Future<void> escolher(WidgetTester tester, Key key, String label) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> data(WidgetTester tester, String key, String value) async {
  final field = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextFormField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

Future<void> salvar(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('w06-salvar')));
  await tester.tap(find.byKey(const Key('w06-salvar')));
  await tester.pumpAndSettle();
}

Future<void> novoAfastamento(WidgetTester tester) async {
  await tester.tap(find.text('Afastamentos'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('novo-afastamento')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('funcionario-busca-input')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ana Silva · 001').last);
  await tester.pumpAndSettle();
  await data(tester, 'w06-inicio', '15/10/2026');
  await data(tester, 'w06-fim', '16/10/2026');
}

Future<void> consultar(
  WidgetTester tester, {
  String pessoa = 'Ana Silva · 001',
}) async {
  final field = find.byKey(const Key('funcionario-busca-input'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, pessoa.split(' · ').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  await tester.tap(find.text(pessoa).last);
  await tester.pumpAndSettle();
  await escolher(tester, const Key('relatorio-mes'), 'Outubro');
  await tester.enterText(find.byKey(const Key('relatorio-ano')), '2026');
  await tester.ensureVisible(find.byKey(const Key('gerar-espelho')));
  await tester.tap(find.byKey(const Key('gerar-espelho')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'feriado grava por POST, edita por PUT e sobrevive a reiniciar a tela',
    (tester) async {
      final api = W06ApiFake();
      await mount(tester, '/justificativas', api: api);
      expect(find.textContaining('Prévia interativa'), findsNothing);
      await tester.tap(find.byKey(const Key('novo-feriado')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('feriado-descricao')),
        'Recesso cadastrado',
      );
      await data(tester, 'w06-inicio', '31/02/2026');
      await salvar(tester);
      expect(
        find.text('Informe uma data válida (DD/MM/AAAA).'),
        findsOneWidget,
      );
      expect(api.feriados, hasLength(1));
      await data(tester, 'w06-inicio', '20/10/2026');
      await salvar(tester);
      expect(api.feriados, hasLength(2));
      final request = api.requests.lastWhere((r) => r.method == 'POST');
      expect((request.data as Map)['setor_id'], isNull);
      expect(request.headers['Authorization'], startsWith('Bearer '));
      await tester.ensureVisible(
        find.byKey(const Key('editar-feriado-feriado-3')),
      );
      await tester.tap(find.byKey(const Key('editar-feriado-feriado-3')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('feriado-descricao')),
        'Recesso atualizado',
      );
      await salvar(tester);
      expect(api.requests.any((r) => r.method == 'PUT'), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(tester, '/justificativas', api: api);
      expect(find.text('Recesso atualizado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'remoção cancelada não chama DELETE; confirmação remove do servidor',
    (tester) async {
      final api = W06ApiFake();
      await mount(tester, '/justificativas', api: api);
      final button = find.byKey(const Key('remover-feriado-feriado-1'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(api.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(api.feriados, isEmpty);
      expect(find.text('Feriado de teste'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('atestado envia bytes multipart e mostra anexo persistido', (
    tester,
  ) async {
    final api = W06ApiFake(), bytes = Uint8List.fromList([37, 80, 68, 70]);
    final container = await mount(
      tester,
      '/justificativas',
      api: api,
      picker: () async =>
          AnexoLocal('atestado.pdf', bytes.length, bytes: bytes),
    );
    await novoAfastamento(tester);
    await tester.ensureVisible(find.byKey(const Key('anexar-atestado')));
    await tester.tap(find.byKey(const Key('anexar-atestado')));
    await tester.pumpAndSettle();
    await salvar(tester);
    final request = api.requests.lastWhere((r) => r.method == 'POST');
    final form = request.data as FormData;
    expect(form.files.single.value.filename, 'atestado.pdf');
    expect(form.files.single.value.length, bytes.length);
    final saved = container.read(w06Provider).requireValue.afastamentos.last;
    expect(saved.anexoUrl, isNotNull);
    expect(saved.anexoLocal, isNull);
    expect(find.byKey(Key('baixar-anexo-${saved.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'afastamento edita mantendo funcionário e remove com confirmação',
    (tester) async {
      final api = W06ApiFake();
      await mount(tester, '/justificativas', api: api);
      await tester.tap(find.text('Afastamentos'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('editar-afastamento-afastamento-1')),
      );
      await tester.tap(
        find.byKey(const Key('editar-afastamento-afastamento-1')),
      );
      await tester.pumpAndSettle();
      await data(tester, 'w06-fim', '08/10/2026');
      await salvar(tester);
      final req = api.requests.lastWhere((r) => r.method == 'PUT');
      expect((req.data as Map).containsKey('funcionario_id'), isFalse);
      expect(api.afastamentos.single['data_fim'], '2026-10-08');
      await tester.ensureVisible(
        find.byKey(const Key('remover-afastamento-afastamento-1')),
      );
      await tester.tap(
        find.byKey(const Key('remover-afastamento-afastamento-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(api.afastamentos, isEmpty);
    },
  );
  testWidgets(
    'erro HTTP 400 mantém modal e exibe alerta vermelho sem cadastro local',
    (tester) async {
      final api = W06ApiFake();
      await mount(tester, '/justificativas', api: api);
      await novoAfastamento(tester);
      api.nextStatus = 400;
      api.nextBody = {
        'erro': {'mensagem': 'Período sobreposto. Revise as datas.'},
      };
      await salvar(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Período sobreposto. Revise as datas.'),
        findsNWidgets(2),
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.error,
      );
      expect(api.afastamentos, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('equipe consulta histórico real e preserva períodos encerrados', (
    tester,
  ) async {
    final api = W06ApiFake();
    await mount(tester, '/equipe', api: api);
    await tester.enterText(find.byKey(const Key('equipe-busca')), '001');
    await tester.pumpAndSettle();
    expect(find.text('Bruno Santos'), findsNothing);
    await tester.tap(find.byKey(const Key('historico-funcionario-1')));
    await tester.pumpAndSettle();
    expect(find.text('Fim: 10/10/2026'), findsOneWidget);
    expect(find.text('Início: 11/10/2026'), findsOneWidget);
    expect(find.text('Aparelhos / Segurança'), findsNothing);
    expect(
      api.requests.where((r) => r.uri.path.contains('/dispositivos')),
      isEmpty,
    );
    expect(api.requests.where((r) => r.method != 'GET'), isEmpty);
  });
  testWidgets(
    'relatório usa abonos e totais recebidos da API, sem cálculo fictício',
    (tester) async {
      final api = W06ApiFake();
      await mount(tester, '/relatorios', api: api);
      await consultar(tester, pessoa: 'Bruno Santos · 002');
      final table = tester.widget<DataTable>(find.byType(DataTable));
      final day = table.rows.singleWhere(
        (r) => r.key == const ValueKey('espelho-2026-10-05'),
      );
      expect((day.cells[5].child as Text).data, '00:00');
      expect((day.cells[6].child as Text).data, '08:00');
      expect((day.cells[7].child as Text).data, '00:00 / 00:00');
      expect(api.requests.last.uri.path, endsWith('/relatorios/espelho'));
      expect(
        api.requests.last.queryParameters['funcionario_id'],
        'funcionario-2',
      );
      expect(find.textContaining('Prévia'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('gestor consulta equipe e justificativas sem botões de mutação', (
    tester,
  ) async {
    final api = W06ApiFake(role: UserRole.gestor);
    final c = await mount(
      tester,
      '/justificativas',
      role: UserRole.gestor,
      api: api,
    );
    expect(find.byKey(const Key('novo-feriado')), findsNothing);
    expect(find.byKey(const Key('remover-feriado-feriado-1')), findsNothing);
    c.read(appRouterProvider).go('/equipe');
    await tester.pumpAndSettle();
    expect(find.text('Ana Silva'), findsOneWidget);
    expect(api.requests.where((r) => r.method != 'GET'), isEmpty);
  });
  testWidgets(
    'erro de carga permite tentar novamente e não mostra dados demonstrativos',
    (tester) async {
      final api = W06ApiFake();
      api.nextStatus = 503;
      api.nextBody = {
        'erro': {'mensagem': 'Banco indisponível.'},
      };
      await mount(tester, '/justificativas', api: api);
      expect(
        find.text('Não foi possível concluir a operação. Tente novamente.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.text('Feriado de teste'), findsOneWidget);
    },
  );
  for (final path in [
    '/equipe',
    '/justificativas',
    '/relatorios',
    '/escalas',
  ]) {
    testWidgets('$path funciona em 320 pixels sem overflow', (tester) async {
      await mount(tester, path, size: const Size(320, 760));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('carregamento mantém proteção enquanto aguarda API', (
    tester,
  ) async {
    final api = W06ApiFake();
    final c = await mount(tester, '/dashboard', api: api);
    api.readGate = Completer<void>();
    c.read(appRouterProvider).go('/justificativas');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    api.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Feriado de teste'), findsOneWidget);
  });
}
