import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/w06_api_fake.dart';
import 'w06_screens_test.dart' show mount, escolher, data;

Future<void> salvarEscala(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Salvar');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'escala persiste no servidor, edita e remove somente com confirmação',
    (tester) async {
      final api = W06ApiFake();
      await mount(tester, '/escalas', api: api);
      await tester.tap(find.text('Nova Escala'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('escala-nome')), 'Noturna');
      await escolher(tester, const Key('escala-modelo'), '12x36');
      await data(tester, 'escala-referencia', '01/10/2026');
      await tester.enterText(find.byKey(const Key('escala-entrada')), '19:00');
      await tester.enterText(find.byKey(const Key('escala-saida')), '07:00');
      await salvarEscala(tester);
      expect(api.escalas, hasLength(2));
      expect(api.escalas.last['modelo'], '12x36');
      expect(api.requests.any((r) => r.method == 'POST'), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(tester, '/escalas', api: api);
      expect(find.text('Noturna'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('editar-escala-escala-2')),
      );
      await tester.tap(find.byKey(const Key('editar-escala-escala-2')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('escala-nome')),
        'Noturna revisada',
      );
      await salvarEscala(tester);
      expect(api.escalas.last['nome'], 'Noturna revisada');
      final button = find.byKey(const Key('remover-escala-escala-2'));
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
      expect(api.escalas, hasLength(1));
      expect(find.text('Noturna revisada'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('escala com histórico mantém linha ao receber HTTP 409', (
    tester,
  ) async {
    final api = W06ApiFake();
    await mount(tester, '/escalas', api: api);
    await tester.ensureVisible(
      find.byKey(const Key('remover-escala-escala-1')),
    );
    await tester.tap(find.byKey(const Key('remover-escala-escala-1')));
    await tester.pumpAndSettle();
    api.nextStatus = 409;
    api.nextBody = {
      'erro': {'mensagem': 'Esta escala possui histórico. Desative-a.'},
    };
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    expect(
      find.text('Esta escala possui histórico. Desative-a.'),
      findsOneWidget,
    );
    expect(api.escalas, hasLength(1));
    expect(find.byType(DataTable), findsOneWidget);
  });
}
