import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/views/funcionarios/dispositivos_funcionario_section.dart';

import 'support/management_api_fake.dart' show jsonResponse;
import 'support/w06_api_fake.dart';
import 'w06_screens_test.dart' as w06;

const codigo = '31da5a20-1a4a-41ef-87c8-e5a3f986d313';

class DispositivosApi extends W06ApiFake {
  DispositivosApi({super.role});
  final aparelhos = <Map<String, dynamic>>[];
  bool temAcessoApp = true;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (!options.uri.path.contains('/api/v1/admin/funcionarios/')) {
      return super.fetch(options, stream, cancel);
    }
    requests.add(options);
    if (options.method == 'GET') {
      return jsonResponse({
        'dispositivos': aparelhos,
        'setores_disponiveis': [
          {'id': 'setor-1', 'nome': 'Sede'},
        ],
        'tem_acesso_app': temAcessoApp,
      });
    }
    await writeGate?.future;
    if (nextStatus != null) {
      final status = nextStatus!;
      nextStatus = null;
      return jsonResponse(nextBody, status);
    }
    if (options.uri.path.endsWith('/revogar')) {
      final dto = aparelhos.first;
      dto['ativo'] = false;
      dto['status'] = 'Inativo';
      return jsonResponse({'dispositivo': dto});
    }
    final data = options.data as Map;
    final dto = <String, dynamic>{
      'id': 'aparelho-${aparelhos.length + 1}',
      'empresa_id': 'empresa-1',
      'device_uuid': data['device_uuid'],
      'tipo': data['tipo'],
      'ativo': true,
      'status': 'Ativo',
      'nome_identificador': data['nome_identificador'] ?? 'Aparelho pessoal',
      'setor_id': data['tipo'] == 'RELOGIO' ? data['setor_id'] : null,
      'setores': data['tipo'] == 'RELOGIO'
          ? [
              {'id': data['setor_id'], 'nome': 'Sede', 'ativo': true},
            ]
          : [],
      'ultimo_acesso_em': null,
    };
    aparelhos.add(dto);
    return jsonResponse({'dispositivo': dto}, 201);
  }
}

Future<void> detalhes(
  WidgetTester tester,
  DispositivosApi api, {
  UserRole role = UserRole.rh,
  Size size = const Size(1440, 900),
}) async {
  await w06.mount(tester, '/funcionarios', api: api, role: role, size: size);
  await tester.ensureVisible(
    find.byKey(const Key('aparelhos-funcionario-funcionario-1')),
  );
  await tester.tap(
    find.byKey(const Key('aparelhos-funcionario-funcionario-1')),
  );
  await tester.pumpAndSettle();
}

Future<void> abrirFormulario(WidgetTester tester) async {
  final botao = find.byKey(const Key('autorizar-aparelho'));
  await tester.ensureVisible(botao);
  await tester.tap(botao);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'aparelho compartilhado exibe todos os setores e suas revogações',
    (tester) async {
      final api = DispositivosApi();
      api.aparelhos.add({
        'id': 'aparelho-1',
        'empresa_id': 'empresa-1',
        'device_uuid': codigo,
        'tipo': 'RELOGIO',
        'ativo': true,
        'status': 'Ativo',
        'nome_identificador': 'Relógio compartilhado',
        'setor_id': 'setor-1',
        'setores': [
          {'id': 'setor-1', 'nome': 'Sede', 'ativo': false},
          {'id': 'setor-2', 'nome': 'Portaria', 'ativo': true},
        ],
        'ultimo_acesso_em': null,
      });
      await detalhes(tester, api, size: const Size(320, 800));
      expect(find.text('Setores autorizados'), findsOneWidget);
      expect(find.text('Sede (inativo)'), findsOneWidget);
      expect(find.text('Portaria'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('RH autoriza aparelho, envia JWT e revoga preservando a linha', (
    tester,
  ) async {
    final api = DispositivosApi();
    await detalhes(tester, api);
    expect(find.text('Aparelhos / Segurança'), findsOneWidget);
    expect(
      find.text('Nenhum aparelho vinculado a este funcionário.'),
      findsOneWidget,
    );
    await abrirFormulario(tester);
    await tester.tap(find.byKey(const Key('aparelho-salvar')));
    await tester.pumpAndSettle();
    expect(
      find.text('Informe o UUID completo exibido no aplicativo.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('aparelho-codigo')), codigo);
    api.writeGate = Completer<void>();
    await tester.tap(find.byKey(const Key('aparelho-salvar')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('aparelho-salvar')))
          .onPressed,
      isNull,
    );
    api.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AutorizarAparelhoDialog), findsNothing);
    expect(find.text('Ativo'), findsOneWidget);
    final request = api.requests.firstWhere((r) => r.method == 'POST');
    expect(
      request.uri.path,
      '/api/v1/admin/funcionarios/funcionario-1/dispositivos',
    );
    expect(request.data, {'device_uuid': codigo, 'tipo': 'PESSOAL'});
    expect(request.headers['Authorization'], startsWith('Bearer '));
    final revogar = find.byKey(const ValueKey('revogar-aparelho-1'));
    await tester.ensureVisible(revogar);
    await tester.tap(revogar);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revogar acesso'));
    await tester.pumpAndSettle();
    expect(find.text('Inativo'), findsOneWidget);
    expect(api.aparelhos, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('relógio compartilha tipo e setor sem overflow em 320 pixels', (
    tester,
  ) async {
    final api = DispositivosApi();
    await detalhes(tester, api, size: const Size(320, 800));
    await abrirFormulario(tester);
    await tester.enterText(find.byKey(const Key('aparelho-codigo')), codigo);
    await tester.ensureVisible(find.byKey(const Key('aparelho-tipo')));
    await tester.tap(find.byKey(const Key('aparelho-tipo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relógio Compartilhado').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('aparelho-setor')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('aparelho-salvar')));
    await tester.tap(find.byKey(const Key('aparelho-salvar')));
    await tester.pumpAndSettle();
    expect(api.aparelhos.single['tipo'], 'RELOGIO');
    expect(api.aparelhos.single['setor_id'], 'setor-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'erro de conflito mantém formulário e exibe mensagem limpa da API',
    (tester) async {
      final api = DispositivosApi();
      await detalhes(tester, api);
      await abrirFormulario(tester);
      await tester.enterText(find.byKey(const Key('aparelho-codigo')), codigo);
      api.nextStatus = 409;
      api.nextBody = {
        'erro': {
          'codigo': 'DISPOSITIVO_CONFLITANTE',
          'mensagem': 'Este código já pertence a outro vínculo de aparelho.',
        },
      };
      await tester.tap(find.byKey(const Key('aparelho-salvar')));
      await tester.pumpAndSettle();
      expect(find.byType(AutorizarAparelhoDialog), findsOneWidget);
      expect(
        find.text('Este código já pertence a outro vínculo de aparelho.'),
        findsOneWidget,
      );
      expect(api.aparelhos, isEmpty);
    },
  );

  testWidgets('histórico da Equipe permanece focado em escalas e alocações', (
    tester,
  ) async {
    final api = DispositivosApi(role: UserRole.gestor);
    await w06.mount(tester, '/equipe', api: api, role: UserRole.gestor);
    await tester.tap(find.byKey(const ValueKey('historico-funcionario-1')));
    await tester.pumpAndSettle();
    expect(find.text('Histórico de escalas e alocações'), findsOneWidget);
    expect(find.text('Aparelhos / Segurança'), findsNothing);
    expect(find.byKey(const Key('autorizar-aparelho')), findsNothing);
    expect(api.requests.every((r) => r.method == 'GET'), isTrue);
    expect(
      api.requests.where((r) => r.uri.path.contains('/dispositivos')),
      isEmpty,
    );
  });

  testWidgets('funcionário sem conta precisa gerar acesso antes de autorizar', (
    tester,
  ) async {
    final api = DispositivosApi()..temAcessoApp = false;
    await detalhes(tester, api);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('autorizar-aparelho')))
          .onPressed,
      isNull,
    );
    expect(
      find.text(
        'Gere o acesso ao aplicativo para este funcionário antes de autorizar aparelhos.',
      ),
      findsOneWidget,
    );
  });

  for (final confirmar in [false, true]) {
    testWidgets(
      'conversão para compartilhado depende de confirmação ($confirmar)',
      (tester) async {
        final api = DispositivosApi();
        await detalhes(tester, api, size: const Size(320, 800));
        await abrirFormulario(tester);
        await tester.enterText(
          find.byKey(const Key('aparelho-codigo')),
          codigo,
        );
        await tester.ensureVisible(find.byKey(const Key('aparelho-tipo')));
        await tester.tap(find.byKey(const Key('aparelho-tipo')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Relógio Compartilhado').last);
        await tester.pumpAndSettle();
        api.nextStatus = 409;
        api.nextBody = {
          'erro': {
            'codigo': 'CONVERSAO_RELOGIO_NECESSARIA',
            'mensagem': 'Este aparelho está cadastrado como Pessoal. Confirme a conversão para Relógio Compartilhado.',
          },
        };
        await tester.tap(find.byKey(const Key('aparelho-salvar')));
        await tester.pumpAndSettle();
        expect(
          find.text('Converter para Relógio Compartilhado?'),
          findsOneWidget,
        );
        expect(api.requests.where((r) => r.method == 'POST'), hasLength(1));
        expect(api.aparelhos, isEmpty);
        if (confirmar) {
          await tester.tap(
            find.byKey(const Key('aparelho-confirmar-conversao')),
          );
        } else {
          await tester.tap(find.widgetWithText(TextButton, 'Cancelar').last);
        }
        await tester.pumpAndSettle();
        if (confirmar) {
          final request = api.requests.where((r) => r.method == 'POST').last;
          expect((request.data as Map)['converter_para_relogio'], isTrue);
          expect(api.aparelhos.single['tipo'], 'RELOGIO');
          expect(find.byType(AutorizarAparelhoDialog), findsNothing);
        } else {
          expect(api.requests.where((r) => r.method == 'POST'), hasLength(1));
          expect(api.aparelhos, isEmpty);
          expect(find.byType(AutorizarAparelhoDialog), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
