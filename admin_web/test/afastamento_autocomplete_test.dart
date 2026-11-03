import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/management_api_fake.dart' show funcionarioJson;
import 'support/w06_api_fake.dart';
import 'w06_screens_test.dart' as w06;

Future<void> abrirNovo(WidgetTester tester, W06ApiFake api) async {
  await w06.mount(tester, '/justificativas', api: api);
  await tester.tap(find.text('Afastamentos'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('novo-afastamento')));
  await tester.pumpAndSettle();
}

void main() {
  final input = find.byKey(const Key('funcionario-busca-input'));

  testWidgets(
    'afastamento lista até 20 ativos no foco e busca nome/matrícula com debounce',
    (tester) async {
      final api = W06ApiFake();
      for (var i = 1; i <= 40; i++) {
        api.funcionarios.add({
          ...funcionarioJson(),
          'id': 'pessoa-$i',
          'nome': 'Pessoa Teste $i',
          'matricula': 'TST-2026-${i.toString().padLeft(4, '0')}',
        });
      }
      api.funcionarios.add({
        ...funcionarioJson(),
        'id': 'inativo',
        'nome': 'Inativo',
        'matricula': 'INATIVO',
        'ativo': false,
      });
      await abrirNovo(tester, api);
      expect(api.requests.where((r) => r.uri.path.endsWith('/busca')), isEmpty);
      await tester.tap(input);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final inicial = api.requests.singleWhere(
        (r) => r.uri.path.endsWith('/busca'),
      );
      expect(inicial.queryParameters, {'q': '', 'ativo': 'true'});
      expect(inicial.headers['Authorization'], startsWith('Bearer '));
      await tester.pumpAndSettle();
      final overlay = find.byKey(const Key('funcionario-sugestoes'));
      expect(
        tester.getRect(overlay).top,
        closeTo(tester.getRect(input).bottom, 1),
      );
      expect(
        tester.getSize(overlay).width,
        closeTo(tester.getSize(input).width, 1),
      );
      expect(
        find
            .descendant(of: overlay, matching: find.byType(ListTile))
            .evaluate()
            .length,
        lessThanOrEqualTo(20),
      );
      expect(find.text('Inativo · INATIVO'), findsNothing);
      api.requests.clear();
      await tester.enterText(input, 'T');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(input, 'TST-2026-0040');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(api.requests.where((r) => r.uri.path.endsWith('/busca')), isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      final busca = api.requests.singleWhere(
        (r) => r.uri.path.endsWith('/busca'),
      );
      expect(busca.queryParameters, {'q': 'TST-2026-0040', 'ativo': 'true'});
      await tester.tap(find.text('Pessoa Teste 40 · TST-2026-0040'));
      await tester.pumpAndSettle();
      await w06.data(tester, 'w06-inicio', '15/10/2026');
      await w06.data(tester, 'w06-fim', '16/10/2026');
      await w06.salvar(tester);
      final post = api.requests.singleWhere((r) => r.method == 'POST');
      expect(post.data['funcionario_id'], 'pessoa-40');
      expect(api.afastamentos.last['funcionario_id'], 'pessoa-40');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'texto livre não substitui seleção válida e busca vazia não trava formulário',
    (tester) async {
      final api = W06ApiFake();
      await abrirNovo(tester, api);
      await tester.tap(input);
      await tester.pumpAndSettle();
      await tester.enterText(input, 'NaoExiste');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum funcionário encontrado.'), findsOneWidget);
      await w06.data(tester, 'w06-inicio', '15/10/2026');
      await w06.data(tester, 'w06-fim', '16/10/2026');
      await w06.salvar(tester);
      expect(find.text('Selecione um funcionário da busca.'), findsOneWidget);
      expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edição preserva funcionário inativo e não dispara busca de catálogo',
    (tester) async {
      final api = W06ApiFake();
      api.funcionarios[1]['ativo'] = false;
      await w06.mount(tester, '/justificativas', api: api);
      await tester.tap(find.text('Afastamentos'));
      await tester.pumpAndSettle();
      final editar = find.byKey(const Key('editar-afastamento-afastamento-1'));
      await tester.ensureVisible(editar);
      await tester.tap(editar);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Bruno Santos · 002',
      );
      expect(tester.widget<TextField>(input).enabled, isFalse);
      expect(api.requests.where((r) => r.uri.path.endsWith('/busca')), isEmpty);
      await w06.data(tester, 'w06-fim', '08/10/2026');
      await w06.salvar(tester);
      final put = api.requests.singleWhere((r) => r.method == 'PUT');
      expect((put.data as Map).containsKey('funcionario_id'), isFalse);
      expect(api.afastamentos.single['funcionario_id'], 'funcionario-2');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
