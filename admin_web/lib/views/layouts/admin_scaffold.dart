import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import 'sidebar.dart';

class AdminScaffold extends ConsumerWidget {
  const AdminScaffold({
    super.key,
    required this.currentPath,
    required this.child,
  });
  final String currentPath;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1000;
      final sidebar = Sidebar(currentPath: currentPath);
      return Scaffold(
        appBar: AppBar(
          title: desktop
              ? const Text(
                  'Gestão de ponto e jornada',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                )
              : const BrandLogo(width: 150),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1),
          ),
          actions: [
            if (constraints.maxWidth >= 600)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 16,
                      color: BrandColors.teal,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Área administrativa',
                      style: TextStyle(color: BrandColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            IconButton(
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
        drawer: desktop ? null : Drawer(child: sidebar),
        body: Row(
          children: [
            if (desktop) ...[
              SizedBox(
                width: 280,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: sidebar,
                ),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: child),
          ],
        ),
      );
    },
  );
}
