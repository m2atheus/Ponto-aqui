import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/smart_polling.dart';

import '../widgets/responsive_table_container.dart';

import '../../models/alocacao.dart';
import '../../models/auth_session.dart';
import '../../providers/alocacoes_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/w06_provider.dart';
import '../../repositories/repository_failure.dart';
import '../../utils/civil_date.dart';
import '../modules/module_placeholder_view.dart';
import 'alocacao_dialog.dart';
import 'encerrar_alocacao_dialog.dart';
import 'transferencia_alocacao_dialog.dart';

class AlocacoesScreen extends ConsumerStatefulWidget {
  const AlocacoesScreen({super.key});
  @override
  ConsumerState<AlocacoesScreen> createState() => _AlocacoesScreenState();
}

class _AlocacoesScreenState extends ConsumerState<AlocacoesScreen>
    with WidgetsBindingObserver, SmartPolling<AlocacoesScreen> {
  @override
  bool get pollingEnabled => !_dialogAberto;

  @override
  Future<void> refreshForPolling(CancelToken cancelToken) =>
      ref.read(alocacoesProvider.notifier).refreshSilently(cancelToken);

  final _scroll = ScrollController();
  final _pesquisa = TextEditingController();
  Timer? _debouncePesquisa;
  String _termoPesquisa = '';
  bool _dialogAberto = false;

  void _pesquisar(String value) {
    _debouncePesquisa?.cancel();
    final termo = value.trim().toLowerCase();
    if (termo.isEmpty) {
      _limparPesquisa();
      return;
    }
    _debouncePesquisa = Timer(const Duration(milliseconds: 300), () {
      if (mounted && termo != _termoPesquisa) {
        setState(() => _termoPesquisa = termo);
      }
    });
  }

  void _limparPesquisa() {
    _debouncePesquisa?.cancel();
    _pesquisa.clear();
    if (_termoPesquisa.isNotEmpty) setState(() => _termoPesquisa = '');
  }

  List<Alocacao> _filtrarAlocacoes(AlocacoesData data) {
    // A API atual entrega a lista completa: filtra localmente, sem novas chamadas.
    if (_termoPesquisa.isEmpty) return data.alocacoes;
    final funcionarios = {for (final f in data.funcionarios) f.id: f};
    return data.alocacoes
        .where((alocacao) {
          final funcionario = funcionarios[alocacao.funcionarioId];
          return funcionario != null &&
              (funcionario.nome.toLowerCase().contains(_termoPesquisa) ||
                  funcionario.matricula.toLowerCase().contains(_termoPesquisa));
        })
        .toList(growable: false);
  }

  @override
  void dispose() {
    _debouncePesquisa?.cancel();
    _pesquisa.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _formulario(AlocacoesData data, [Alocacao? alocacao]) async {
    final session = ref.read(authProvider).asData?.value;
    if (_dialogAberto ||
        session == null ||
        session.isMock ||
        session.user.role != UserRole.rh) {
      return;
    }
    setState(() => _dialogAberto = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => alocacao != null
            ? EncerrarAlocacaoDialog(
                alocacao: alocacao,
                funcionarioNome:
                    data.funcionarios
                        .where((f) => f.id == alocacao.funcionarioId)
                        .firstOrNull
                        ?.nome ??
                    'Funcionário',
                setorNome:
                    data.setores
                        .where((s) => s.id == alocacao.setorId)
                        .firstOrNull
                        ?.nome ??
                    'Setor',
                sessionToken: session.accessToken,
              )
            : AlocacaoDialog(
                data: data,
                alocacao: alocacao,
                empresaId: session.user.companyId!,
                sessionToken: session.accessToken,
              ),
      );
      if (mounted &&
          saved == true &&
          ref.read(authProvider).asData?.value?.accessToken ==
              session.accessToken) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              alocacao == null
                  ? 'Alocação cadastrada.'
                  : 'Alocação encerrada. Histórico preservado.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _dialogAberto = false);
    }
  }

  Future<void> _mudar(AlocacoesData data, Alocacao atual) async {
    final sessao = ref.read(authProvider).asData?.value;
    if (_dialogAberto ||
        sessao == null ||
        sessao.isMock ||
        sessao.user.role != UserRole.rh) {
      return;
    }
    setState(() => _dialogAberto = true);
    try {
      final salvo = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => TransferenciaAlocacaoDialog(
          atual: atual,
          sessionToken: sessao.accessToken,
          funcionarioNome:
              data.funcionarios
                  .where((f) => f.id == atual.funcionarioId)
                  .firstOrNull
                  ?.nome ??
              'Funcionário',
          setorNome:
              data.setores
                  .where((s) => s.id == atual.setorId)
                  .firstOrNull
                  ?.nome ??
              'Setor',
          escalaNome: atual.escalaId == null
              ? 'Sem escala'
              : data.escalas
                        .where((e) => e.id == atual.escalaId)
                        .firstOrNull
                        ?.nome ??
                    'Escala indisponível',
        ),
      );
      if (mounted &&
          salvo == true &&
          ref.read(authProvider).asData?.value?.accessToken ==
              sessao.accessToken) {
        ref.invalidate(alocacoesProvider);
        ref.invalidate(w06Provider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Funcionário transferido. Histórico preservado.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _dialogAberto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider).asData?.value;
    if (session?.user.role != UserRole.rh || session?.user.companyId == null) {
      return const ModulePlaceholderView(
        title: 'Acesso negado',
        message: 'Esta área é exclusiva do RH da empresa.',
      );
    }
    final dados = ref.watch(alocacoesProvider);
    final data = dados.asData?.value;
    final enabled =
        !session!.isMock &&
        !dados.isLoading &&
        !dados.hasError &&
        !_dialogAberto;
    final visiveis = data == null
        ? const <Alocacao>[]
        : _filtrarAlocacoes(data);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Alocações',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              FilledButton.icon(
                key: const Key('nova-alocacao'),
                onPressed: enabled && data != null
                    ? () => _formulario(data)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Nova Alocação'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Funcionários, setores e períodos da sua empresa. Encerrar mantém o histórico.',
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            // Só o campo acompanha o texto imediatamente; a tabela espera o debounce.
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _pesquisa,
              builder: (context, value, child) => TextField(
                key: const Key('alocacoes-pesquisa'),
                controller: _pesquisa,
                enabled: enabled && data != null,
                onChanged: _pesquisar,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Pesquisar por Nome ou Matrícula do funcionário...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('alocacoes-limpar-pesquisa'),
                          tooltip: 'Limpar pesquisa',
                          onPressed: _limparPesquisa,
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (dados.isLoading) const LinearProgressIndicator(),
          if (dados.hasError)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dados.error is RepositoryFailure
                          ? (dados.error as RepositoryFailure).message
                          : 'Não foi possível carregar as alocações.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: !session.isMock && !_dialogAberto
                          ? () => ref.invalidate(alocacoesProvider)
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          if (data != null && !dados.hasError) ...[
            if (visiveis.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _termoPesquisa.isEmpty
                          ? 'Nenhuma alocação cadastrada.'
                          : 'Nenhuma alocação encontrada para este termo.',
                    ),
                  ),
                ),
              )
            else
              _tabela(data, enabled, visiveis),
          ],
        ],
      ),
    );
  }

  Widget _tabela(AlocacoesData data, bool enabled, List<Alocacao> visiveis) {
    final funcionarios = {for (final f in data.funcionarios) f.id: f};
    final setores = {for (final s in data.setores) s.id: s};
    final hoje = civilDateIso(DateTime.now());
    final colors = Theme.of(context).colorScheme;
    bool encerrada(Alocacao row) =>
        row.dataFim != null && row.dataFim!.compareTo(hoje) < 0;
    Widget texto(Alocacao row, String valor) => Text(
      valor,
      style: encerrada(row)
          ? TextStyle(color: colors.onSurfaceVariant.withValues(alpha: 0.65))
          : null,
    );
    return Card(
      child: ResponsiveTableContainer(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 12),
        child: DataTable(
          columnSpacing: 24,
          horizontalMargin: 20,
          columns: const [
            DataColumn(label: Text('Funcionário')),
            DataColumn(label: Text('Matrícula')),
            DataColumn(label: Text('Setor')),
            DataColumn(label: Text('Início')),
            DataColumn(label: Text('Fim')),
            DataColumn(label: Text('Ações')),
          ],
          rows: [
            for (final row in visiveis)
              DataRow(
                key: ValueKey(row.id),
                color: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered)) {
                    return colors.primary.withValues(alpha: 0.06);
                  }
                  return encerrada(row)
                      ? (Theme.of(context).brightness == Brightness.dark
                            ? colors.surfaceContainerHighest.withValues(
                                alpha: 0.35,
                              )
                            : const Color(0xFFFAFAFA))
                      : null;
                }),
                cells: [
                  DataCell(
                    texto(
                      row,
                      funcionarios[row.funcionarioId]?.nome ??
                          'Funcionário ${row.funcionarioId}',
                    ),
                  ),
                  DataCell(
                    texto(
                      row,
                      funcionarios[row.funcionarioId]?.matricula ?? '—',
                    ),
                  ),
                  DataCell(
                    texto(
                      row,
                      setores[row.setorId]?.nome ?? 'Setor ${row.setorId}',
                    ),
                  ),
                  DataCell(texto(row, civilDateDisplay(row.dataInicio))),
                  DataCell(
                    texto(
                      row,
                      row.dataFim == null
                          ? 'Em aberto'
                          : civilDateDisplay(row.dataFim!),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!encerrada(row))
                          OutlinedButton.icon(
                            key: Key('transferir-alocacao-${row.id}'),
                            onPressed: enabled ? () => _mudar(data, row) : null,
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('Transferir'),
                          ),
                        row.dataFim == null
                            ? IconButton(
                                key: Key('encerrar-alocacao-${row.id}'),
                                tooltip: 'Somente encerrar alocação',
                                onPressed: enabled
                                    ? () => _formulario(data, row)
                                    : null,
                                icon: const Icon(Icons.event_busy_outlined),
                              )
                            : Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: texto(
                                  row,
                                  encerrada(row) ? 'Encerrada' : 'Fim agendado',
                                ),
                              ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
