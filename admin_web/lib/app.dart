import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Ponto Aqui — Administração',
      debugShowCheckedModeBanner: false,
      theme: buildAdminTheme(),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
