import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/alocacao.dart';
import '../../models/auth_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mudanca_alocacao_provider.dart';
import '../../repositories/alocacao_repository.dart';
import '../../repositories/repository_failure.dart';
import '../../utils/civil_date.dart';
import '../widgets/busca_assincrona.dart';

class TransferenciaAlocacaoDialog extends ConsumerStatefulWidget {
  const TransferenciaAlocacaoDialog({
    super.key,
    required this.atual,
    required this.funcionarioNome,
    required this.setorNome,
    required this.escalaNome,
    required this.sessionToken,
  });

  final Alocacao atual;
  final String funcionarioNome, setorNome, escalaNome, sessionToken;

  @override
  ConsumerState<TransferenciaAlocacaoDialog> createState() =>
      _TransferenciaAlocacaoDialogState();
}

class _TransferenciaAlocacaoDialogState
    extends ConsumerState<TransferenciaAlocacaoDialog> {
  final _form = GlobalKey<FormState>();
  final _fim = TextEditingController(), _inicio = TextEditingController();
  OpcaoMudancaAlocacao? _setor, _escala;
  String _inicioSugerido = '';
  bool _salvando = false, _semEscala = false;
  String? _erro;

  bool get _sessaoValida {
    final sessao = ref.read(authProvider).asData?.value;
    return mounted &&
        sessao != null &&
        !sessao.isMock &&
        sessao.user.role == UserRole.rh &&
        sessao.user.companyId != null &&
        sessao.user.companyId == widget.atual.empresaId &&
        sessao.accessToken == widget.sessionToken &&
        sessao.expiresAt.isAfter(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    var fim = civilDateIso(DateTime.now());
    if (fim.compareTo(widget.atual.dataInicio) < 0) {
      fim = widget.atual.dataInicio;
    }
    if (widget.atual.dataFim != null &&
        fim.compareTo(widget.atual.dataFim!) > 0) {
      fim = widget.atual.dataFim!;
    }
    _fim.text = civilDateDisplay(fim);
    _sugerirInicio();
    _fim.addListener(_sugerirInicio);
  }

  void _sugerirInicio() {
    // Acompanha o encerramento enquanto o RH não editar o início manualmente.
    if (_inicio.text.isNotEmpty && _inicio.text != _inicioSugerido) return;
    try {
      final fim = DateTime.parse(civilDateFromInput(_fim.text));
      final proximo = DateTime.utc(fim.year, fim.month, fim.day + 1);
      if (proximo.year > 9999) return;
      _inicioSugerido = civilDateDisplay(civilDateIso(proximo));
      _inicio.text = _inicioSugerido;
    } on FormatException {
      /* Não altera o início enquanto a data está incompleta. */
    }
  }

  @override
  void dispose() {
    _fim.removeListener(_sugerirInicio);
    _fim.dispose();
    _inicio.dispose();
    super.dispose();
  }

  String? _validarFim(String? value) {
    try {
      final fim = civilDateFromInput(value ?? '');
      if (fim.compareTo(widget.atual.dataInicio) < 0) {
        return 'O encerramento não pode ser anterior ao início atual.';
      }
      if (widget.atual.dataFim != null &&
          fim.compareTo(widget.atual.dataFim!) > 0) {
        return 'O encerramento deve respeitar a vigência atual.';
      }
      return null;
    } on FormatException {
      return 'Informe uma data válida em DD/MM/AAAA.';
    }
  }

  String? _validarInicio(String? value) {
    try {
      final inicio = civilDateFromInput(value ?? '');
      if (_validarFim(_fim.text) == null &&
          inicio.compareTo(civilDateFromInput(_fim.text)) <= 0) {
        return 'O novo início deve ser posterior ao encerramento.';
      }
      return null;
    } on FormatException {
      return 'Informe uma data válida em DD/MM/AAAA.';
    }
  }

  Future<void> _selecionarData(
    TextEditingController controller,
    String titulo,
  ) async {
    if (_salvando || !_sessaoValida) return;
    var inicial = DateTime.now();
    try {
      inicial = DateTime.parse(civilDateFromInput(controller.text));
    } on FormatException {
      /* Campo vazio. */
    }
    if (inicial.isBefore(DateTime(1900))) inicial = DateTime(1900);
    final selecionada = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: inicial,
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
      helpText: titulo,
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );
    if (mounted && _sessaoValida && selecionada != null) {
      controller.text = civilDateDisplay(civilDateIso(selecionada));
    }
  }

  Future<void> _salvar() async {
    if (_salvando || !_sessaoValida || !_form.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      // Uma única chamada: o servidor valida e grava os dois vínculos atomicamente.
      await ref
          .read(mudancaAlocacaoRepositoryProvider)
          .mudarAlocacao(
            atual: widget.atual,
            novoSetorId: _setor!.id,
            novaEscalaId: _semEscala ? null : _escala!.id,
            dataEncerramento: civilDateFromInput(_fim.text),
            dataTransicao: civilDateFromInput(_inicio.text),
          );
      if (mounted && _sessaoValida) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted || !_sessaoValida) return;
      final mensagem = error is RepositoryFailure
          ? error.message
          : 'Não foi possível transferir o funcionário.';
      setState(() => _erro = mensagem);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _data(
    String id,
    String titulo,
    TextEditingController controller,
    FormFieldValidator<String> validator,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(titulo, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      TextFormField(
        key: Key(id),
        controller: controller,
        enabled: !_salvando && _sessaoValida,
        keyboardType: TextInputType.datetime,
        validator: validator,
        decoration: InputDecoration(
          hintText: 'DD/MM/AAAA',
          suffixIcon: IconButton(
            tooltip: 'Selecionar data',
            onPressed: _salvando
                ? null
                : () => _selecionarData(controller, titulo),
            icon: const Icon(Icons.calendar_today_outlined),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider);
    final enabled = !_salvando && _sessaoValida;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_salvando,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Transferir funcionário'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vínculo atual',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.funcionarioNome,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('Setor: ${widget.setorNome}'),
                        const SizedBox(height: 4),
                        Text('Escala: ${widget.escalaNome}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _data(
                    'transferencia-fim',
                    'Data de Encerramento no Setor Atual',
                    _fim,
                    _validarFim,
                  ),
                  const SizedBox(height: 24),
                  BuscaAssincrona<OpcaoMudancaAlocacao>(
                    inputId: 'transferencia-setor',
                    titulo: 'Novo Setor',
                    hint: 'Selecione ou busque um setor',
                    validationMessage: 'Selecione um setor da lista.',
                    icon: Icons.location_on_outlined,
                    enabled: enabled,
                    // Busca vazia imediata (até 20); digitação com debounce de 500 ms.
                    buscar: (q, cancel) => ref
                        .read(mudancaAlocacaoRepositoryProvider)
                        .opcoesMudanca('setor', q, cancelToken: cancel),
                    label: (item) => item.nome,
                    onChanged: (value) => _setor = value,
                  ),
                  const SizedBox(height: 20),
                  if (!_semEscala)
                    BuscaAssincrona<OpcaoMudancaAlocacao>(
                      inputId: 'transferencia-escala',
                      titulo: 'Nova Escala',
                      hint: 'Selecione ou busque uma escala',
                      validationMessage: 'Selecione uma escala da lista.',
                      icon: Icons.calendar_month_outlined,
                      enabled: enabled,
                      buscar: (q, cancel) => ref
                          .read(mudancaAlocacaoRepositoryProvider)
                          .opcoesMudanca('escala', q, cancelToken: cancel),
                      label: (item) => item.nome,
                      onChanged: (value) => _escala = value,
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sem escala'),
                    value: _semEscala,
                    onChanged: !enabled
                        ? null
                        : (value) => setState(() {
                            _semEscala = value!;
                            _escala = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  _data(
                    'transferencia-inicio',
                    'Data de Início no Novo Setor',
                    _inicio,
                    _validarInicio,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'O início sugerido é o dia seguinte ao encerramento. Você pode ajustá-lo para uma data posterior. O histórico será preservado.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  if (_erro != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _erro!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _salvando ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const Key('transferencia-confirmar'),
            onPressed: enabled ? _salvar : null,
            icon: _salvando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz),
            label: Text(
              _salvando ? 'Transferindo…' : 'Confirmar transferência',
            ),
          ),
        ],
      ),
    );
  }
}
