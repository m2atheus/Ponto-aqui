import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/providers/api_providers.dart';
import 'package:ponto_aqui_admin/router/app_router.dart';
import 'package:ponto_aqui_admin/views/dashboard/dashboard_screen.dart';
import 'package:ponto_aqui_admin/views/layouts/admin_scaffold.dart';
import 'package:ponto_aqui_admin/views/layouts/sidebar.dart';

import 'theme_test.dart' show MemoryPreferences, mountTheme;
import 'w06_screens_test.dart' show mount;

void main() {
  final sidebar = find.byKey(const Key('sidebar-width'));
  final userMenu = find.byKey(const Key('sidebar-user-menu'));

  testWidgets(
    'recolher ganha espaço, não transborda e mantém estado ao navegar',
    (tester) async {
      final c = await mount(tester, '/dashboard');
      final shell = tester.element(find.byType(AdminScaffold));
      final menu = tester.element(find.byType(Sidebar));
      final contentLeft = tester.getTopLeft(find.byType(DashboardScreen)).dx;
      expect(tester.getSize(sidebar).width, 280);

      await tester.tap(find.byTooltip('Recolher menu'));
      await tester.pump();
      for (var frame = 0; frame < 15; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      expect(tester.getSize(sidebar).width, 76);
      expect(
        contentLeft - tester.getTopLeft(find.byType(DashboardScreen)).dx,
        closeTo(204, 1),
      );
      expect(find.widgetWithText(ListTile, 'Setores'), findsNothing);
      await tester.tap(find.byTooltip('Setores'));
      await tester.pumpAndSettle();
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.path,
        '/setores',
      );
      expect(tester.element(find.byType(AdminScaffold)), same(shell));
      expect(tester.element(find.byType(Sidebar)), same(menu));
      expect(tester.getSize(sidebar).width, 76);

      await tester.tap(find.byTooltip('Expandir menu'));
      await tester.pump();
      for (var frame = 0; frame < 15; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      expect(tester.getSize(sidebar).width, 280);
      expect(find.widgetWithText(ListTile, 'Setores'), findsOneWidget);
    },
  );

  for (final collapsed in [false, true]) {
    testWidgets('menu de usuário funciona com sidebar recolhida=$collapsed', (
      tester,
    ) async {
      final preferences = MemoryPreferences();
      final c = await mountTheme(tester, preferences);
      if (collapsed) {
        await tester.tap(find.byTooltip('Recolher menu'));
        await tester.pumpAndSettle();
      }
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      expect(find.text('Meu Perfil'), findsOneWidget);
      expect(find.text('Configurações'), findsOneWidget);
      expect(find.text('Sair do Sistema'), findsOneWidget);
      expect(
        find.byKey(const Key('sidebar-user-menu-divider')),
        findsOneWidget,
      );
      final card = tester.getRect(userMenu);
      final first = tester.getRect(
        find.widgetWithText(MenuItemButton, 'Meu Perfil'),
      );
      final last = tester.getRect(
        find.widgetWithText(MenuItemButton, 'Sair do Sistema'),
      );
      expect(first.left, closeTo(card.left + 8, 1));
      expect(last.bottom, lessThanOrEqualTo(card.top - 8));
      if (!collapsed) expect(first.right, closeTo(card.right - 8, 1));
      await tester.tap(find.text('Meu Perfil'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Perfil de acesso'), findsOneWidget);
      expect(find.text('E-mail'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();

      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configurações'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byTooltip('Ativar tema escuro'),
        ),
      );
      await tester.pumpAndSettle();
      expect(preferences.values['ponto_aqui_theme'], 'dark');
      expect(find.text('Escuro'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.widgetWithText(MenuItemButton, 'Sair do Sistema'))
            .bottom,
        lessThanOrEqualTo(tester.getRect(userMenu).top - 8),
      );
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.path,
        '/dashboard',
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final role in UserRole.values) {
    testWidgets('modo recolhido mantém permissões de ${role.name}', (
      tester,
    ) async {
      await mount(tester, '/dashboard', role: role);
      await tester.tap(find.byTooltip('Recolher menu'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sidebar-item-/empresas')),
        role == UserRole.superadmin ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('sidebar-item-/setores')),
        role == UserRole.rh ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('sidebar-item-/equipe')),
        role == UserRole.superadmin ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final mobile in [false, true]) {
    testWidgets('logout pelo rodapé encerra sessão; mobile=$mobile', (
      tester,
    ) async {
      final c = await mount(
        tester,
        '/dashboard',
        size: Size(mobile ? 320 : 1440, 760),
      );
      if (mobile) {
        await tester.tap(find.byTooltip('Abrir menu'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sidebar-toggle')), findsNothing);
      }
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      if (mobile) {
        final card = tester.getRect(userMenu);
        final first = tester.getRect(
          find.widgetWithText(MenuItemButton, 'Meu Perfil'),
        );
        final last = tester.getRect(
          find.widgetWithText(MenuItemButton, 'Sair do Sistema'),
        );
        expect(first.left, closeTo(card.left + 8, 1));
        expect(first.right, closeTo(card.right - 8, 1));
        expect(last.bottom, lessThanOrEqualTo(card.top - 8));
      }
      await tester.tap(find.text('Sair do Sistema'));
      await tester.pumpAndSettle();
      expect(await c.read(tokenStorageProvider).readSession(), isNull);
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.path,
        '/login',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('perfil aberto no Drawer fecha o menu sem perder o modal', (
    tester,
  ) async {
    await mount(tester, '/dashboard', size: const Size(320, 760));
    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    await tester.tap(userMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meu Perfil'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Perfil de acesso'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    final state = tester.state<ScaffoldState>(
      find.descendant(
        of: find.byType(AdminScaffold),
        matching: find.byType(Scaffold),
      ),
    );
    expect(state.isDrawerOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape e clique fora fecham o menu sem navegar', (tester) async {
    final c = await mount(tester, '/dashboard');
    await tester.tap(userMenu);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Meu Perfil'), findsNothing);
    await tester.tap(userMenu);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 120));
    await tester.pumpAndSettle();
    expect(find.text('Meu Perfil'), findsNothing);
    expect(
      c.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/dashboard',
    );
    expect(tester.takeException(), isNull);
  });
}
