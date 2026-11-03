import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/providers/funcionarios_provider.dart';

import 'funcionarios_screen_test.dart' show mountFuncionarios;
import 'support/management_api_fake.dart';

ManagementApiFake dadosPesquisa() {
  final api = ManagementApiFake();
  api.funcionarios[0].addAll({
    'nome': 'Matheus Almeida',
    'matricula': 'TST-0001',
  });
  api.funcionarios.add({
    ...funcionarioJson(),
    'id': 'funcionario-2',
    'nome': 'João Santos',
    'matricula': 'TST-0002',
    'ativo': false,
  });
  return api;
}

void main() {
  testWidgets(
    'nome ou matrícula sem distinguir caixa; tabela espera 300ms e não consulta rede',
    (tester) async {
      final api = dadosPesquisa();
      await mountFuncionarios(tester, api: api);
      api.requests.clear();
      final campo = find.byKey(const Key('funcionarios-pesquisa'));
      expect(
        find.byKey(const Key('funcionarios-limpar-pesquisa')),
        findsNothing,
      );
      await tester.enterText(campo, ' MATH ');
      await tester.pump();
      expect(
        find.byKey(const Key('funcionarios-limpar-pesquisa')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.text('João Santos'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Matheus Almeida'), findsOneWidget);
      expect(find.text('João Santos'), findsNothing);
      await tester.enterText(campo, 'tst-0002');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Matheus Almeida'), findsNothing);
      expect(find.text('João Santos'), findsOneWidget);
      expect(
        find.byKey(const Key('reativar-funcionario-funcionario-2')),
        findsOneWidget,
      );
      expect(api.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'estado vazio e limpar restaura imediatamente a lista e cancela busca pendente',
    (tester) async {
      await mountFuncionarios(tester, api: dadosPesquisa());
      final campo = find.byKey(const Key('funcionarios-pesquisa'));
      await tester.enterText(campo, 'Inexistente');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Nenhum funcionário encontrado para o termo pesquisado.'),
        findsOneWidget,
      );
      expect(find.byType(DataTable), findsNothing);
      await tester.enterText(campo, 'Math');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('funcionarios-limpar-pesquisa')));
      await tester.pump();
      expect(find.text('Matheus Almeida'), findsOneWidget);
      expect(find.text('João Santos'), findsOneWidget);
      expect(
        find.byKey(const Key('funcionarios-limpar-pesquisa')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('João Santos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mantém filtro ao recarregar dados e cancela timer quando sai da tela em 320px',
    (tester) async {
      final api = dadosPesquisa();
      final app = await mountFuncionarios(
        tester,
        api: api,
        size: const Size(320, 760),
      );
      final campo = find.byKey(const Key('funcionarios-pesquisa'));
      await tester.ensureVisible(campo);
      await tester.enterText(campo, 'Math');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Matheus Almeida'), findsOneWidget);
      expect(find.text('João Santos'), findsNothing);
      api.funcionarios.add({
        ...funcionarioJson(),
        'id': 'funcionario-3',
        'nome': 'Matheus Santos',
        'matricula': 'TST-0003',
      });
      app.container.invalidate(funcionariosProvider);
      await tester.pumpAndSettle();
      expect(find.text('Matheus Santos'), findsOneWidget);
      expect(find.text('João Santos'), findsNothing);
      expect(tester.getSize(campo).width, lessThanOrEqualTo(320));
      await tester.enterText(campo, 'João');
      app.router.go('/dashboard');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
