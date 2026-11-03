import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/utils/civil_date.dart';

import 'alocacoes_screen_test.dart' show mountAlocacoes;
import 'support/management_api_fake.dart';

class TransferenciaApiFake extends ManagementApiFake {
  TransferenciaApiFake() {
    setores.add({...setorJson(), 'id': 'setor-2', 'nome': 'Filial'});
  }
  bool conflito = false;
  Completer<void>? transferenciaGate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path.endsWith('/alocacoes/opcoes-mudanca')) {
      requests.add(options);
      final rows = options.queryParameters['tipo'] == 'setor'
          ? setores
          : escalas;
      final q = options.queryParameters['q'].toString().toLowerCase();
      return jsonResponse({
        'opcoes': rows
            .where((r) => r['nome'].toString().toLowerCase().contains(q))
            .take(20)
            .toList(),
      });
    }
    if (options.uri.path.endsWith('/mudar-alocacao')) {
      requests.add(options);
      await transferenciaGate?.future;
      if (conflito) {
        return jsonResponse({
          'erro': {
            'codigo': 'CONFLITO_ESCALA',
            'mensagem': 'Conflito com escala noturna.',
          },
        }, 409);
      }
      final body = options.data as Map;
      final old = alocacoes.firstWhere((a) => a['id'] == body['alocacao_id']);
      old['data_fim'] = body['data_encerramento'];
      final nova = {
        ...old,
        'id': 'alocacao-2',
        'setor_id': body['novo_setor_id'],
        'escala_id': body['nova_escala_id'],
        'data_inicio': body['data_transicao'],
        'data_fim': null,
      };
      alocacoes.add(nova);
      return jsonResponse({'alocacao_anterior': old, 'alocacao': nova}, 201);
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

Future<TransferenciaApiFake> abrir(
  WidgetTester tester, {
  TransferenciaApiFake? api,
  Size size = const Size(1440, 900),
}) async {
  final fake = api ?? TransferenciaApiFake();
  await mountAlocacoes(tester, api: fake, size: size);
  final botao = find.byKey(const Key('transferir-alocacao-alocacao-1'));
  await tester.ensureVisible(botao);
  await tester.pumpAndSettle();
  await tester.tap(botao);
  await tester.pumpAndSettle();
  return fake;
}

Future<void> preencher(WidgetTester tester) async {
  for (final entry in {'setor': 'Filial', 'escala': 'Comercial'}.entries) {
    final campo = find.byKey(Key('transferencia-${entry.key}'));
    await tester.ensureVisible(campo);
    await tester.pumpAndSettle();
    await tester.tap(campo);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, entry.value));
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.byKey(const Key('transferencia-fim')),
    '02/11/2026',
  );
  final inicio = find.byKey(const Key('transferencia-inicio'));
  await tester.ensureVisible(inicio);
  await tester.enterText(inicio, '10/11/2026');
  await tester.ensureVisible(find.byKey(const Key('transferencia-confirmar')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'contexto pré-carregado, datas sugeridas e alterações manuais respeitadas',
    (tester) async {
      await abrir(tester);
      expect(find.text('Setor: Sede'), findsOneWidget);
      expect(find.text('Escala: Comercial'), findsOneWidget);
      final fim = find.byKey(const Key('transferencia-fim'));
      final inicio = find.byKey(const Key('transferencia-inicio'));
      final hoje = DateTime.now();
      expect(
        tester.widget<TextFormField>(fim).controller!.text,
        civilDateDisplay(civilDateIso(hoje)),
      );
      expect(
        tester.widget<TextFormField>(inicio).controller!.text,
        civilDateDisplay(
          civilDateIso(DateTime.utc(hoje.year, hoje.month, hoje.day + 1)),
        ),
      );
      await tester.enterText(fim, '31/12/2026');
      expect(
        tester.widget<TextFormField>(inicio).controller!.text,
        '01/01/2027',
      );
      await tester.ensureVisible(inicio);
      await tester.enterText(inicio, '15/01/2027');
      await tester.ensureVisible(fim);
      await tester.enterText(fim, '30/12/2026');
      expect(
        tester.widget<TextFormField>(inicio).controller!.text,
        '15/01/2027',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uma requisição transfere, preserva vínculo antigo e aceita intervalo entre datas',
    (tester) async {
      final api = await abrir(tester);
      final original = Map<String, dynamic>.of(api.alocacao);
      await preencher(tester);
      await tester.tap(find.byKey(const Key('transferencia-confirmar')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final post = api.requests.singleWhere((r) => r.method == 'POST');
      expect(
        post.uri.path,
        '/api/web/funcionarios/funcionario-1/mudar-alocacao',
      );
      expect(post.data, {
        'alocacao_id': 'alocacao-1',
        'novo_setor_id': 'setor-2',
        'nova_escala_id': 'escala-1',
        'data_encerramento': '2026-11-02',
        'data_transicao': '2026-11-10',
      });
      expect(post.headers['Authorization'], startsWith('Bearer '));
      expect(
        api.requests.where((r) => r.method == 'PUT' || r.method == 'DELETE'),
        isEmpty,
      );
      expect(api.alocacoes, hasLength(2));
      expect(api.alocacoes.first, {...original, 'data_fim': '2026-11-02'});
      expect(api.alocacoes.last['data_fim'], isNull);
      expect(
        find.text('Funcionário transferido. Histórico preservado.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'falha mantém formulário e histórico; envio duplicado é bloqueado',
    (tester) async {
      final api = await abrir(
        tester,
        api: TransferenciaApiFake()..conflito = true,
      );
      await preencher(tester);
      api.transferenciaGate = Completer<void>();
      await tester.tap(find.byKey(const Key('transferencia-confirmar')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('transferencia-confirmar')),
            )
            .onPressed,
        isNull,
      );
      api.transferenciaGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Conflito com escala noturna.'), findsWidgets);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(api.alocacoes, hasLength(1));
      expect(api.alocacao['data_fim'], isNull);
      expect(api.requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('campos obrigatórios e início posterior ao encerramento', (
    tester,
  ) async {
    final api = await abrir(tester);
    await preencher(tester);
    await tester.enterText(
      find.byKey(const Key('transferencia-inicio')),
      '02/11/2026',
    );
    await tester.tap(find.byKey(const Key('transferencia-confirmar')));
    await tester.pumpAndSettle();
    expect(
      find.text('O novo início deve ser posterior ao encerramento.'),
      findsOneWidget,
    );
    expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busca vazia imediata, debounce e overlay ancorado', (
    tester,
  ) async {
    final api = await abrir(tester);
    final campo = find.byKey(const Key('transferencia-setor'));
    await tester.ensureVisible(campo);
    await tester.pumpAndSettle();
    await tester.tap(campo);
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters, {'tipo': 'setor', 'q': ''});
    api.requests.clear();
    await tester.enterText(campo, 'Filial');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 499));
    expect(api.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(api.requests.single.queryParameters, {
      'tipo': 'setor',
      'q': 'Filial',
    });
    final edit = find.descendant(
      of: campo,
      matching: find.byType(EditableText),
    );
    final box = InputDecorator.containerOf(tester.element(edit))!;
    final borda = box.localToGlobal(Offset.zero) & box.size;
    final popup = tester.getRect(
      find.byKey(const Key('transferencia-setor-sugestoes')),
    );
    expect(popup.top, closeTo(borda.bottom, 1));
    expect(popup.width, closeTo(borda.width, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('transferência em 320 pixels não tem overflow', (tester) async {
    await abrir(tester, size: const Size(320, 760));
    await preencher(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('somente linhas encerradas no passado recebem fundo discreto', (
    tester,
  ) async {
    final api = TransferenciaApiFake();
    api.alocacoes.addAll([
      {
        ...alocacaoJson(),
        'id': 'passada',
        'data_inicio': '2020-01-01',
        'data_fim': '2020-02-01',
      },
      {...alocacaoJson(), 'id': 'futura', 'data_fim': '2099-12-31'},
    ]);
    await mountAlocacoes(tester, api: api);
    final rows = tester.widget<DataTable>(find.byType(DataTable)).rows;
    expect(
      rows
          .firstWhere((r) => r.key == const ValueKey('passada'))
          .color!
          .resolve({}),
      const Color(0xFFFAFAFA),
    );
    expect(
      rows
          .firstWhere((r) => r.key == const ValueKey('futura'))
          .color!
          .resolve({}),
      isNull,
    );
    expect(
      rows
          .firstWhere((r) => r.key == const ValueKey('alocacao-1'))
          .color!
          .resolve({}),
      isNull,
    );
    expect(find.text('Transferir'), findsNWidgets(2));
    expect(find.text('Encerrada'), findsOneWidget);
    expect(find.text('Fim agendado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
