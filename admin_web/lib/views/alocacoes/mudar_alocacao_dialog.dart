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

class MudarAlocacaoDialog extends ConsumerStatefulWidget {
  const MudarAlocacaoDialog({
    super.key,
    required this.alocacao,
    required this.funcionarioNome,
    required this.setorNome,
    required this.sessionToken,
  });

  final Alocacao alocacao;
  final String funcionarioNome, setorNome, sessionToken;

  @override
  ConsumerState<MudarAlocacaoDialog> createState() =>
      _MudarAlocacaoDialogState();
}

class _MudarAlocacaoDialogState extends ConsumerState<MudarAlocacaoDialog> {
  final _form = GlobalKey<FormState>();
  final _data = TextEditingController();
  OpcaoMudancaAlocacao? _setor, _escala;
  bool _semEscala = false, _salvando = false;
  String? _erro;

  bool get _sessaoValida {
    final sessao = ref.read(authProvider).asData?.value;
    return mounted &&
        sessao != null &&
        !sessao.isMock &&
        {UserRole.rh, UserRole.gestor}.contains(sessao.user.role) &&
        sessao.accessToken == widget.sessionToken &&
        sessao.user.companyId != null &&
        sessao.user.companyId == widget.alocacao.empresaId &&
        sessao.expiresAt.isAfter(DateTime.now());
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  String? _validarData(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe a data efetiva.';
    try {
      final data = civilDateFromInput(value);
      if (data.compareTo(widget.alocacao.dataInicio) <= 0) {
        return 'A mudança deve ser posterior ao início atual.';
      }
      if (widget.alocacao.dataFim != null &&
          data.compareTo(widget.alocacao.dataFim!) > 0) {
        return 'A mudança deve ocorrer dentro da vigência atual.';
      }
      return null;
    } on FormatException {
      return 'Informe uma data válida em DD/MM/AAAA.';
    }
  }

  Future<void> _selecionarData() async {
    if (_salvando || !_sessaoValida) return;
    final inicio = DateTime.parse(widget.alocacao.dataInicio);
    final primeira = DateTime(inicio.year, inicio.month, inicio.day + 1);
    final ultima = widget.alocacao.dataFim == null
        ? DateTime(9999, 12, 31)
        : DateTime.parse(widget.alocacao.dataFim!);
    if (ultima.isBefore(primeira)) return;
    var inicial = DateTime.now();
    try {
      inicial = DateTime.parse(civilDateFromInput(_data.text));
    } on FormatException {
      /* Campo vazio. */
    }
    if (inicial.isBefore(primeira)) inicial = primeira;
    if (inicial.isAfter(ultima)) inicial = ultima;
    final data = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: inicial,
      firstDate: primeira,
      lastDate: ultima,
      helpText: 'Data efetiva da mudança',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );
    if (data != null && _sessaoValida) {
      _data.text = civilDateDisplay(civilDateIso(data));
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
          .read(mudancaAlocacaoRepositoryProvider)
          .mudarAlocacao(
            atual: widget.alocacao,
            novoSetorId: _setor!.id,
            novaEscalaId: _semEscala ? null : _escala!.id,
            dataTransicao: civilDateFromInput(_data.text),
          );
      if (mounted && _sessaoValida) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted || !_sessaoValida) return;
      final mensagem = error is RepositoryFailure
          ? error.message
          : 'Não foi possível mudar a alocação.';
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

  @override
  Widget build(BuildContext context) {
    final sessao = ref.watch(authProvider).asData?.value;
    final enabled = !_salvando && _sessaoValida;
    final colors = Theme.of(context).colorScheme;
    final gestor = sessao?.user.role == UserRole.gestor;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: !_salvando,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Mudar Escala/Setor'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Fixo acima da área rolável: o aviso permanece visível durante a edição.
              if (gestor)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: escuro
                          ? const Color(0xFF3D2F18)
                          : const Color(0xFFFFF3D6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD49B36)),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            ((MediaQuery.sizeOf(context).height -
                                        MediaQuery.viewInsetsOf(context)
                                            .bottom) *
                                    0.25)
                                .clamp(48, 180)
                                .toDouble(),
                      ),
                      child: SingleChildScrollView(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: escuro
                                  ? const Color(0xFFFFD18A)
                                  : const Color(0xFF805000),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '⚠️ Atenção Gestor: A alteração de escala ou setor impacta diretamente o cálculo do espelho de ponto e horas extras. Certifique-se de alinhar esta mudança com o RH.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: escuro
                                      ? const Color(0xFFFFE3B5)
                                      : const Color(0xFF684000),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.funcionarioNome,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('Setor atual: ${widget.setorNome}'),
                        const SizedBox(height: 8),
                        const Text(
                          'O vínculo anterior será encerrado no dia anterior à mudança. O histórico será preservado.',
                        ),
                        const SizedBox(height: 24),
                        BuscaAssincrona<OpcaoMudancaAlocacao>(
                          inputId: 'mudanca-setor',
                          titulo: 'Novo setor',
                          hint: 'Selecione ou busque um setor',
                          validationMessage: 'Selecione um setor da lista.',
                          icon: Icons.location_on_outlined,
                          enabled: enabled,
                          buscar: (q, cancel) => ref
                              .read(mudancaAlocacaoRepositoryProvider)
                              .opcoesMudanca('setor', q, cancelToken: cancel),
                          label: (item) => item.nome,
                          onChanged: (value) => _setor = value,
                        ),
                        const SizedBox(height: 20),
                        if (!_semEscala)
                          BuscaAssincrona<OpcaoMudancaAlocacao>(
                            inputId: 'mudanca-escala',
                            titulo: 'Nova escala',
                            hint: 'Selecione ou busque uma escala',
                            validationMessage: 'Selecione uma escala da lista.',
                            icon: Icons.calendar_month_outlined,
                            enabled: enabled,
                            buscar: (q, cancel) => ref
                                .read(mudancaAlocacaoRepositoryProvider)
                                .opcoesMudanca(
                                  'escala',
                                  q,
                                  cancelToken: cancel,
                                ),
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
                        Text(
                          'Data efetiva da mudança',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('mudanca-data'),
                          controller: _data,
                          enabled: enabled,
                          keyboardType: TextInputType.datetime,
                          validator: _validarData,
                          decoration: InputDecoration(
                            hintText: 'DD/MM/AAAA',
                            suffixIcon: IconButton(
                              tooltip: 'Selecionar data',
                              onPressed: enabled ? _selecionarData : null,
                              icon: const Icon(Icons.calendar_today_outlined),
                            ),
                          ),
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _salvando ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const Key('mudanca-confirmar'),
            onPressed: enabled ? _salvar : null,
            icon: _salvando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz),
            label: Text(_salvando ? 'Salvando…' : 'Salvar mudança'),
          ),
        ],
      ),
    );
  }
}
