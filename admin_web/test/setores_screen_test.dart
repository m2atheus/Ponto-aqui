import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ponto_aqui_admin/app.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/providers/api_providers.dart';
import 'package:ponto_aqui_admin/providers/auth_provider.dart';
import 'package:ponto_aqui_admin/providers/setores_provider.dart';
import 'package:ponto_aqui_admin/router/app_router.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/views/layouts/admin_scaffold.dart';

import 'support/auth_fakes.dart';
import 'support/management_api_fake.dart';

// Tiles locais: os testes de mapa não acessam OpenStreetMap nem Supabase.
class MemoryTileProvider extends TileProvider {
  static final _image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
    ),
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _image;
}

Future<({ManagementApiFake api, GoRouter router, ProviderContainer container})>
mountSetores(
  WidgetTester tester, {
  ManagementApiFake? api,
  Size size = const Size(1440, 1000),
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
        setorTileProviderFactoryProvider.overrideWithValue(
          MemoryTileProvider.new,
        ),
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AdminApp)),
  );
  final router = container.read(appRouterProvider)..go('/setores');
  await tester.pumpAndSettle();
  return (api: adapter, router: router, container: container);
}

Future<void> abrirNovo(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('novo-setor')));
  await tester.tap(find.byKey(const Key('novo-setor')));
  await tester.pumpAndSettle();
}

Future<void> digitar(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mapa real captura clique e slider altera círculo em metros', (
    tester,
  ) async {
    final app = await mountSetores(tester);
    final shell = tester.element(find.byType(AdminScaffold));
    await abrirNovo(tester);
    expect(find.byKey(const Key('setor-pino')), findsNothing);
    await digitar(tester, 'setor-nome', 'Filial');
    await digitar(tester, 'setor-endereco', 'Av. Brasil, 200');
    await tester.ensureVisible(find.byType(FlutterMap));
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setor-pino')), findsOneWidget);
    tester
        .widget<Slider>(find.byKey(const Key('setor-raio-slider')))
        .onChanged!(350);
    await tester.pumpAndSettle();
    final circle = tester
        .widget<CircleLayer>(find.byType(CircleLayer))
        .circles
        .single;
    expect(circle.radius, 350);
    expect(circle.useRadiusInMeter, isTrue);
    await tester.tap(find.byKey(const Key('setor-selfie')));
    await tester.tap(find.byKey(const Key('setor-acao-fora')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar para análise').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Filial'), findsOneWidget);
    final post = app.api.requests.singleWhere((r) => r.method == 'POST');
    expect(post.data['raio_metros'], 350);
    expect(post.data['latitude'], circle.point.latitude);
    expect(post.data['longitude'], circle.point.longitude);
    expect(post.data['acao_fora_perimetro'], 'PENDENTE');
    expect(post.data['exige_selfie'], isTrue);
    app.container.invalidate(setoresProvider);
    await tester.pumpAndSettle();
    expect(find.text('Filial'), findsOneWidget);
    app.router.go('/funcionarios');
    await tester.pumpAndSettle();
    app.router.go('/setores');
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(AdminScaffold)), same(shell));
    expect(tester.takeException(), isNull);
  });

  testWidgets('editar preserva coordenadas, raio acima do slider e políticas', (
    tester,
  ) async {
    final api = ManagementApiFake();
    api.setores.single.addAll({
      'raio_metros': 7500,
      'exige_selfie': true,
      'ignorar_localizacao': true,
      'acao_fora_perimetro': 'PENDENTE',
    });
    await mountSetores(tester, api: api);
    await tester.tap(find.byKey(const Key('editar-setor-setor-1')));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 7500);
    expect(
      tester
          .widget<CircleLayer>(find.byType(CircleLayer))
          .circles
          .single
          .radius,
      7500,
    );
    await digitar(tester, 'setor-nome', 'Sede Central');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final put = api.requests.singleWhere((r) => r.method == 'PUT');
    expect(put.data['latitude'], -8.0476);
    expect(put.data['longitude'], -34.877);
    expect(put.data['raio_metros'], 7500);
    expect(put.data['ignorar_localizacao'], isTrue);
    expect(put.data['exige_selfie'], isTrue);
    expect(put.data['acao_fora_perimetro'], 'PENDENTE');
    expect(find.text('Sede Central'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final status in [400, 409]) {
    testWidgets(
      'remover confirma e bloqueio $status mantém linha com alerta vermelho',
      (tester) async {
        final app = await mountSetores(tester);
        await tester.tap(find.byKey(const Key('remover-setor-setor-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(app.api.requests.where((r) => r.method == 'DELETE'), isEmpty);
        await tester.tap(find.byKey(const Key('remover-setor-setor-1')));
        await tester.pumpAndSettle();
        app.api.nextStatus = status;
        app.api.nextBody = {
          'erro': {'mensagem': 'Setor possui funcionários alocados.'},
        };
        await tester.tap(find.text('Remover'));
        await tester.pumpAndSettle();
        expect(find.text('Sede'), findsOneWidget);
        expect(
          find.text('Setor possui funcionários alocados.'),
          findsOneWidget,
        );
        final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(
          snackbar.backgroundColor,
          Theme.of(tester.element(find.byType(DataTable))).colorScheme.error,
        );
        await tester.tap(find.byKey(const Key('remover-setor-setor-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remover'));
        await tester.pumpAndSettle();
        expect(find.text('Nenhum setor cadastrado.'), findsOneWidget);
      },
    );
  }

  testWidgets('valida nome, posição, valores finitos e raio maior que zero', (
    tester,
  ) async {
    final app = await mountSetores(tester);
    await abrirNovo(tester);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe o nome.'), findsOneWidget);
    await digitar(tester, 'setor-nome', 'Rua');
    await digitar(tester, 'setor-latitude', '91');
    await digitar(tester, 'setor-longitude', 'Infinity');
    await digitar(tester, 'setor-raio', '0');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe um raio maior que zero.'), findsOneWidget);
    expect(app.api.requests.where((r) => r.method == 'POST'), isEmpty);
    await digitar(tester, 'setor-latitude', '-8,0476');
    await digitar(tester, 'setor-longitude', '-34,877');
    await digitar(tester, 'setor-raio', '75,50');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(
      app.api.requests
          .singleWhere((r) => r.method == 'POST')
          .data['raio_metros'],
      75.5,
    );
  });

  testWidgets('requisição pendente bloqueia edição, mapa e envio repetido', (
    tester,
  ) async {
    final app = await mountSetores(tester);
    await abrirNovo(tester);
    await digitar(tester, 'setor-nome', 'Filial');
    await digitar(tester, 'setor-latitude', '-8');
    await digitar(tester, 'setor-longitude', '-34');
    app.api.writeGate = Completer<void>();
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Salvando...'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byKey(const Key('setor-nome'))).enabled,
      isFalse,
    );
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    expect(
      tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .options
          .interactionOptions
          .flags,
      InteractiveFlag.none,
    );
    expect(app.api.requests.where((r) => r.method == 'POST'), hasLength(1));
    app.api.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'erro de cadastro mantém formulário e não inventa linha na tabela',
    (tester) async {
      final app = await mountSetores(tester);
      await abrirNovo(tester);
      await digitar(tester, 'setor-nome', 'Sede');
      await digitar(tester, 'setor-latitude', '-8');
      await digitar(tester, 'setor-longitude', '-34');
      app.api.nextStatus = 409;
      app.api.nextBody = {
        'erro': {'mensagem': 'Já existe um setor com esse nome nesta empresa.'},
      };
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(app.api.setores, hasLength(1));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('setor-nome')))
            .controller!
            .text,
        'Sede',
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.error,
      );
      expect(app.container.read(setoresProvider).asData!.value, hasLength(1));
    },
  );

  testWidgets(
    'logout durante cadastro descarta atualização da sessão anterior',
    (tester) async {
      final app = await mountSetores(tester);
      await abrirNovo(tester);
      await digitar(tester, 'setor-nome', 'Filial');
      await digitar(tester, 'setor-latitude', '-8');
      await digitar(tester, 'setor-longitude', '-34');
      app.api.writeGate = Completer<void>();
      await tester.tap(find.text('Salvar'));
      await tester.pump();
      await app.container.read(authProvider.notifier).logout();
      await tester.pump();
      app.api.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(app.container.read(setoresProvider).asData?.value, isEmpty);
      expect(find.byType(DataTable), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('erro GET permite repetir e resumo legado desabilita edição', (
    tester,
  ) async {
    final api = ManagementApiFake()..nextStatus = 503;
    await mountSetores(tester, api: api);
    expect(find.text('Tentar novamente'), findsOneWidget);
    api.setores.single.removeWhere(
      (key, value) => {'latitude', 'longitude', 'raio_metros'}.contains(key),
    );
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Sede'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('editar-setor-setor-1')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('formulário e mapa funcionam com 320 pixels sem overflow', (
    tester,
  ) async {
    final app = await mountSetores(tester, size: const Size(320, 760));
    await abrirNovo(tester);
    await digitar(tester, 'setor-nome', 'Móvel');
    await digitar(tester, 'setor-latitude', '-8');
    await digitar(tester, 'setor-longitude', '-34');
    await digitar(tester, 'setor-raio', '200');
    await tester.ensureVisible(find.text('Salvar'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(app.api.requests.where((r) => r.method == 'POST'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
