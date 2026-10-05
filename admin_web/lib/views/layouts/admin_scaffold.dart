import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
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
          title: const Text('Ponto Aqui'),
          actions: [
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
                width: 260,
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
