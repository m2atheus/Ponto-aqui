import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/w06.dart';
import '../../providers/auth_provider.dart';
import '../../providers/w06_provider.dart';
import '../../repositories/repository_failure.dart';
import '../../router/access_policy.dart';
import '../../utils/civil_date.dart';
import 'responsive_table_container.dart';

class W06Content extends ConsumerWidget {
  const W06Content({super.key, required this.path, required this.builder});
  final String path;
  final Widget Function(W06Data data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null ||
        !session.expiresAt.isAfter(DateTime.now()) ||
        !AccessPolicy.allows(session.user.role, path)) {
      return const Center(
        child: Text('Seu perfil não tem acesso a esta página.'),
      );
    }
    return ref
        .watch(w06Provider)
        .when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    error is RepositoryFailure
                        ? error.message
                        : 'Não foi possível carregar os dados.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => ref.invalidate(w06Provider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
          data: builder,
        );
  }
}

/// Mesma largura útil para cabeçalho, filtros, ações e tabelas.
class W06PageLayout extends StatelessWidget {
  const W06PageLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: child,
      ),
    ),
  );
}

class W06Table extends StatelessWidget {
  const W06Table({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'Nenhum registro encontrado.',
  });
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final String emptyMessage;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: rows.isEmpty
        ? Padding(padding: const EdgeInsets.all(28), child: Text(emptyMessage))
        : ResponsiveTableContainer(
            child: DataTable(
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.resolveWith(
                (_) => Theme.of(context).colorScheme.secondaryContainer,
              ),
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: 0.6),
                  width: 0.6,
                ),
              ),
              dividerThickness: 0,
              dataRowMinHeight: 64,
              dataRowMaxHeight: 96,
              columns: columns,
              rows: rows,
            ),
          ),
  );
}

void w06Message(BuildContext context, String message, {bool error = false}) {
  final colors = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: error ? colors.error : null,
      content: Text(
        message,
        style: error ? TextStyle(color: colors.onError) : null,
      ),
    ),
  );
}

String w06Error(Object error) => error is RepositoryFailure
    ? error.message
    : 'Não foi possível concluir a operação. Tente novamente.';

class W06DateField extends StatelessWidget {
  const W06DateField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    enabled: enabled,
    keyboardType: TextInputType.datetime,
    decoration: InputDecoration(
      labelText: label,
      hintText: 'DD/MM/AAAA',
      suffixIcon: IconButton(
        tooltip: 'Selecionar $label',
        onPressed: enabled
            ? () async {
                DateTime initial = DateTime.now();
                try {
                  initial = DateTime.parse(civilDateFromInput(controller.text));
                } on FormatException {
                  /* Campo vazio ou incompleto. */
                }
                if (initial.year < 1900 || initial.year > 2100) {
                  initial = DateTime.now();
                }
                final date = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100, 12, 31),
                  helpText: 'Selecionar data',
                  cancelText: 'Cancelar',
                  confirmText: 'Confirmar',
                );
                if (context.mounted && date != null) {
                  controller.text = civilDateDisplay(civilDateIso(date));
                }
              }
            : null,
        icon: const Icon(Icons.calendar_month_outlined),
      ),
    ),
    validator: (value) {
      try {
        final iso = civilDateFromInput(value ?? '');
        final year = int.parse(iso.substring(0, 4));
        if (year < 1900 || year > 2100) return 'Use um ano entre 1900 e 2100.';
        return null;
      } on FormatException {
        return 'Informe uma data válida (DD/MM/AAAA).';
      }
    },
  );
}

String w06Hours(num minutes) {
  final seconds = (minutes * 60).round();
  final base =
      '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}';
  return seconds % 60 == 0
      ? base
      : '$base:${(seconds % 60).toString().padLeft(2, '0')}';
}
