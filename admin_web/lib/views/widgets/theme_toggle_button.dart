import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_provider.dart';

class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(themeProvider) == ThemeMode.dark;
    return IconButton(
      key: const Key('theme-toggle'),
      tooltip: dark ? 'Ativar tema claro' : 'Ativar tema escuro',
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () async {
        try {
          await ref.read(themeProvider.notifier).toggle();
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Não foi possível salvar o tema. Tente novamente.',
                ),
              ),
            );
          }
        }
      },
    );
  }
}
