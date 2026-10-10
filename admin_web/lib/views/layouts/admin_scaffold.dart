import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../widgets/brand_logo.dart';
import '../widgets/theme_toggle_button.dart';
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
      final desktop = constraints.maxWidth >= 800;
      final sidebar = Sidebar(currentPath: currentPath);
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: desktop ? 76 : 64,
          automaticallyImplyLeading: false,
          leading: desktop
              ? null
              : Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Abrir menu',
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
          title: desktop
              ? const Text(
                  'Gestão de ponto e jornada',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                )
              : BrandLogo(
                  width: (constraints.maxWidth - 160).clamp(80.0, 150.0),
                ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1),
          ),
          actions: [
            if (constraints.maxWidth >= 1100)
              Padding(
                padding: EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Área administrativa',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            const ThemeToggleButton(),
            IconButton(
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
        drawer: desktop
            ? null
            : Drawer(
                width: (constraints.maxWidth - 24).clamp(0.0, 280.0),
                child: sidebar,
              ),
        body: SafeArea(
          top: false,
          child: desktop
              ? Row(
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
                )
              : child,
        ),
      );
    },
  );
}
