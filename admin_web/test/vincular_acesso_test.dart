import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/funcionario.dart';
import 'package:ponto_aqui_admin/providers/auth_provider.dart';
import 'package:ponto_aqui_admin/providers/funcionarios_provider.dart';
import 'package:ponto_aqui_admin/repositories/funcionario_repository.dart';
import 'package:ponto_aqui_admin/repositories/repository_failure.dart';
import 'package:ponto_aqui_admin/views/layouts/admin_scaffold.dart';

import 'funcionarios_screen_test.dart' show mountFuncionarios;
import 'support/management_api_fake.dart';

const acao = Key('gerar-acesso-app-funcionario-1');
const salvar = Key('criar-acesso-app');
const email = Key('acesso-app-email');
const senha = Key('acesso-app-senha');

Future<void> abrir(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(acao));
  await tester.tap(find.byKey(acao));
  await tester.pumpAndSettle();
}

Future<void> preencher(WidgetTester tester) async {
  await tester.enterText(find.byKey(email), '  Ana.App@Example.com  ');
  await tester.enterText(find.byKey(senha), ' Senha-com-espacos ');
}

void main() {
  testWidgets('gera acesso com JWT, mantém Shell e vínculo após recarregar', (
    tester,
  ) async {
    final app = await mountFuncionarios(tester);
    final shell = tester.element(find.byType(AdminScaffold));
    await abrir(tester);
    await preencher(tester);
    final senhaEditavel = find.descendant(
      of: find.byKey(senha),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(senhaEditavel).obscureText, isTrue);
    await tester.tap(find.byKey(const Key('acesso-app-ver-senha')));
    await tester.pump();
    expect(tester.widget<EditableText>(senhaEditavel).obscureText, isFalse);
    await tester.tap(find.byKey(salvar));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final post = app.api.requests.singleWhere((r) => r.method == 'POST');
    expect(
      post.uri.toString(),
      'https://api.example.com/api/v1/funcionarios/funcionario-1/vincular-acesso',
    );
    expect(post.headers['Authorization'], startsWith('Bearer '));
    expect(post.data, {
      'email': 'ana.app@example.com',
      'senha': ' Senha-com-espacos ',
    });
    expect(
      find.text('Acesso do funcionário ao App gerado com sucesso.'),
      findsOneWidget,
    );
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
      const Color(0xFF237A48),
    );
    expect(tester.widget<IconButton>(find.byKey(acao)).onPressed, isNull);
    expect(
      app.container.read(funcionariosProvider).asData!.value.single.usuarioId,
      'conta-funcionario-1',
    );
    expect(tester.element(find.byType(AdminScaffold)), same(shell));
    await tester.tap(find.byTooltip('Atualizar funcionários'));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.byKey(acao)).onPressed, isNull);
    // A senha nunca é incorporada ao DTO nem ao estado do funcionário.
    expect(
      app.container
          .read(funcionariosProvider)
          .asData!
          .value
          .single
          .toJson()
          .keys,
      isNot(contains('senha')),
    );
  });

  testWidgets('valida campos sem enviar e permite cancelar', (tester) async {
    final app = await mountFuncionarios(tester);
    await abrir(tester);
    await tester.tap(find.byKey(salvar));
    await tester.pumpAndSettle();
    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    expect(
      find.text('A senha deve ter pelo menos 8 caracteres.'),
      findsOneWidget,
    );
    expect(app.api.requests.where((r) => r.method == 'POST'), isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final status in [400, 409]) {
    testWidgets('erro $status preserva formulário e exibe SnackBar vermelho', (
      tester,
    ) async {
      final app = await mountFuncionarios(tester);
      await abrir(tester);
      await preencher(tester);
      app.api.nextStatus = status;
      app.api.nextBody = {
        'erro': {
          'codigo': 'EMAIL_INDISPONIVEL',
          'mensagem': 'E-mail indisponível para cadastro.',
        },
      };
      await tester.tap(find.byKey(salvar));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('E-mail indisponível para cadastro.'), findsWidgets);
      final context = tester.element(find.byType(AlertDialog));
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        Theme.of(context).colorScheme.error,
      );
      expect(
        tester.widget<TextFormField>(find.byKey(email)).controller!.text,
        '  Ana.App@Example.com  ',
      );
      expect(
        app.container.read(funcionariosProvider).asData!.value.single.usuarioId,
        isNull,
      );
      await tester.tap(find.byKey(salvar));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  testWidgets('bloqueia envio duplo, cancelamento e edição durante POST', (
    tester,
  ) async {
    final app = await mountFuncionarios(tester);
    final gate = app.api.writeGate = Completer<void>();
    await abrir(tester);
    await preencher(tester);
    await tester.tap(find.byKey(salvar));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(find.byKey(salvar)).onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
          .onPressed,
      isNull,
    );
    expect(tester.widget<TextFormField>(find.byKey(email)).enabled, isFalse);
    expect(tester.widget<TextFormField>(find.byKey(senha)).enabled, isFalse);
    expect(app.api.requests.where((r) => r.method == 'POST'), hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final vinculado in [false, true]) {
    testWidgets(
      'botão desabilitado para ${vinculado ? "vinculado" : "inativo"}',
      (tester) async {
        final api = ManagementApiFake();
        if (vinculado) {
          api.funcionarios.single['usuario_id'] = 'conta-existente';
        } else {
          api.funcionarios.single['ativo'] = false;
        }
        await mountFuncionarios(tester, api: api);
        expect(tester.widget<IconButton>(find.byKey(acao)).onPressed, isNull);
      },
    );
  }

  testWidgets('logout durante POST não contamina sessão nem exibe sucesso', (
    tester,
  ) async {
    final app = await mountFuncionarios(tester);
    final gate = app.api.writeGate = Completer<void>();
    await abrir(tester);
    await preencher(tester);
    await tester.tap(find.byKey(salvar));
    await tester.pump();
    await app.container.read(authProvider.notifier).logout();
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(app.container.read(authProvider).asData?.value, isNull);
    expect(
      find.text('Acesso do funcionário ao App gerado com sucesso.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('modal funciona em 320 pixels sem overflow', (tester) async {
    await mountFuncionarios(tester, size: const Size(320, 760));
    await abrir(tester);
    await preencher(tester);
    await tester.ensureVisible(find.byKey(salvar));
    await tester.tap(find.byKey(salvar));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('endpoint preserva prefixo do proxy e não usa /api/web', () async {
    final api = ManagementApiFake();
    final dio = Dio(BaseOptions(baseUrl: 'https://host.example/ponto/api/web/'))
      ..httpClientAdapter = api;
    addTearDown(() => dio.close(force: true));
    final dto = await FuncionarioRepository(
      dio,
      empresaId: 'empresa-1',
    ).vincularAcessoApp('funcionario-1', 'ana@example.com', 'senha123');
    expect(dto.temAcessoApp, isTrue);
    expect(
      api.requests.single.uri.path,
      '/ponto/api/v1/funcionarios/funcionario-1/vincular-acesso',
    );
  });

  for (final field in ['funcionario', 'usuario']) {
    test('rejeita resposta com $field de outra empresa', () async {
      final api = ManagementApiFake()
        ..handler = (_) => jsonResponse({
          'funcionario': {
            ...funcionarioJson(
              empresaId: field == 'funcionario' ? 'empresa-2' : 'empresa-1',
            ),
            'usuario_id': 'conta-1',
          },
          'usuario': {
            'id': 'conta-1',
            'papel': 'FUNCIONARIO',
            'empresa_id': field == 'usuario' ? 'empresa-2' : 'empresa-1',
          },
        }, 201);
      final dio = Dio(BaseOptions(baseUrl: 'https://host.example/api/web/'))
        ..httpClientAdapter = api;
      addTearDown(() => dio.close(force: true));
      expect(
        FuncionarioRepository(
          dio,
          empresaId: 'empresa-1',
        ).vincularAcessoApp('funcionario-1', 'ana@example.com', 'senha123'),
        throwsA(isA<RepositoryFailure>()),
      );
    });
  }

  test(
    'DTO tolera vínculo ausente/nulo e não envia usuário ao editar cadastro',
    () {
      expect(Funcionario.fromJson(funcionarioJson()).temAcessoApp, isFalse);
      expect(
        Funcionario.fromJson({...funcionarioJson(), 'usuario_id': null})
            .temAcessoApp,
        isFalse,
      );
      final dto = Funcionario.fromJson({
        ...funcionarioJson(),
        'usuario_id': 'conta-1',
      });
      expect(dto.toJson()['usuario_id'], 'conta-1');
      expect(dto.toRequestJson().keys, isNot(contains('usuario_id')));
    },
  );
}
