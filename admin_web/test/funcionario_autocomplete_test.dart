import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/management_api_fake.dart';
import 'support/w06_api_fake.dart';
import 'w06_screens_test.dart' as reports;

void main() {
  final input = find.byKey(const Key('funcionario-busca-input'));

  testWidgets(
    'relatórios não pré-carrega equipe; debounce dispara somente após 500 ms',
    (tester) async {
      final api = W06ApiFake();
      await reports.mount(tester, '/relatorios', api: api);
      expect(
        api.requests.where(
          (r) => [
            '/equipe',
            '/feriados',
            '/afastamentos',
            '/funcionarios',
          ].any(r.uri.path.endsWith),
        ),
        isEmpty,
      );
      await tester.tap(input);
      await tester.pumpAndSettle();
      api.requests.clear();
      await tester.enterText(input, 'An');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(input, 'Ana');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(api.requests.where((r) => r.uri.path.endsWith('/busca')), isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      final search = api.requests
          .where((r) => r.uri.path.endsWith('/busca'))
          .single;
      expect(search.queryParameters, {'q': 'Ana'});
      expect(search.headers['Authorization'], startsWith('Bearer '));
      expect(find.text('Ana Silva · 001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focar campo vazio carrega a lista imediatamente e permite selecionar sem digitar',
    (tester) async {
      final api = W06ApiFake();
      await reports.mount(tester, '/relatorios', api: api);
      expect(api.requests.where((r) => r.uri.path.endsWith('/busca')), isEmpty);
      await tester.tap(input);
      // Monta o overlay em frames reais, sem avançar o debounce de 500 ms.
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final request = api.requests
          .where((r) => r.uri.path.endsWith('/busca'))
          .single;
      expect(request.queryParameters, {'q': ''});
      await tester.pumpAndSettle();
      expect(find.text('Ana Silva · 001'), findsOneWidget);
      expect(find.text('Bruno Santos · 002'), findsOneWidget);
      await tester.tap(find.text('Ana Silva · 001'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'Ana Silva · 001',
      );
      await tester.tap(find.byTooltip('Limpar funcionário'));
      await tester.pumpAndSettle();
      expect(api.requests.last.queryParameters, {'q': ''});
      expect(find.text('Bruno Santos · 002'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1440, 900), const Size(390, 900)]) {
    for (final invalid in [false, true]) {
      testWidgets(
        'sugestões encostam na borda do campo: $size, erro=$invalid',
        (tester) async {
          await reports.mount(tester, '/relatorios', size: size);
          if (invalid) {
            await tester.ensureVisible(find.byKey(const Key('gerar-espelho')));
            await tester.tap(find.byKey(const Key('gerar-espelho')));
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(input);
          await tester.tap(input);
          await tester.pumpAndSettle();
          final edit = find.descendant(
            of: input,
            matching: find.byType(EditableText),
          );
          final container = InputDecorator.containerOf(tester.element(edit))!;
          final border = container.localToGlobal(Offset.zero) & container.size;
          final popup = tester.getRect(
            find.byKey(const Key('funcionario-sugestoes')),
          );
          expect(popup.top, closeTo(border.bottom, 1));
          expect(popup.left, closeTo(border.left, 1));
          expect(popup.width, closeTo(border.width, 1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final width in [1440.0, 1800.0]) {
    testWidgets('filtros alinhados com ajuda e validação: largura $width', (
      tester,
    ) async {
      await reports.mount(tester, '/relatorios', size: Size(width, 900));

      Rect fieldBorder(Finder finder) {
        final text = find.descendant(of: finder, matching: find.byType(Text));
        final container = InputDecorator.containerOf(
          tester.element(text.first),
        )!;
        return container.localToGlobal(Offset.zero) & container.size;
      }

      void expectAligned() {
        final employee = fieldBorder(input);
        for (final key in ['relatorio-mes', 'relatorio-ano']) {
          final other = fieldBorder(find.byKey(Key(key)));
          expect(other.top, closeTo(employee.top, 1), reason: '$key topo');
          expect(
            other.bottom,
            closeTo(employee.bottom, 1),
            reason: '$key base',
          );
        }
        final button = tester.getRect(find.byKey(const Key('gerar-espelho')));
        expect(button.center.dy, closeTo(employee.center.dy, 1));
        expect(tester.takeException(), isNull);
      }

      expectAligned();
      await tester.enterText(find.byKey(const Key('relatorio-ano')), '0');
      await tester.tap(find.byKey(const Key('gerar-espelho')));
      await tester.pumpAndSettle();
      expect(find.text('Selecione um funcionário da busca.'), findsOneWidget);
      expect(find.text('1900 a 2100.'), findsOneWidget);
      expectAligned();
    });
  }

  testWidgets(
    'um caractere filtra com debounce e limpar recarrega a lista sem atraso',
    (tester) async {
      final api = W06ApiFake();
      await reports.mount(tester, '/relatorios', api: api);
      await tester.tap(input);
      await tester.pumpAndSettle();
      api.requests.clear();
      await tester.enterText(input, 'B');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(api.requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(api.requests.single.queryParameters, {'q': 'B'});
      expect(find.text('Bruno Santos · 002'), findsOneWidget);
      expect(find.text('Ana Silva · 001'), findsNothing);
      await tester.enterText(input, '');
      await tester.pump();
      await tester.pump();
      expect(api.requests.last.queryParameters, {'q': ''});
      await tester.pumpAndSettle();
      expect(find.text('Ana Silva · 001'), findsOneWidget);
    },
  );

  testWidgets('mostra carregamento dentro do campo e resposta vazia', (
    tester,
  ) async {
    final api = W06ApiFake();
    await reports.mount(tester, '/relatorios', api: api);
    await tester.tap(input);
    await tester.pumpAndSettle();
    final response = Completer<ResponseBody>();
    api.handler = (_) => response.future;
    await tester.enterText(input, 'zzz');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
      find.descendant(
        of: input,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    response.complete(jsonResponse({'funcionarios': []}));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum funcionário encontrado.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('resposta antiga não substitui a última busca', (tester) async {
    final api = W06ApiFake();
    await reports.mount(tester, '/relatorios', api: api);
    final old = Completer<ResponseBody>();
    final latest = Completer<ResponseBody>();
    api.handler = (request) =>
        request.queryParameters['q'] == 'Ana' ? old.future : latest.future;
    await tester.enterText(input, 'Ana');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.enterText(input, 'Bruno');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    latest.complete(
      jsonResponse({
        'funcionarios': [api.funcionarios.last],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bruno Santos · 002'), findsOneWidget);
    old.complete(
      jsonResponse({
        'funcionarios': [api.funcionarios.first],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bruno Santos · 002'), findsOneWidget);
    expect(find.text('Ana Silva · 001'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('erro de rede é exibido e uma nova busca pode recuperar', (
    tester,
  ) async {
    final api = W06ApiFake();
    await reports.mount(tester, '/relatorios', api: api);
    await tester.tap(input);
    await tester.pumpAndSettle();
    api.nextStatus = 503;
    api.nextBody = {
      'erro': {'mensagem': 'Indisponível'},
    };
    await tester.enterText(input, 'Ana');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      find.text('Não foi possível concluir a operação. Tente novamente.'),
      findsOneWidget,
    );
    await tester.enterText(input, 'Bruno');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Bruno Santos · 002'), findsOneWidget);
  });

  testWidgets('após a API voltar, botão de repetir recarrega o campo vazio', (
    tester,
  ) async {
    final api = W06ApiFake();
    await reports.mount(tester, '/relatorios', api: api);
    var offline = true;
    api.handler = (request) {
      if (offline) {
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        );
      }
      return jsonResponse({'funcionarios': api.funcionarios.take(20).toList()});
    };
    await tester.tap(input);
    await tester.pumpAndSettle();
    expect(
      find.text('Não foi possível conectar à API. Confira sua conexão.'),
      findsOneWidget,
    );
    offline = false;
    await tester.tap(find.byTooltip('Tentar buscar funcionários novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Silva · 001'), findsOneWidget);
    expect(
      find.text('Não foi possível conectar à API. Confira sua conexão.'),
      findsNothing,
    );
    expect(api.requests.last.queryParameters, {'q': ''});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editar o texto invalida a seleção anterior para consultar espelho',
    (tester) async {
      final api = W06ApiFake();
      await reports.mount(tester, '/relatorios', api: api);
      await reports.consultar(tester);
      final before = api.requests
          .where((r) => r.uri.path.endsWith('/relatorios/espelho'))
          .length;
      await tester.enterText(input, 'Br');
      await tester.ensureVisible(find.byKey(const Key('gerar-espelho')));
      await tester.tap(find.byKey(const Key('gerar-espelho')));
      await tester.pumpAndSettle();
      expect(find.text('Selecione um funcionário da busca.'), findsOneWidget);
      expect(
        api.requests
            .where((r) => r.uri.path.endsWith('/relatorios/espelho'))
            .length,
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
