import 'package:flutter/material.dart';

class ModulePlaceholderView extends StatelessWidget {
  const ModulePlaceholderView({
    super.key,
    required this.title,
    this.message = 'Esta tela será implementada na próxima etapa.',
  });
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Text(message),
      ],
    ),
  );
}
