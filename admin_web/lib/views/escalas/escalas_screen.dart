import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/smart_polling.dart';

import '../../models/auth_session.dart';
import '../../models/escala.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escalas_provider.dart';
import '../widgets/status_badge.dart';
import '../widgets/w06_widgets.dart';
import 'escala_dialog.dart';

class EscalasScreen extends ConsumerStatefulWidget {
  const EscalasScreen({super.key});
  @override
  ConsumerState<EscalasScreen> createState() => _EscalasScreenState();
}

class _EscalasScreenState extends ConsumerState<EscalasScreen>
    with WidgetsBindingObserver, SmartPolling<EscalasScreen> {
  @override
  bool get pollingEnabled => !_ocupado;

  @override
  Future<void> refreshForPolling(CancelToken cancelToken) =>
      ref.read(escalasProvider.notifier).refreshSilently(cancelToken);

  bool _ocupado = false;
  Future<void> _formulario([Escala? escala]) async {
    final session = ref.read(authProvider).asData?.value;
    if (_ocupado ||
        session == null ||
        session.isMock ||
        session.user.role != UserRole.rh) {
      return;
    }
    setState(() => _ocupado = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => EscalaDialog(
          escala: escala,
          empresaId: session.user.companyId!,
          token: session.accessToken,
        ),
      );
      if (mounted &&
          saved == true &&
          ref.read(authProvider).asData?.value?.accessToken ==
              session.accessToken) {
        w06Message(context, 'Escala salva no banco.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _remover(Escala escala) async {
    if (_ocupado) return;
    final token = ref.read(authProvider).asData?.value?.accessToken;
    setState(() => _ocupado = true);
    try {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('Remover escala?'),
          content: Text(
            'Remover "${escala.nome}"? Escalas com histórico de alocações devem ser desativadas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remover'),
            ),
          ],
        ),
      );
      if (!mounted ||
          ok != true ||
          token != ref.read(authProvider).asData?.value?.accessToken) {
        return;
      }
      await ref.read(escalasProvider.notifier).remover(escala.id);
      if (mounted) w06Message(context, 'Escala removida do banco.');
    } catch (error) {
      if (mounted) w06Message(context, w06Error(error), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authProvider).asData?.value?.user.role != UserRole.rh) {
      return const Center(child: Text('Acesso exclusivo do RH.'));
    }
    final state = ref.watch(escalasProvider);
    return W06PageLayout(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Escalas',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              FilledButton.icon(
                onPressed: _ocupado || !state.hasValue
                    ? null
                    : () => _formulario(),
                icon: const Icon(Icons.add),
                label: const Text('Nova Escala'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Turnos e ciclos da empresa. Escalas já utilizadas preservam seus horários históricos.',
          ),
          const SizedBox(height: 20),
          state.when(
            skipLoadingOnRefresh: false,
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w06Error(error)),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(escalasProvider),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
            data: (escalas) => W06Table(
              emptyMessage: 'Nenhuma escala cadastrada.',
              columns: const [
                DataColumn(label: Text('Nome da Escala')),
                DataColumn(label: Text('Modelo')),
                DataColumn(label: Text('Turnos')),
                DataColumn(label: Text('Dias da Semana')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Ações')),
              ],
              rows: [
                for (final e in escalas)
                  DataRow(
                    cells: [
                      DataCell(Text(e.nome)),
                      DataCell(Text(e.modelo)),
                      DataCell(
                        SizedBox(
                          width: 180,
                          child: Text(
                            e.turnos.isEmpty
                                ? 'Sem turnos estruturados'
                                : e.turnos
                                      .map(
                                        (t) =>
                                            '${Escala.formatarHorario(t.inicio)}–${Escala.formatarHorario(t.fim)}${t.fim < t.inicio || t.diaSeguinte ? ' (+1 dia)' : ''} · ${t.intervalo} min',
                                      )
                                      .join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          e.ciclica
                              ? 'Ciclo contínuo'
                              : (e.turnos.expand((t) => t.dias).toSet().toList()
                                      ..sort())
                                    .map((d) => Escala.dias[d - 1])
                                    .join(', '),
                        ),
                      ),
                      DataCell(StatusBadge(ativo: e.ativa)),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: Key('editar-escala-${e.id}'),
                              tooltip: 'Editar escala',
                              onPressed: _ocupado ? null : () => _formulario(e),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              key: Key('remover-escala-${e.id}'),
                              tooltip: 'Remover escala',
                              onPressed: _ocupado ? null : () => _remover(e),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
