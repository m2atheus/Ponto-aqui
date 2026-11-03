import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/views/relatorios/detalhe_ponto_dialog.dart';
import 'package:ponto_aqui_admin/views/relatorios/ponto_invalidacao_dialog.dart';
import 'package:ponto_aqui_admin/views/relatorios/relatorios_screen.dart';

import 'ponto_admin_test.dart' show PontoApi;
import 'w06_screens_test.dart' as w06;

class SelfieApi extends PontoApi {
  SelfieApi({super.role});
  String? fotoUrl = '/api/v1/admin/pontos/batida-1/selfie';
  Completer<void>? fotoGate;
  int fotoStatus = 200;

  @override
  Map<String, dynamic> report(String fid, int year, int month) {
    final dto = super.report(fid, year, month);
    for (final dia in dto['dias'] as List) {
      for (final ponto in dia['marcacoes'] as List) {
        ponto['foto_url'] = fotoUrl;
        ponto['foto_recebida_em'] = '2026-10-05T08:02:00-03:00';
        ponto['geofence'] = {
          'raio_metros': 100,
          'distancia_metros': 25.5,
          'politica': 'Bloquear',
        };
      }
    }
    return dto;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (!options.uri.path.endsWith('/selfie')) {
      return super.fetch(options, stream, cancel);
    }
    requests.add(options);
    await fotoGate?.future;
    return ResponseBody.fromBytes(
      fotoStatus == 200
          ? base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGNkaGhgYGBgYgADAAuqAQTkKlkHAAAAAElFTkSuQmCC',
            )
          : [],
      fotoStatus,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
      },
    );
  }
}

Future<void> verBotao(WidgetTester tester, Finder botao) async {
  await tester.scrollUntilVisible(
    botao,
    400,
    scrollable: find
        .descendant(
          of: find.byType(RelatoriosScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(botao);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('gestor aprova batida recusada pelo modal da selfie', (
    tester,
  ) async {
    final api = SelfieApi(role: UserRole.gestor)
      ..situacaoOriginal = 'PendenteAnalise';
    await w06.mount(
      tester,
      '/relatorios',
      api: api,
      role: UserRole.gestor,
      size: const Size(390, 844),
    );
    await w06.consultar(tester);
    final foto = find.byKey(const ValueKey('selfie-batida-batida-1'));
    await verBotao(tester, foto);
    await tester.tap(foto);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final imagem = find.descendant(
      of: find.byType(DetalhePontoDialog),
      matching: find.byType(Image),
    );
    for (var i = 0; i < 10 && imagem.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(imagem, findsOneWidget);
    await tester.runAsync(() async {
      await precacheImage(
        tester.widget<Image>(imagem).image,
        tester.element(imagem),
      );
    });
    await tester.pumpAndSettle();
    final aprovar = find.descendant(
      of: find.byType(DetalhePontoDialog),
      matching: find.byType(AprovarPontoButton),
    );
    await tester.ensureVisible(aprovar);
    await tester.pumpAndSettle();
    await tester.tap(aprovar);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('aprovacao-motivo')),
      'Foto e horário conferidos',
    );
    await tester.tap(find.byKey(const Key('aprovacao-confirmar')));
    await tester.pumpAndSettle();
    expect(find.text('Aprovada pelo Gestor/RH'), findsOneWidget);
    expect(aprovar, findsNothing);
    expect(
      api.requests.where((r) => r.uri.path.endsWith('/aprovar')),
      hasLength(1),
    );
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(
      api.requests.where((r) => r.uri.path.endsWith('/relatorios/espelho')),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });

  for (final url in [null, '', '  ']) {
    testWidgets('sem foto ($url) não renderiza ação, coluna ou placeholder', (
      tester,
    ) async {
      final api = SelfieApi()..fotoUrl = url;
      await w06.mount(tester, '/relatorios', api: api);
      await w06.consultar(tester);
      await verBotao(
        tester,
        find.byKey(const ValueKey('invalidar-batida-batida-1')),
      );
      expect(find.byTooltip('Visualizar selfie'), findsNothing);
      expect(
        api.requests.where((r) => r.uri.path.endsWith('/selfie')),
        isEmpty,
      );
    });
  }

  for (final role in [UserRole.rh, UserRole.gestor]) {
    testWidgets('$role abre imagem privada e invalida com motivo no modal', (
      tester,
    ) async {
      final api = SelfieApi(role: role)..fotoGate = Completer<void>();
      await w06.mount(
        tester,
        '/relatorios',
        api: api,
        role: role,
        size: role == UserRole.gestor
            ? const Size(390, 844)
            : const Size(1440, 900),
      );
      await w06.consultar(tester);
      final abrir = find.byKey(const ValueKey('selfie-batida-batida-1'));
      await verBotao(tester, abrir);
      await tester.tap(abrir);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DetalhePontoDialog), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final request = api.requests.last;
      expect(request.uri.path, '/api/v1/admin/pontos/batida-1/selfie');
      expect(request.headers['Authorization'], startsWith('Bearer '));
      // O decoder de imagens usa tarefas reais fora do relógio virtual do teste.
      api.fotoGate!.complete();
      final image = find.descendant(
        of: find.byType(DetalhePontoDialog),
        matching: find.byType(Image),
      );
      for (var frame = 0; frame < 10 && image.evaluate().isEmpty; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(image, findsOneWidget);
      await tester.runAsync(() async {
        await precacheImage(
          tester.widget<Image>(image).image,
          tester.element(image),
        );
      });
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('Distância: 25.5 m'), findsOneWidget);
      expect(find.text('Dentro do perímetro.'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(DetalhePontoDialog),
          matching: find.byType(InvalidarPontoButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('invalidacao-confirmar')));
      await tester.pumpAndSettle();
      expect(find.text('Informe o motivo da invalidação.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('invalidacao-motivo')),
        'A foto não é do funcionário',
      );
      await tester.tap(find.byKey(const Key('invalidacao-confirmar')));
      await tester.pumpAndSettle();
      expect(find.text('Invalidado'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Fechar'));
      await tester.pumpAndSettle();
      await verBotao(
        tester,
        find.byKey(const ValueKey('invalidar-batida-batida-1')),
      );
      expect(find.text('Invalidado pelo Gestor/RH'), findsOneWidget);
      expect(api.ajustes.single['motivo_texto'], 'A foto não é do funcionário');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'foto indisponível permite tentar novamente sem invalidar automaticamente',
    (tester) async {
      final api = SelfieApi()..fotoStatus = 404;
      await w06.mount(
        tester,
        '/relatorios',
        api: api,
        size: const Size(390, 844),
      );
      await w06.consultar(tester);
      final abrir = find.byKey(const ValueKey('selfie-batida-batida-1'));
      await verBotao(tester, abrir);
      await tester.tap(abrir);
      await tester.pumpAndSettle();
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(api.ajustes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(TextButton, 'Fechar'));
      await tester.pumpAndSettle();
    },
  );
}
