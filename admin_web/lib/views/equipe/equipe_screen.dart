import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/smart_polling.dart';

import '../../models/funcionario.dart';
import '../../models/w06.dart';
import '../../providers/w06_provider.dart';
import '../../utils/civil_date.dart';
import '../widgets/w06_widgets.dart';
import '../widgets/responsive_table_container.dart';

class EquipeScreen extends ConsumerStatefulWidget {
  const EquipeScreen({super.key});
  @override
  ConsumerState<EquipeScreen> createState() => _EquipeScreenState();
}

class _EquipeScreenState extends ConsumerState<EquipeScreen>
    with WidgetsBindingObserver, SmartPolling<EquipeScreen> {
  @override
  bool get pollingEnabled => !_dialogAberto;

  @override
  Future<void> refreshForPolling(CancelToken cancelToken) =>
      ref.read(w06Provider.notifier).refreshSilently(cancelToken);

  final _tabelaScroll = ScrollController();
  String _busca = '';
  bool _dialogAberto = false;

  @override
  void dispose() {
    _tabelaScroll.dispose();
    super.dispose();
  }

  Future<void> _detalhes(Funcionario funcionario, W06Data data) async {
    if (_dialogAberto) return;
    setState(() => _dialogAberto = true);
    try {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (_) => _HistoricoDialog(funcionario: funcionario, data: data),
      );
    } finally {
      if (mounted) setState(() => _dialogAberto = false);
    }
  }

  @override
  Widget build(BuildContext context) => W06Content(
    path: '/equipe',
    builder: (data) {
      final pessoas = data.funcionarios.where(
        (f) => '${f.nome} ${f.matricula} ${f.cargo ?? ''}'
            .toLowerCase()
            .contains(_busca),
      );
      final hoje = civilDateIso(DateTime.now());
      String setorAtual(String id) {
        final atual = data.historico
            .where(
              (a) =>
                  a.funcionarioId == id &&
                  a.inicio.compareTo(hoje) <= 0 &&
                  (a.fim == null || a.fim!.compareTo(hoje) >= 0),
            )
            .firstOrNull;
        return atual == null
            ? 'Sem alocação vigente'
            : data.setorNome(atual.setorId);
      }

      final colors = Theme.of(context).colorScheme;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Equipe',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Selecione um funcionário para acompanhar seu histórico de jornada.',
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth < 600
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: width,
                          child: _ResumoEquipe(
                            label: 'Funcionários',
                            valor: data.funcionarios.length,
                            icon: Icons.groups_outlined,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _ResumoEquipe(
                            label: 'Períodos no histórico',
                            valor: data.historico.length,
                            icon: Icons.history,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                _EquipeSurface(
                  child: TextField(
                    key: const Key('equipe-busca'),
                    decoration: InputDecoration(
                      labelText: 'Buscar por nome, matrícula ou cargo',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: colors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colors.secondary),
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _busca = value.trim().toLowerCase()),
                  ),
                ),
                const SizedBox(height: 16),
                _EquipeTable(
                  controller: _tabelaScroll,
                  columns: const [
                    DataColumn(label: Text('Nome')),
                    DataColumn(label: Text('Matrícula')),
                    DataColumn(label: Text('Cargo')),
                    DataColumn(label: Text('Setor vigente')),
                    DataColumn(label: Text('Histórico')),
                  ],
                  rows: [
                    for (final f in pessoas)
                      DataRow(
                        key: ValueKey('equipe-${f.id}'),
                        onSelectChanged: _dialogAberto
                            ? null
                            : (_) => _detalhes(f, data),
                        cells: [
                          DataCell(Text(f.nome)),
                          DataCell(Text(f.matricula)),
                          DataCell(Text(f.cargo ?? '—')),
                          DataCell(Text(setorAtual(f.id))),
                          DataCell(
                            IconButton(
                              key: ValueKey('historico-${f.id}'),
                              tooltip: 'Ver histórico de ${f.nome}',
                              onPressed: _dialogAberto
                                  ? null
                                  : () => _detalhes(f, data),
                              icon: const Icon(Icons.history),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _EquipeSurface extends StatelessWidget {
  const _EquipeSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Card(margin: EdgeInsets.zero, child: child);
}

class _EquipeTable extends StatelessWidget {
  const _EquipeTable({
    required this.controller,
    required this.columns,
    required this.rows,
  });
  final ScrollController controller;
  final List<DataColumn> columns;
  final List<DataRow> rows;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _EquipeSurface(
      child: rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhum funcionário encontrado.'),
            )
          : ResponsiveTableContainer(
              controller: controller,
              child: DataTable(
                showCheckboxColumn: false,
                horizontalMargin: 20,
                columnSpacing: 32,
                headingRowHeight: 56,
                dataRowMinHeight: 64,
                dataRowMaxHeight: 96,
                headingRowColor: WidgetStateProperty.resolveWith(
                  (_) => colors.secondaryContainer,
                ),
                // Uma única linha sutil entre registros, sem borda dupla.
                dividerThickness: 0,
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.6),
                    width: 0.6,
                  ),
                ),
                columns: columns,
                rows: rows,
              ),
            ),
    );
  }
}

class _ResumoEquipe extends StatelessWidget {
  const _ResumoEquipe({
    required this.label,
    required this.valor,
    required this.icon,
  });
  final String label;
  final int valor;
  final IconData icon;
  @override
  Widget build(BuildContext context) => _EquipeSurface(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text('$valor', style: Theme.of(context).textTheme.headlineMedium),
          Text(label),
        ],
      ),
    ),
  );
}

class _HistoricoDialog extends StatelessWidget {
  const _HistoricoDialog({required this.funcionario, required this.data});
  final Funcionario funcionario;
  final W06Data data;
  @override
  Widget build(BuildContext context) {
    final historico =
        data.historico.where((a) => a.funcionarioId == funcionario.id).toList()
          ..sort((a, b) => b.inicio.compareTo(a.inicio));
    final hoje = civilDateIso(DateTime.now());
    return AlertDialog(
      title: Text(funcionario.nome),
      content: SizedBox(
        width: 900,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Matrícula ${funcionario.matricula} · ${funcionario.cargo ?? 'Cargo não informado'}',
              ),
              const SizedBox(height: 20),
              Text(
                'Histórico de escalas e alocações',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Cada período mantém seu setor e sua escala. O encerramento preserva as datas anteriores.',
              ),
              const SizedBox(height: 16),
              if (historico.isEmpty)
                const Text(
                  'Este funcionário ainda não possui histórico de alocações.',
                ),
              for (final a in historico)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _EquipeSurface(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              Text(
                                data.setorNome(a.setorId),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Chip(
                                label: Text(
                                  a.inicio.compareTo(hoje) > 0
                                      ? 'Programado'
                                      : a.fim != null &&
                                            a.fim!.compareTo(hoje) < 0
                                      ? 'Encerrado'
                                      : 'Vigente',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(a.escalaNome),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 24,
                            runSpacing: 8,
                            children: [
                              Text('Início: ${civilDateDisplay(a.inicio)}'),
                              Text(
                                'Fim: ${a.fim == null ? 'Em aberto' : civilDateDisplay(a.fim!)}',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
