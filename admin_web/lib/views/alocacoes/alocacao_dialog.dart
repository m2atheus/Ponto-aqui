import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/alocacao.dart';
import '../../models/funcionario.dart';
import '../../models/setor.dart';
import '../../providers/alocacoes_provider.dart';
import '../../providers/funcionarios_provider.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/repository_failure.dart';
import '../../utils/civil_date.dart';
import '../widgets/busca_assincrona.dart';

class AlocacaoDialog extends ConsumerStatefulWidget {
  const AlocacaoDialog({
    super.key,
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
  ConsumerState<AlocacaoDialog> createState() => _AlocacaoDialogState();
}

class _AlocacaoDialogState extends ConsumerState<AlocacaoDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _inicio;
  late final TextEditingController _fim;
  Funcionario? _funcionario;
  Setor? _setor;
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
      return fim && !_encerramento ? null : 'Informe a data.';
    }
    try {
      final iso = civilDateFromInput(value);
      if (fim) {
        String inicio;
        try {
          inicio = civilDateFromInput(_inicio.text);
        } on FormatException {
          // A mensagem do início inválido pertence ao próprio campo.
          return null;
        }
        if (iso.compareTo(inicio) < 0) {
          return 'A data final não pode ser anterior à inicial.';
        }
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
      final fimInformado = _fim.text.trim();
      final dto = Alocacao(
        id: anterior?.id ?? '',
        funcionarioId: anterior?.funcionarioId ?? _funcionario!.id,
        setorId: anterior?.setorId ?? _setor!.id,
        dataInicio: anterior?.dataInicio ?? civilDateFromInput(_inicio.text),
        dataFim: fimInformado.isEmpty ? null : civilDateFromInput(fimInformado),
        empresaId: widget.empresaId,
        escalaId:
            anterior?.escalaId ??
            (_escalaId == 'sem-escala' ? null : _escalaId),
      );
      await ref
          .read(alocacoesProvider.notifier)
          .salvar(dto, funcionario: _funcionario, setor: _setor);
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
      labelText: fim ? (_encerramento ? 'Fim' : 'Fim (opcional)') : 'Início',
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
    final anterior = widget.alocacao;
    return PopScope(
      canPop: !_salvando,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        clipBehavior: Clip.none,
        actionsAlignment: MainAxisAlignment.end,
        actionsOverflowButtonSpacing: 12,
        title: Text(_encerramento ? 'Encerrar alocação' : 'Nova Alocação'),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  BuscaAssincrona<Funcionario>(
                    key: const Key('alocacao-funcionario'),
                    inputId: 'alocacao-funcionario-input',
                    titulo: 'Funcionário',
                    hint: 'Selecione ou busque por nome ou matrícula',
                    validationMessage: 'Selecione o funcionário.',
                    enabled: !_salvando,
                    icon: Icons.person_search_outlined,
                    label: (f) => '${f.nome} — ${f.matricula}',
                    buscar: (q, cancel) => ref
                        .read(funcionarioRepositoryProvider)
                        .buscar(q, ativo: true, cancelToken: cancel),
                    onChanged: (f) => setState(() => _funcionario = f),
                  ),
                  const SizedBox(height: 20),
                  BuscaAssincrona<Setor>(
                    key: const Key('alocacao-setor'),
                    inputId: 'alocacao-setor-input',
                    titulo: 'Setor',
                    hint: 'Selecione ou busque pelo nome do setor',
                    validationMessage: 'Selecione o setor.',
                    enabled: !_salvando,
                    icon: Icons.location_on_outlined,
                    label: (s) => s.nome,
                    buscar: (q, cancel) => ref
                        .read(setorRepositoryProvider)
                        .buscar(q, cancelToken: cancel),
                    onChanged: (s) => setState(() => _setor = s),
                  ),
                  const SizedBox(height: 20),
                  _campoData(_inicio, fim: false),
                  const SizedBox(height: 16),
                  Text(
                    'Escala',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const Key('alocacao-escala'),
                    isExpanded: true,
                    initialValue: _escalaId,
                    menuMaxHeight: 280,
                    borderRadius: BorderRadius.circular(12),
                    decoration: const InputDecoration(
                      hintText: 'Selecione uma escala',
                    ),
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
                    'A data de fim é opcional. Se deixada em branco, a alocação terá vigência por tempo indeterminado.',
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

/// O alvo do overlay é somente o TextField: ajuda e erros ficam fora dele.
