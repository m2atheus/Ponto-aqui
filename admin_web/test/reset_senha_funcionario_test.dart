import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dispositivos_funcionario_test.dart' show DispositivosApi, detalhes;
import 'support/management_api_fake.dart' show jsonResponse;

class ResetSenhaApi extends DispositivosApi {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (!options.uri.path.endsWith('/resetar-senha')) {
      return super.fetch(options, stream, cancel);
    }
    requests.add(options);
    await writeGate?.future;
    if (nextStatus != null) {
      final status = nextStatus!;
      nextStatus = null;
      return jsonResponse(nextBody, status);
    }
    return jsonResponse({
      'mensagem': 'Senha redefinida com sucesso para este funcionário.',
      'funcionario_id': 'funcionario-1',
      'empresa_id': 'empresa-1',
      'usuario_id': 'usuario-funcionario-1',
    });
  }
}

Future<void> abrirReset(
  WidgetTester tester,
  ResetSenhaApi api, {
  Size size = const Size(1440, 900),
}) async {
  await detalhes(tester, api, size: size);
  final botao = find.byKey(const Key('redefinir-senha-funcionario'));
  await tester.ensureVisible(botao);
  await tester.pumpAndSettle();
  await tester.tap(botao);
  await tester.pumpAndSettle();
}

Future<void> preencher(
  WidgetTester tester,
  String senha,
  String confirmacao,
) async {
  final campoSenha = find.byKey(const Key('reset-senha-nova'));
  final campoConfirmacao = find.byKey(const Key('reset-senha-confirmacao'));
  await tester.ensureVisible(campoSenha);
  await tester.enterText(campoSenha, senha);
  await tester.ensureVisible(campoConfirmacao);
  await tester.enterText(campoConfirmacao, confirmacao);
  await tester.ensureVisible(find.byKey(const Key('reset-senha-salvar')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'valida mínimo e confirmação antes de PUT; sucesso fecha modal e confirma em verde',
    (tester) async {
      final api = ResetSenhaApi();
      await abrirReset(tester, api);
      await preencher(tester, '1234567', '1234567');
      await tester.tap(find.byKey(const Key('reset-senha-salvar')));
      await tester.pumpAndSettle();
      expect(
        find.text('Informe uma senha de 8 a 1024 caracteres.'),
        findsOneWidget,
      );
      expect(
        api.requests.where((r) => r.uri.path.endsWith('/resetar-senha')),
        isEmpty,
      );
      await preencher(tester, 'NovaSenha123!', 'Diferente123!');
      await tester.tap(find.byKey(const Key('reset-senha-salvar')));
      await tester.pumpAndSettle();
      expect(find.text('As senhas não conferem.'), findsOneWidget);
      final senha = '  Nova senha 123!  ';
      await preencher(tester, senha, senha);
      await tester.tap(find.byKey(const Key('reset-senha-salvar')));
      await tester.pumpAndSettle();
      final put = api.requests.singleWhere(
        (r) => r.uri.path.endsWith('/resetar-senha'),
      );
      expect(put.method, 'PUT');
      expect(
        put.uri.path,
        '/api/v1/admin/funcionarios/funcionario-1/resetar-senha',
      );
      expect(put.headers['Authorization'], startsWith('Bearer '));
      expect(put.data, {'nova_senha': senha});
      expect(find.byKey(const Key('reset-senha-nova')), findsNothing);
      expect(
        find.text('Senha redefinida com sucesso para este funcionário.'),
        findsOneWidget,
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        const Color(0xFF237A48),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading bloqueia reenvio e erro mantém formulário com mensagem tratada',
    (tester) async {
      final api = ResetSenhaApi();
      await abrirReset(tester, api);
      await preencher(tester, 'NovaSenha123!', 'NovaSenha123!');
      api.writeGate = Completer<void>();
      api.nextStatus = 409;
      api.nextBody = {
        'erro': {
          'codigo': 'ACESSO_NAO_VINCULADO',
          'mensagem': 'Gere o acesso ao aplicativo antes de redefinir a senha.',
        },
      };
      await tester.tap(find.byKey(const Key('reset-senha-salvar')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('reset-senha-salvar')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('reset-senha-nova')))
            .enabled,
        isFalse,
      );
      api.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(
        api.requests.where((r) => r.uri.path.endsWith('/resetar-senha')),
        hasLength(1),
      );
      expect(
        find.text('Gere o acesso ao aplicativo antes de redefinir a senha.'),
        findsWidgets,
      );
      expect(find.byKey(const Key('reset-senha-nova')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sem conta vinculada, redefinição fica desabilitada', (
    tester,
  ) async {
    final api = ResetSenhaApi()..temAcessoApp = false;
    await detalhes(tester, api);
    final botao = find.byKey(const Key('redefinir-senha-funcionario'));
    expect(tester.widget<FilledButton>(botao).onPressed, isNull);
    expect(
      api.requests.where((r) => r.uri.path.endsWith('/resetar-senha')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320px, senha oculta por padrão e botão de visibilidade funciona',
    (tester) async {
      final api = ResetSenhaApi();
      await abrirReset(tester, api, size: const Size(320, 800));
      final campo = find.byKey(const Key('reset-senha-nova'));
      final editavel = find.descendant(
        of: campo,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editavel).obscureText, isTrue);
      await tester.ensureVisible(find.byTooltip('Mostrar nova senha'));
      await tester.tap(find.byTooltip('Mostrar nova senha'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(editavel).obscureText, isFalse);
      await preencher(tester, 'NovaSenha123!', 'NovaSenha123!');
      expect(tester.takeException(), isNull);
    },
  );
}
