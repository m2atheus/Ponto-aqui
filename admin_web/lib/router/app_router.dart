import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../views/auth/login_view.dart';
import '../views/dashboard/dashboard_screen.dart';
import '../views/empresas/empresas_screen.dart';
import '../views/escalas/escalas_screen.dart';
import '../views/layouts/admin_scaffold.dart';
import '../views/modules/module_placeholder_view.dart';
import 'access_policy.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  // listen atualiza redirects sem recriar o roteador e o Navigator do Shell.
  ref.listen(authProvider, (previous, next) => refresh.value++);
  final router = GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final atLogin = state.uri.path == '/login';
      final session = auth.asData?.value;
      if (session == null || !session.expiresAt.isAfter(DateTime.now())) {
        if (atLogin) return null;
        return Uri(
          path: '/login',
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      final destination = atLogin
          ? AccessPolicy.loginDestination(state.uri.queryParameters['from'])
          : state.uri.toString();
      if (!AccessPolicy.allows(
        session.user.role,
        Uri.parse(destination).path,
      )) {
        return '/acesso-negado';
      }
      if (atLogin || state.uri.path == '/') {
        return atLogin ? destination : '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/dashboard'),
      GoRoute(path: '/login', builder: (context, state) => const LoginView()),
      ShellRoute(
        navigatorKey: GlobalKey<NavigatorState>(),
        pageBuilder: (context, state, child) => NoTransitionPage(
          key: state.pageKey,
          child: AdminScaffold(currentPath: state.uri.path, child: child),
        ),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const DashboardScreen(),
            ),
          ),
          for (final entry in AccessPolicy.modules.entries)
            GoRoute(
              path: entry.key,
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: switch (entry.key) {
                  '/empresas' => const EmpresasScreen(),
                  '/empresas/nova' => const EmpresasScreen(abrirCadastro: true),
                  '/escalas' => const EscalasScreen(),
                  _ => ModulePlaceholderView(title: entry.value),
                },
              ),
            ),
          GoRoute(
            path: '/acesso-negado',
            builder: (context, state) => const ModulePlaceholderView(
              title: 'Acesso negado',
              message: 'Seu perfil não tem permissão para acessar esta página.',
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Página não encontrada.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Abrir Dashboard'),
            ),
          ],
        ),
      ),
    ),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
