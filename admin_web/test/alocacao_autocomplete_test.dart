import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alocacoes_screen_test.dart' show mountAlocacoes;
import 'support/management_api_fake.dart';

void main() {
  ManagementApiFake manyRows() {
    final api = ManagementApiFake()..alocacoes.clear();
    api.funcionarios.clear();
    api.setores.clear();
    for (var i = 0; i < 40; i++) {
      final number = i.toString().padLeft(2, '0');
      api.funcionarios.add({
        ...funcionarioJson(),
        'id': 'pessoa-$i',
        'nome': 'Pessoa $number',
        'matricula': 'TST-$number',
      });
      api.setores.add({
        ...setorJson(),
        'id': 'setor-$i',
        'nome': 'Filial $number',
      });
    }
    return api;
  }

  testWidgets(
    'não carrega cadastros inteiros; foco busca 20 e digitação espera 500 ms nos dois campos',
    (tester) async {
      final api = manyRows();
      await mountAlocacoes(tester, api: api);
      expect(
        api.requests.where(
          (r) =>
              r.uri.path.endsWith('/funcionarios') ||
              r.uri.path.endsWith('/setores'),
        ),
        isEmpty,
      );
      await tester.tap(find.byKey(const Key('nova-alocacao')));
      await tester.pumpAndSettle();
      expect(api.requests.where((r) => r.uri.path.endsWith('/busca')), isEmpty);

      for (final type in ['funcionario', 'setor']) {
        final input = find.byKey(Key('alocacao-$type-input'));
        await tester.ensureVisible(input);
        await tester.tap(input);
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        final request = api.requests.last;
        expect(request.queryParameters['q'], '');
        if (type == 'funcionario') {
          expect(request.queryParameters['ativo'], 'true');
        }
        final list = tester.widget<ListView>(
          find.descendant(
            of: find.byKey(Key('alocacao-$type-input-sugestoes')),
            matching: find.byType(ListView),
          ),
        );
        expect(
          (list.childrenDelegate as SliverChildListDelegate).children,
          hasLength(20),
        );
        api.requests.clear();
        final q = type == 'funcionario' ? 'Pessoa 39' : 'Filial 39';
        await tester.enterText(input, q);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 499));
        expect(api.requests, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pumpAndSettle();
        expect(api.requests, hasLength(1));
        expect(api.requests.single.queryParameters['q'], q);
        final label = type == 'funcionario'
            ? 'Pessoa 39 — TST-39'
            : 'Filial 39';
        await tester.tap(find.widgetWithText(ListTile, label));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).controller!.text, label);
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(1440, 900),
    const Size(390, 844),
    const Size(1440, 480),
  ]) {
    for (final field in ['funcionario', 'setor']) {
      testWidgets('overlay de $field ancorado e clicável em $size', (
        tester,
      ) async {
        final api = manyRows();
        await mountAlocacoes(tester, api: api, size: size);
        await tester.tap(find.byKey(const Key('nova-alocacao')));
        await tester.pumpAndSettle();
        final input = find.byKey(Key('alocacao-$field-input'));
        await tester.ensureVisible(input);
        await tester.tap(input);
        await tester.pumpAndSettle();
        final edit = find.descendant(
          of: input,
          matching: find.byType(EditableText),
        );
        final box = InputDecorator.containerOf(tester.element(edit))!;
        final border = box.localToGlobal(Offset.zero) & box.size;
        final popup = tester.getRect(
          find.byKey(Key('alocacao-$field-input-sugestoes')),
        );
        expect(popup.top, closeTo(border.bottom, 1));
        expect(popup.left, closeTo(border.left, 1));
        expect(popup.width, closeTo(border.width, 1));
        expect(popup.height, greaterThan(0));
        if (field == 'setor') {
          expect(
            popup.overlaps(
              tester.getRect(find.byKey(const Key('alocacao-data-inicio'))),
            ),
            isTrue,
          );
        }
        final label = field == 'funcionario'
            ? 'Pessoa 00 — TST-00'
            : 'Filial 00';
        await tester.tap(find.widgetWithText(ListTile, label));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).controller!.text, label);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
