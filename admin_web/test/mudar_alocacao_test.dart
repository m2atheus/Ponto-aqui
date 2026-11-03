import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';

import 'support/management_api_fake.dart';
import 'support/w06_api_fake.dart';
import 'w06_screens_test.dart' show mount;

class MudancaApiFake extends W06ApiFake {
  MudancaApiFake({super.role}) {
    historico[1]['escala_id'] = 'escala-1';
  }
  bool conflito = false;
  Completer<void>? mudancaGate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.endsWith('/alocacoes/opcoes-mudanca')) {
      requests.add(options);
      final tipo = options.queryParameters['tipo'];
      return jsonResponse({
        'opcoes': [
          {
            'id': tipo == 'setor' ? 'setor-1' : 'escala-1',
            'nome': tipo == 'setor' ? 'Sede' : 'Comercial',
            'empresa_id': 'empresa-1',
          },
        ],
      });
    }
    if (path.endsWith('/mudar-alocacao')) {
      requests.add(options);
      await mudancaGate?.future;
      if (conflito) {
        return jsonResponse({
          'erro': {
            'codigo': 'CONFLITO_ESCALA',
            'mensagem': 'Conflito com plantão noturno.',
          },
        }, 409);
      }
      final body = Map<String, dynamic>.from(options.data as Map);
      final old = historico.firstWhere((a) => a['id'] == body['alocacao_id']);
      final inicio = DateTime.parse(body['data_transicao'] as String);
      final fim = DateTime.utc(
        inicio.year,
        inicio.month,
        inicio.day - 1,
      ).toIso8601String().substring(0, 10);
      old['data_fim'] = fim;
      final nova = {
        ...old,
        'id': 'nova-alocacao',
        'setor_id': body['novo_setor_id'],
        'escala_id': body['nova_escala_id'],
        'data_inicio': body['data_transicao'],
        'data_fim': null,
      };
      historico.add(nova);
      return jsonResponse({'alocacao_anterior': old, 'alocacao': nova}, 201);
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

Future<void> abrir(
  WidgetTester tester,
  MudancaApiFake api, {
  Size size = const Size(1440, 900),
}) async {
  await mount(tester, '/equipe', api: api, role: api.role, size: size);
  await tester.ensureVisible(find.byKey(const Key('historico-funcionario-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('historico-funcionario-1')));
  await tester.pumpAndSettle();
  final mudar = find.byKey(const Key('mudar-equipe-historico-2'));
  await tester.ensureVisible(mudar);
  await tester.pumpAndSettle();
  await tester.tap(mudar);
  await tester.pumpAndSettle();
}

Future<void> preencher(WidgetTester tester) async {
  for (final entry in {'setor': 'Sede', 'escala': 'Comercial'}.entries) {
    final campo = find.byKey(Key('mudanca-${entry.key}'));
    await tester.ensureVisible(campo);
    await tester.pumpAndSettle();
    await tester.tap(campo);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, entry.value));
    await tester.pumpAndSettle();
  }
  final data = find.byKey(const Key('mudanca-data'));
  await tester.ensureVisible(data);
  await tester.enterText(data, '04/11/2026');
  await tester.ensureVisible(find.byKey(const Key('mudanca-confirmar')));
  await tester.pumpAndSettle();
}

void main() {
  for (final papel in [UserRole.rh, UserRole.gestor]) {
    testWidgets(
      'troca pelo $papel preserva histórico e exibe aviso somente ao gestor',
      (tester) async {
        final api = MudancaApiFake(role: papel);
        await abrir(tester, api);
        expect(
          find.textContaining('Atenção Gestor:'),
          papel == UserRole.gestor ? findsOneWidget : findsNothing,
        );
        await preencher(tester);
        await tester.tap(find.byKey(const Key('mudanca-confirmar')));
        await tester.pumpAndSettle();
        final post = api.requests.singleWhere(
          (r) => r.uri.path.endsWith('/mudar-alocacao'),
        );
        expect(post.data, {
          'alocacao_id': 'historico-2',
          'novo_setor_id': 'setor-1',
          'nova_escala_id': 'escala-1',
          'data_transicao': '2026-11-04',
        });
        expect(post.headers['Authorization'], startsWith('Bearer '));
        expect(
          find.text('Escala/setor alterados. Histórico preservado.'),
          findsOneWidget,
        );
        expect(
          api.historico.firstWhere((a) => a['id'] == 'historico-2')['data_fim'],
          '2026-11-03',
        );
        expect(api.historico.last['data_fim'], isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'conflito mantém formulário e histórico; impede envio duplo durante loading',
    (tester) async {
      final api = MudancaApiFake(role: UserRole.gestor)..conflito = true;
      await abrir(tester, api);
      await preencher(tester);
      api.mudancaGate = Completer<void>();
      await tester.tap(find.byKey(const Key('mudanca-confirmar')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('mudanca-confirmar')))
            .onPressed,
        isNull,
      );
      api.mudancaGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Conflito com plantão noturno.'), findsWidgets);
      expect(find.text('Mudar Escala/Setor'), findsWidgets);
      expect(api.historico[1]['data_fim'], isNull);
      expect(
        api.requests.where((r) => r.uri.path.endsWith('/mudar-alocacao')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'gestor em 320px: aviso visível, formulário rolável e validação de seleção',
    (tester) async {
      final api = MudancaApiFake(role: UserRole.gestor);
      await abrir(tester, api, size: const Size(320, 720));
      expect(find.textContaining('Atenção Gestor:'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mudanca-confirmar')));
      await tester.pumpAndSettle();
      expect(
        api.requests.where((r) => r.uri.path.endsWith('/mudar-alocacao')),
        isEmpty,
      );
      expect(find.text('Selecione um setor da lista.'), findsOneWidget);
    },
  );

  testWidgets(
    'setor carrega vazio imediatamente e busca digitada espera 500ms',
    (tester) async {
      final api = MudancaApiFake();
      await abrir(tester, api);
      final campo = find.byKey(const Key('mudanca-setor'));
      await tester.tap(campo);
      await tester.pumpAndSettle();
      expect(api.requests.last.queryParameters['q'], '');
      api.requests.clear();
      await tester.enterText(campo, 'Sede');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(api.requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(api.requests.single.queryParameters, {
        'tipo': 'setor',
        'q': 'Sede',
      });
      final edit = find.descendant(
        of: campo,
        matching: find.byType(EditableText),
      );
      final box = InputDecorator.containerOf(tester.element(edit))!;
      final borda = box.localToGlobal(Offset.zero) & box.size;
      final menu = tester.getRect(
        find.byKey(const Key('mudanca-setor-sugestoes')),
      );
      expect(menu.top, closeTo(borda.bottom, 1));
      expect(menu.width, closeTo(borda.width, 1));
      expect(tester.takeException(), isNull);
    },
  );
}
