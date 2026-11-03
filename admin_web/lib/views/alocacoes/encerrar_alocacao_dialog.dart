import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/alocacao.dart';
import '../../models/auth_session.dart';
import '../../providers/alocacoes_provider.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/repository_failure.dart';
import '../../utils/civil_date.dart';

class EncerrarAlocacaoDialog extends ConsumerStatefulWidget {
  const EncerrarAlocacaoDialog({
    super.key,
    required this.alocacao,
    required this.funcionarioNome,
    required this.setorNome,
    required this.sessionToken,
  });

  final Alocacao alocacao;
  final String funcionarioNome, setorNome, sessionToken;

  @override
  ConsumerState<EncerrarAlocacaoDialog> createState() =>
      _EncerrarAlocacaoDialogState();
}

class _EncerrarAlocacaoDialogState
    extends ConsumerState<EncerrarAlocacaoDialog> {
  final _form = GlobalKey<FormState>();
  final _fim = TextEditingController();
  bool _salvando = false;
  String? _erro;

  bool get _sessaoValida {
    final sessao = ref.read(authProvider).asData?.value;
    return mounted &&
        sessao != null &&
        !sessao.isMock &&
        sessao.user.role == UserRole.rh &&
        sessao.accessToken == widget.sessionToken &&
        sessao.expiresAt.isAfter(DateTime.now()) &&
        (widget.alocacao.empresaId == null ||
            widget.alocacao.empresaId == sessao.user.companyId);
  }

  @override
  void dispose() {
    _fim.dispose();
    super.dispose();
  }

  String? _validarFim(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe a data de fim.';
    try {
      return civilDateFromInput(value).compareTo(widget.alocacao.dataInicio) < 0
          ? 'A data final não pode ser anterior à inicial.'
          : null;
    } on FormatException {
      return 'Informe uma data válida em DD/MM/AAAA.';
    }
  }

  Future<void> _selecionarData() async {
    if (_salvando || !_sessaoValida) return;
    final primeira = DateTime.parse(widget.alocacao.dataInicio);
    var inicial = DateTime.now();
    try {
      inicial = DateTime.parse(civilDateFromInput(_fim.text));
    } on FormatException {
      /* Campo vazio. */
    }
    if (inicial.isBefore(primeira)) inicial = primeira;
    final data = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: inicial,
      firstDate: primeira,
      lastDate: DateTime(9999, 12, 31),
      helpText: 'Data de fim',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );
    if (mounted && _sessaoValida && data != null) {
      setState(() => _fim.text = civilDateDisplay(civilDateIso(data)));
    }
  }

  Future<void> _salvar() async {
    if (_salvando || !_sessaoValida || !_form.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref
          .read(alocacoesProvider.notifier)
          .encerrar(widget.alocacao, civilDateFromInput(_fim.text));
      if (mounted && _sessaoValida) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted && _sessaoValida) {
        final mensagem = error is RepositoryFailure
            ? error.message
            : 'Não foi possível encerrar a alocação.';
        setState(() => _erro = mensagem);
        final colors = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colors.error,
            content: Text(mensagem, style: TextStyle(color: colors.onError)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_salvando,
    child: AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Encerrar Alocação'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.funcionarioNome,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.setorNome} · Início: ${civilDateDisplay(widget.alocacao.dataInicio)}',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Somente a data de fim será preenchida. O vínculo e seu histórico serão preservados. '
                  'Depois, use Nova Alocação para cadastrar o novo setor ou escala.',
                ),
                const SizedBox(height: 20),
                const Text(
                  'Data de Fim',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('alocacao-data-fim'),
                  controller: _fim,
                  enabled: !_salvando,
                  keyboardType: TextInputType.datetime,
                  validator: _validarFim,
                  decoration: InputDecoration(
                    hintText: 'DD/MM/AAAA',
                    suffixIcon: IconButton(
                      tooltip: 'Selecionar data de fim',
                      onPressed: _salvando ? null : _selecionarData,
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A data de fim é inclusiva.',
                  style: TextStyle(fontSize: 12),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _erro!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          key: const Key('encerrar-alocacao-confirmar'),
          onPressed: _salvando ? null : _salvar,
          icon: _salvando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.event_busy_outlined),
          label: Text(_salvando ? 'Salvando…' : 'Encerrar'),
        ),
      ],
    ),
  );
}
