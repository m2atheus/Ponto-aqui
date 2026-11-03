import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/repositories/ponto_admin_repository.dart';
import 'package:ponto_aqui_admin/repositories/repository_failure.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/views/relatorios/detalhe_ponto_dialog.dart';
import 'package:ponto_aqui_admin/views/relatorios/ponto_invalidacao_dialog.dart';

import 'ponto_admin_test.dart' show PontoApi;
import 'selfie_ponto_test.dart' show SelfieApi, verBotao;
import 'support/auth_fakes.dart';
import 'w06_screens_test.dart' as w06;

void main() {
  test(
    'reaprovação envia referência da invalidação, JWT e preserva prefixo',
    () async {
      final api = PontoApi()..invalidarInicialmente();
      final storage = MemoryTokenStorage()
        ..session = sessionFor(UserRole.rh).toJson();
      final dio = createDioClient(
        baseUrl: 'https://api.example.com/painel/api/web/',
        tokenStorage: storage,
      )..httpClientAdapter = api;
      addTearDown(() => dio.close(force: true));
      final repo = PontoAdminRepository(dio, empresaId: 'empresa-1');
      await repo.reaprovarMarcacao(
        registroId: 'batida-1',
        invalidacaoId: 'ajuste-1',
        motivoTexto: '  Identidade conferida  ',
      );
      expect(
        api.requests.single.uri.path,
        '/painel/api/v1/admin/pontos/batida-1/reaprovar',
      );
      expect(api.requests.single.data, {
        'motivo_texto': 'Identidade conferida',
        'invalidacao_id': 'ajuste-1',
      });
      expect(
        api.requests.single.headers['Authorization'],
        startsWith('Bearer '),
      );
      api.nextStatus = 409;
      api.nextBody = {
        'erro': {
          'codigo': 'DECISAO_DESATUALIZADA',
          'mensagem':
              'A análise desta marcação mudou. Consulte o espelho novamente.',
        },
      };
      await expectLater(
        repo.reaprovarMarcacao(
          registroId: 'batida-1',
          invalidacaoId: 'ajuste-1',
          motivoTexto: 'Reenvio',
        ),
        throwsA(
          isA<RepositoryFailure>().having(
            (e) => e.message,
            'mensagem',
            contains('Consulte o espelho novamente'),
          ),
        ),
      );
    },
  );

  testWidgets(
    'RH reaprova pela tabela com motivo e preserva invalidação no histórico',
    (tester) async {
      final api = PontoApi()..invalidarInicialmente();
      final anterior = Map<String, dynamic>.of(api.ajustes.first);
      await w06.mount(tester, '/relatorios', api: api);
      await w06.consultar(tester);
      final botao = find.byKey(const ValueKey('reaprovar-batida-batida-1'));
      await verBotao(tester, botao);
      await tester.tap(botao);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Foto inicialmente não reconhecida'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('reaprovacao-confirmar')));
      await tester.pumpAndSettle();
      expect(find.text('Informe o motivo da reaprovação.'), findsOneWidget);
      expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.enterText(
        find.byKey(const Key('reaprovacao-motivo')),
        'Identidade conferida com a equipe',
      );
      api.writeGate = Completer<void>();
      await tester.tap(find.byKey(const Key('reaprovacao-confirmar')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('reaprovacao-confirmar')),
            )
            .onPressed,
        isNull,
      );
      api.writeGate!.complete();
      await tester.pumpAndSettle();
      await verBotao(
        tester,
        find.byKey(const ValueKey('invalidar-batida-batida-1')),
      );
      expect(find.text('Reaprovada pelo RH'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reaprovar-batida-batida-1')),
        findsNothing,
      );
      expect(api.ajustes.first, anterior);
      expect(api.ajustes, hasLength(2));
      final tooltip = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.text('Reaprovada pelo RH'),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(tooltip.message, contains('Invalidada pelo Gestor/RH'));
      expect(tooltip.message, contains('Identidade conferida com a equipe'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Gestor vê invalidação mas não recebe ação exclusiva de reaprovação do RH',
    (tester) async {
      final api = PontoApi(role: UserRole.gestor)..invalidarInicialmente();
      await w06.mount(tester, '/relatorios', api: api, role: UserRole.gestor);
      await w06.consultar(tester);
      await verBotao(
        tester,
        find.byKey(const ValueKey('invalidar-batida-batida-1')),
      );
      expect(find.text('Invalidado pelo Gestor/RH'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reaprovar-batida-batida-1')),
        findsNothing,
      );
      expect(api.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );

  testWidgets('RH reaprova pelo modal da selfie em tela pequena', (
    tester,
  ) async {
    final api = SelfieApi()..invalidarInicialmente();
    await w06.mount(
      tester,
      '/relatorios',
      api: api,
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
    await tester.runAsync(() async {
      await precacheImage(
        tester.widget<Image>(imagem).image,
        tester.element(imagem),
      );
    });
    await tester.pumpAndSettle();
    final reaprovar = find.descendant(
      of: find.byType(DetalhePontoDialog),
      matching: find.byType(AprovarPontoButton),
    );
    expect(tester.widget<AprovarPontoButton>(reaprovar).reaprovar, isTrue);
    await tester.ensureVisible(reaprovar);
    await tester.pumpAndSettle();
    await tester.tap(reaprovar);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reaprovacao-motivo')),
      'Conferência concluída pelo RH',
    );
    await tester.tap(find.byKey(const Key('reaprovacao-confirmar')));
    await tester.pumpAndSettle();
    expect(find.text('Reaprovada pelo RH'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Fechar'));
    await tester.pumpAndSettle();
    expect(
      api.requests.where((r) => r.uri.path.endsWith('/relatorios/espelho')),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });
}
