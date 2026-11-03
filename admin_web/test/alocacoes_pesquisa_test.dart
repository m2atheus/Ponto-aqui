import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alocacoes_screen_test.dart' show mountAlocacoes;
import 'support/management_api_fake.dart';

ManagementApiFake dados() {
  final api = ManagementApiFake();
  api.funcionarios[0]['nome'] = 'Matheus Almeida';
  api.funcionarios[0]['matricula'] = 'TST-2026-0001';
  api.funcionarios.add({
    ...funcionarioJson(),
    'id': 'funcionario-2',
    'nome': 'João Santos',
    'matricula': 'TST-2026-0002',
  });
  api.alocacoes.add({
    ...alocacaoJson(),
    'id': 'alocacao-2',
    'funcionario_id': 'funcionario-2',
  });
  return api;
}

void main() {
  testWidgets(
    'busca nome e matrícula sem distinguir caixa, com debounce e sem rede',
    (tester) async {
      final api = dados();
      await mountAlocacoes(tester, api: api);
      api.requests.clear();
      final campo = find.byKey(const Key('alocacoes-pesquisa'));
      expect(find.byKey(const Key('alocacoes-limpar-pesquisa')), findsNothing);
      await tester.enterText(campo, 'MATH');
      await tester.pump();
      expect(
        find.byKey(const Key('alocacoes-limpar-pesquisa')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.text('João Santos'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Matheus Almeida'), findsOneWidget);
      expect(find.text('João Santos'), findsNothing);
      await tester.enterText(campo, 'tst-2026-0002');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Matheus Almeida'), findsNothing);
      expect(find.text('João Santos'), findsOneWidget);
      expect(api.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nenhum resultado e limpar restauram a lista, cancelando debounce pendente',
    (tester) async {
      final api = dados();
      await mountAlocacoes(tester, api: api);
      final campo = find.byKey(const Key('alocacoes-pesquisa'));
      await tester.enterText(campo, 'Não existe');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Nenhuma alocação encontrada para este termo.'),
        findsOneWidget,
      );
      expect(find.byType(DataTable), findsNothing);
      await tester.enterText(campo, 'Math');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('alocacoes-limpar-pesquisa')));
      await tester.pump();
      expect(find.text('Matheus Almeida'), findsOneWidget);
      expect(find.text('João Santos'), findsOneWidget);
      expect(find.byKey(const Key('alocacoes-limpar-pesquisa')), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('João Santos'), findsOneWidget);
      expect(tester.widget<TextField>(campo).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'campo cabe em 320px e timer pendente é cancelado ao sair da tela',
    (tester) async {
      final app = await mountAlocacoes(
        tester,
        api: dados(),
        size: const Size(320, 760),
      );
      final campo = find.byKey(const Key('alocacoes-pesquisa'));
      await tester.ensureVisible(campo);
      await tester.enterText(campo, 'João');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('João Santos'), findsOneWidget);
      expect(find.text('Matheus Almeida'), findsNothing);
      expect(tester.getSize(campo).width, lessThanOrEqualTo(320));
      await tester.enterText(campo, 'Math');
      app.router.go('/dashboard');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
