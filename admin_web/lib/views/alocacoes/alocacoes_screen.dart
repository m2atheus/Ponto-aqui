import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/smart_polling.dart';

import '../widgets/responsive_table_container.dart';

import '../../models/alocacao.dart';
import '../../models/auth_session.dart';
import '../../models/funcionario.dart';
import '../../models/setor.dart';
import '../../providers/alocacoes_provider.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/repository_failure.dart';
import '../../utils/civil_date.dart';
import '../modules/module_placeholder_view.dart';

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
  bool _dialogAberto = false;

  @override
  void dispose() {
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
        builder: (_) => _AlocacaoDialog(
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
    final temOpcoes =
        data != null &&
        data.funcionarios.any((f) => f.ativo) &&
        data.setores.any((s) => s.ativo);
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
                onPressed: enabled && temOpcoes
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
            if (!temOpcoes)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Para criar uma alocação, cadastre ao menos um funcionário ativo e um setor ativo na sua empresa.',
                    ),
                  ),
                ),
              ),
            if (data.alocacoes.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhuma alocação cadastrada.'),
                ),
              )
            else
              _tabela(data, enabled),
          ],
        ],
      ),
    );
  }

  Widget _tabela(AlocacoesData data, bool enabled) {
    final funcionarios = {for (final f in data.funcionarios) f.id: f};
    final setores = {for (final s in data.setores) s.id: s};
    return Card(
      child: ResponsiveTableContainer(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 12),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Funcionário')),
            DataColumn(label: Text('Matrícula')),
            DataColumn(label: Text('Setor')),
            DataColumn(label: Text('Início')),
            DataColumn(label: Text('Fim')),
            DataColumn(label: Text('Ações')),
          ],
          rows: [
            for (final row in data.alocacoes)
              DataRow(
                key: ValueKey(row.id),
                cells: [
                  DataCell(
                    Text(
                      funcionarios[row.funcionarioId]?.nome ??
                          'Funcionário ${row.funcionarioId}',
                    ),
                  ),
                  DataCell(
                    Text(funcionarios[row.funcionarioId]?.matricula ?? '—'),
                  ),
                  DataCell(
                    Text(setores[row.setorId]?.nome ?? 'Setor ${row.setorId}'),
                  ),
                  DataCell(Text(civilDateDisplay(row.dataInicio))),
                  DataCell(
                    Text(
                      row.dataFim == null
                          ? 'Em aberto'
                          : civilDateDisplay(row.dataFim!),
                    ),
                  ),
                  DataCell(
                    row.dataFim == null
                        ? IconButton(
                            key: Key('encerrar-alocacao-${row.id}'),
                            tooltip: 'Encerrar alocação',
                            onPressed: enabled
                                ? () => _formulario(data, row)
                                : null,
                            icon: const Icon(Icons.event_busy_outlined),
                          )
                        : const Text('Fim definido'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AlocacaoDialog extends ConsumerStatefulWidget {
  const _AlocacaoDialog({
    required this.data,
    required this.empresaId,
    required this.sessionToken,
    this.alocacao,
  });
  final AlocacoesData data;
  final String empresaId;
  final String sessionToken;
  final Alocacao? alocacao;
  @override
  ConsumerState<_AlocacaoDialog> createState() => _AlocacaoDialogState();
}

class _AlocacaoDialogState extends ConsumerState<_AlocacaoDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _inicio;
  late final TextEditingController _fim;
  String? _funcionarioId;
  String? _setorId;
  String _escalaId = 'sem-escala';
  bool _salvando = false;
  String? _erro;
  bool get _encerramento => widget.alocacao != null;

  @override
  void initState() {
    super.initState();
    final hoje = civilDateIso(DateTime.now());
    final inicio = widget.alocacao?.dataInicio ?? hoje;
    _inicio = TextEditingController(text: civilDateDisplay(inicio));
    _fim = TextEditingController(
      text: _encerramento
          ? civilDateDisplay(inicio.compareTo(hoje) > 0 ? inicio : hoje)
          : '',
    );
  }

  @override
  void dispose() {
    _inicio.dispose();
    _fim.dispose();
    super.dispose();
  }

  String? _validarData(String? value, {bool fim = false}) {
    if (value == null || value.trim().isEmpty) {
      return fim && !_encerramento && _escalaId == 'sem-escala'
          ? null
          : 'Informe a data.';
    }
    try {
      final iso = civilDateFromInput(value);
      if (fim && iso.compareTo(civilDateFromInput(_inicio.text)) < 0) {
        return 'A data final não pode ser anterior à inicial.';
      }
      return null;
    } on FormatException {
      return 'Informe uma data válida em DD/MM/AAAA.';
    }
  }

  Future<void> _selecionarData(
    TextEditingController controller,
    bool fim,
  ) async {
    if (_salvando) return;
    DateTime initial;
    try {
      initial = DateTime.parse(civilDateFromInput(controller.text));
    } on FormatException {
      initial = DateTime.now();
    }
    final selected = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDate: initial,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: fim ? 'Data de fim' : 'Data de início',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
      fieldLabelText: 'Data',
      fieldHintText: 'DD/MM/AAAA',
    );
    if (mounted && selected != null) {
      setState(
        () => controller.text = civilDateDisplay(civilDateIso(selected)),
      );
    }
  }

  Future<void> _salvar() async {
    if (_salvando || !_form.currentState!.validate()) return;
    final session = ref.read(authProvider).asData?.value;
    if (session?.accessToken != widget.sessionToken ||
        session?.user.companyId != widget.empresaId) {
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final anterior = widget.alocacao;
      final dto = Alocacao(
        id: anterior?.id ?? '',
        funcionarioId: anterior?.funcionarioId ?? _funcionarioId!,
        setorId: anterior?.setorId ?? _setorId!,
        dataInicio: anterior?.dataInicio ?? civilDateFromInput(_inicio.text),
        dataFim: _fim.text.trim().isEmpty
            ? null
            : civilDateFromInput(_fim.text),
        empresaId: widget.empresaId,
        escalaId:
            anterior?.escalaId ??
            (_escalaId == 'sem-escala' ? null : _escalaId),
      );
      await ref.read(alocacoesProvider.notifier).salvar(dto);
      if (mounted &&
          ref.read(authProvider).asData?.value?.accessToken ==
              widget.sessionToken) {
        Navigator.pop(context, true);
      }
    } on RepositoryFailure catch (error) {
      if (mounted &&
          ref.read(authProvider).asData?.value?.accessToken ==
              widget.sessionToken) {
        setState(() => _erro = error.message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(
              error.message,
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _campoData(
    TextEditingController controller, {
    required bool fim,
  }) => TextFormField(
    key: Key(fim ? 'alocacao-data-fim' : 'alocacao-data-inicio'),
    controller: controller,
    enabled: !_salvando,
    maxLength: 10,
    keyboardType: TextInputType.datetime,
    validator: (value) => _validarData(value, fim: fim),
    decoration: InputDecoration(
      labelText: fim
          ? (_encerramento || _escalaId != 'sem-escala'
                ? 'Fim'
                : 'Fim (opcional)')
          : 'Início',
      hintText: 'DD/MM/AAAA',
      counterText: '',
      suffixIcon: IconButton(
        tooltip: fim ? 'Selecionar data de fim' : 'Selecionar data de início',
        onPressed: _salvando ? null : () => _selecionarData(controller, fim),
        icon: const Icon(Icons.calendar_month_outlined),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final funcionarios = widget.data.funcionarios
        .where((f) => f.ativo)
        .toList();
    final setores = widget.data.setores.where((s) => s.ativo).toList();
    final anterior = widget.alocacao;
    return PopScope(
      canPop: !_salvando,
      child: AlertDialog(
        title: Text(_encerramento ? 'Encerrar alocação' : 'Nova Alocação'),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (anterior != null) ...[
                  Text(
                    'Funcionário: ${_nomeFuncionario(anterior.funcionarioId)}',
                  ),
                  const SizedBox(height: 8),
                  Text('Setor: ${_nomeSetor(anterior.setorId)}'),
                  const SizedBox(height: 8),
                  Text('Início: ${civilDateDisplay(anterior.dataInicio)}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Defina o último dia desta alocação. O vínculo ficará no histórico.',
                  ),
                ] else ...[
                  DropdownButtonFormField<String>(
                    key: const Key('alocacao-funcionario'),
                    isExpanded: true,
                    initialValue: _funcionarioId,
                    decoration: const InputDecoration(labelText: 'Funcionário'),
                    items: [
                      for (final Funcionario f in funcionarios)
                        DropdownMenuItem(
                          value: f.id,
                          child: Text(
                            '${f.nome} — ${f.matricula}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _salvando
                        ? null
                        : (value) => setState(() => _funcionarioId = value),
                    validator: (value) =>
                        value == null ? 'Selecione o funcionário.' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('alocacao-setor'),
                    isExpanded: true,
                    initialValue: _setorId,
                    decoration: const InputDecoration(labelText: 'Setor'),
                    items: [
                      for (final Setor s in setores)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(s.nome, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _salvando
                        ? null
                        : (value) => setState(() => _setorId = value),
                    validator: (value) =>
                        value == null ? 'Selecione o setor.' : null,
                  ),
                  const SizedBox(height: 16),
                  _campoData(_inicio, fim: false),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('alocacao-escala'),
                    isExpanded: true,
                    initialValue: _escalaId,
                    decoration: const InputDecoration(labelText: 'Escala'),
                    items: [
                      const DropdownMenuItem(
                        value: 'sem-escala',
                        child: Text('Sem escala (sem apuração de jornada)'),
                      ),
                      for (final e in widget.data.escalas.where(
                        (e) => e.ativa && e.modelo != 'Legado',
                      ))
                        DropdownMenuItem(
                          value: e.id,
                          child: Text(e.nome, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _salvando
                        ? null
                        : (v) => setState(() => _escalaId = v!),
                  ),
                ],
                const SizedBox(height: 16),
                _campoData(_fim, fim: true),
                if (!_encerramento) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Com escala, informe o fim do período para validar conflitos de jornada. Sem escala, o vínculo pode ficar em aberto.',
                  ),
                ],
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _erro!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_salvando) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _salvando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _salvando ? null : _salvar,
            child: Text(
              _salvando
                  ? 'Salvando...'
                  : (_encerramento ? 'Encerrar' : 'Salvar'),
            ),
          ),
        ],
      ),
    );
  }

  String _nomeFuncionario(String id) =>
      widget.data.funcionarios.where((f) => f.id == id).firstOrNull?.nome ?? id;
  String _nomeSetor(String id) =>
      widget.data.setores.where((s) => s.id == id).firstOrNull?.nome ?? id;
}
