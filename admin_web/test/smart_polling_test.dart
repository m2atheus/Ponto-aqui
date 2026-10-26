import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/providers/dashboard_provider.dart';
import 'package:ponto_aqui_admin/router/app_router.dart';
import 'package:ponto_aqui_admin/views/dashboard/dashboard_screen.dart';

import 'support/management_api_fake.dart';
import 'support/w06_api_fake.dart';
import 'w06_screens_test.dart' show mount;

ResponseBody counters(int employees) => jsonResponse({
  'empresa_id': 'empresa-1',
  'indicadores': {
    'funcionarios': employees,
    'setores': 2,
    'escalas_ativas': 1,
    'justificativas_pendentes': 0,
  },
});

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'consulta a cada 60 segundos sem apagar cards nem sobrepor chamadas',
    (tester) async {
      final api = W06ApiFake();
      final c = await mount(tester, '/dashboard', api: api);
      expect(find.text('Atualizar indicadores'), findsNothing);
      api.requests.clear();
      final gate = Completer<ResponseBody>();
      api.handler = (_) => gate.future;
      await tester.pump(const Duration(seconds: 59));
      expect(api.requests, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(api.requests, hasLength(1));
      expect(c.read(dashboardProvider).isLoading, isFalse);
      expect(c.read(dashboardProvider).requireValue['funcionarios'], 2);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 120));
      expect(api.requests, hasLength(1));
      gate.complete(counters(40));
      await tester.pumpAndSettle();
      expect(find.text('40'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.inactive,
    AppLifecycleState.detached,
  ]) {
    testWidgets('pausa em $state e retoma com uma consulta imediata', (
      tester,
    ) async {
      final api = W06ApiFake();
      await mount(tester, '/dashboard', api: api);
      api.requests.clear();
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump(const Duration(minutes: 5));
      expect(api.requests, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(1));
      await tester.pump(const Duration(seconds: 59));
      expect(api.requests, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'falha silenciosa preserva valores e tenta no próximo intervalo',
    (tester) async {
      final api = W06ApiFake();
      final c = await mount(tester, '/dashboard', api: api);
      api.handler = (_) => jsonResponse({
        'erro': {'mensagem': 'Indisponível'},
      }, 503);
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(c.read(dashboardProvider).requireValue['funcionarios'], 2);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      api.handler = (_) => counters(41);
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(find.text('41'), findsOneWidget);
    },
  );

  testWidgets('trocar de tela encerra o timer do Dashboard', (tester) async {
    final api = W06ApiFake();
    final c = await mount(tester, '/dashboard', api: api);
    c.read(appRouterProvider).go('/funcionarios');
    await tester.pumpAndSettle();
    api.requests.clear();
    await tester.pump(const Duration(minutes: 3));
    await tester.pumpAndSettle();
    expect(
      api.requests.where((r) => r.uri.path.endsWith('/dashboard')),
      isEmpty,
    );
    expect(
      api.requests.where((r) => r.uri.path.endsWith('/funcionarios')),
      hasLength(3),
    );
  });

  testWidgets(
    'modal pausa consultas e a lista atualiza depois sem perder formulário',
    (tester) async {
      final api = W06ApiFake();
      await mount(tester, '/funcionarios', api: api);
      await tester.tap(find.byKey(const Key('novo-funcionario')));
      await tester.pumpAndSettle();
      api.requests.clear();
      await tester.pump(const Duration(minutes: 3));
      expect(api.requests, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(
        api.requests.where((r) => r.uri.path.endsWith('/funcionarios')),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'esconder a aba cancela a consulta em andamento e rejeita resposta antiga',
    (tester) async {
      final api = W06ApiFake();
      final c = await mount(tester, '/dashboard', api: api);
      final gate = Completer<ResponseBody>();
      api.handler = (_) => gate.future;
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      gate.complete(counters(99));
      await tester.pumpAndSettle();
      expect(c.read(dashboardProvider).requireValue['funcionarios'], 2);
      api.handler = (_) => counters(42);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('42'), findsOneWidget);
    },
  );
}
