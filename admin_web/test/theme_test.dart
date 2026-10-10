import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/app.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/providers/api_providers.dart';
import 'package:ponto_aqui_admin/providers/theme_provider.dart';
import 'package:ponto_aqui_admin/router/app_router.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/views/layouts/admin_scaffold.dart';
import 'package:ponto_aqui_admin/views/layouts/sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/auth_fakes.dart';
import 'support/management_api_fake.dart';

// Exercita o ThemeStorage real; substitui somente o acesso à plataforma.
// Mutabilidade intencional para simular falhas e gravações pendentes no teste.
// ignore: must_be_immutable
class MemoryPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};
  bool failReads = false, failWrites = false;
  Completer<void>? writeGate;

  @override
  Future<String?> getString(String key) async {
    if (failReads) throw StateError('Armazenamento bloqueado');
    return values[key];
  }

  @override
  Future<void> setString(String key, String value) async {
    await writeGate?.future;
    if (failWrites) throw StateError('Armazenamento bloqueado');
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> mountTheme(
  WidgetTester tester,
  MemoryPreferences preferences, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final storage = ThemeStorage(preferences);
  final savedTheme = await storage.load();
  final tokens = MemoryTokenStorage()
    ..session = sessionFor(UserRole.rh).toJson();
  final dio = createDioClient(
    baseUrl: 'https://api.example.com/api/web/',
    tokenStorage: tokens,
  )..httpClientAdapter = ManagementApiFake();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    dio.close(force: true);
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        themeStorageProvider.overrideWithValue(storage),
        initialThemeModeProvider.overrideWithValue(savedTheme),
        tokenStorageProvider.overrideWithValue(tokens),
        dioProvider.overrideWithValue(dio),
      ],
      child: const AdminApp(),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AdminApp)),
  );
  // Já no primeiro frame, antes de a autenticação terminar, o tema é o salvo.
  expect(
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
    savedTheme,
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('preferência ausente/inválida ou inacessível usa tema claro; escuro é restaurado', () async {
    final preferences = MemoryPreferences();
    final storage = ThemeStorage(preferences);
    expect(await storage.load(), ThemeMode.light);
    preferences.values[ThemeStorage.key] = 'desconhecido';
    expect(await storage.load(), ThemeMode.light);
    await storage.save(ThemeMode.dark);
    expect(await storage.load(), ThemeMode.dark);
    preferences.failReads = true;
    expect(await storage.load(), ThemeMode.light);
  });

  testWidgets(
    'alternância persiste, mantém router/Shell/Sidebar e restaura no primeiro frame',
    (tester) async {
      final preferences = MemoryPreferences();
      final c = await mountTheme(tester, preferences);
      final router = c.read(appRouterProvider);
      final shell = tester.element(find.byType(AdminScaffold));
      final sidebar = tester.element(find.byType(Sidebar));
      await tester.tap(find.byTooltip('Ativar tema escuro'));
      await tester.pumpAndSettle();
      expect(preferences.values[ThemeStorage.key], 'dark');
      expect(
        Theme.of(tester.element(find.byType(AdminScaffold))).brightness,
        Brightness.dark,
      );
      expect(c.read(appRouterProvider), same(router));
      expect(tester.element(find.byType(AdminScaffold)), same(shell));
      expect(tester.element(find.byType(Sidebar)), same(sidebar));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountTheme(tester, preferences);
      expect(find.byTooltip('Ativar tema claro'), findsOneWidget);
      await tester.tap(find.byTooltip('Ativar tema claro'));
      await tester.pumpAndSettle();
      expect(preferences.values[ThemeStorage.key], 'light');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'erro de persistência mantém o tema e informa falha, sem quebrar a navegação',
    (tester) async {
      final preferences = MemoryPreferences()..failWrites = true;
      await mountTheme(tester, preferences);
      await tester.tap(find.byTooltip('Ativar tema escuro'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(
        find.text('Não foi possível salvar o tema. Tente novamente.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'modal aberto mantém campos; cards, tabela e Sidebar têm superfícies escuras',
    (tester) async {
      final preferences = MemoryPreferences()
        ..values[ThemeStorage.key] = 'dark';
      final c = await mountTheme(tester, preferences);
      c.read(appRouterProvider).go('/escalas');
      await tester.pumpAndSettle();
      final tableTheme = Theme.of(tester.element(find.byType(DataTable)));
      expect(tableTheme.cardTheme.color, const Color(0xFF1E1E1E));
      expect(
        tableTheme.dataTableTheme.headingTextStyle!.color,
        tableTheme.colorScheme.primary,
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(Sidebar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, const Color(0xFF1E1E1E));
      await tester.tap(find.text('Nova Escala'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('escala-nome')),
        'Nome preservado',
      );
      final dialog = tester.element(find.byType(AlertDialog));
      expect(
        Theme.of(dialog).dialogTheme.backgroundColor,
        const Color(0xFF1E1E1E),
      );
      await c.read(themeProvider.notifier).toggle();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(AlertDialog)), same(dialog));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('escala-nome')))
            .controller!
            .text,
        'Nome preservado',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cliques enquanto salva não gravam temas fora de ordem', (
    tester,
  ) async {
    final preferences = MemoryPreferences()..writeGate = Completer<void>();
    final c = await mountTheme(tester, preferences);
    final first = c.read(themeProvider.notifier).toggle();
    await c.read(themeProvider.notifier).toggle();
    expect(c.read(themeProvider), ThemeMode.light);
    preferences.writeGate!.complete();
    await first;
    await tester.pumpAndSettle();
    expect(c.read(themeProvider), ThemeMode.dark);
    expect(preferences.values[ThemeStorage.key], 'dark');
  });

  testWidgets('botão permanece acessível em 320 pixels', (tester) async {
    await mountTheme(tester, MemoryPreferences(), size: const Size(320, 760));
    await tester.tap(find.byTooltip('Ativar tema escuro'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ativar tema claro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
