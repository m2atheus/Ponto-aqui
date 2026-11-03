import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth_session.dart';
import '../../models/funcionario.dart';
import '../../models/w06.dart' show SetorResumo;
import '../../providers/auth_provider.dart';
import '../../providers/w06_provider.dart';
import '../../repositories/dispositivo_repository.dart';
import '../../repositories/repository_failure.dart';
import '../widgets/w06_widgets.dart';
import 'aparelho_card.dart';

class DispositivosFuncionarioDialog extends StatelessWidget {
  const DispositivosFuncionarioDialog({super.key, required this.funcionario});
  final Funcionario funcionario;

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
    title: Row(
      children: [
        Icon(
          Icons.devices_outlined,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Aparelhos / Segurança',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: 760,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                    foregroundColor: Theme.of(context)
                        .colorScheme
                        .onSecondaryContainer,
                    child: const Icon(Icons.person_outline),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          funcionario.nome,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Matrícula ${funcionario.matricula} · ${funcionario.cargo ?? 'Cargo não informado'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            DispositivosFuncionarioSection(
              key: ValueKey('aparelhos-${funcionario.id}'),
              funcionario: funcionario,
              exibirTitulo: false,
            ),
          ],
        ),
      ),
    ),
    actions: [
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          textStyle: TextStyle(
            fontFamily: Theme.of(context).textTheme.labelLarge?.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: () => Navigator.pop(context),
        child: const Text('Fechar'),
      ),
    ],
  );
}

class DispositivosFuncionarioSection extends ConsumerStatefulWidget {
  const DispositivosFuncionarioSection({
    super.key,
    required this.funcionario,
    this.exibirTitulo = true,
  });
  final Funcionario funcionario;
  final bool exibirTitulo;
  @override
  ConsumerState<DispositivosFuncionarioSection> createState() =>
      _DispositivosFuncionarioSectionState();
}

class _DispositivosFuncionarioSectionState
    extends ConsumerState<DispositivosFuncionarioSection> {
  CancelToken? _cancel;
  DispositivosData? _dados;
  String? _erro;
  bool _carregando = false;
  bool _operando = false;
  bool _revogando = false;
  late final String? _token;
  bool get _sessaoValida {
    if (!mounted) return false;
    final sessao = ref.read(authProvider).asData?.value;
    return mounted &&
        sessao != null &&
        !sessao.isMock &&
        sessao.accessToken == _token &&
        sessao.expiresAt.isAfter(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    _token = ref.read(authProvider).asData?.value?.accessToken;
    _carregar();
  }

  @override
  void dispose() {
    _cancel?.cancel('Detalhes encerrados.');
    super.dispose();
  }

  Future<void> _carregar() async {
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dados = await ref
          .read(dispositivoRepositoryProvider)
          .listar(widget.funcionario.id, cancelToken: cancel);
      if (_sessaoValida && !cancel.isCancelled) setState(() => _dados = dados);
    } catch (error) {
      if (_sessaoValida && !cancel.isCancelled) {
        setState(() => _erro = w06Error(error));
      }
    } finally {
      if (mounted && !cancel.isCancelled) setState(() => _carregando = false);
    }
  }

  Future<void> _autorizar() async {
    if (_operando ||
        _carregando ||
        !_sessaoValida ||
        _dados?.temAcessoApp != true) {
      return;
    }
    setState(() => _operando = true);
    try {
      final salvo = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => AutorizarAparelhoDialog(
          funcionarioId: widget.funcionario.id,
          repository: ref.read(dispositivoRepositoryProvider),
          setores: _dados!.setores,
          sessaoValida: () => _sessaoValida,
        ),
      );
      if (mounted && salvo == true && _sessaoValida) {
        w06Message(context, 'Aparelho autorizado com sucesso.');
        await _carregar();
      }
    } catch (error) {
      if (mounted && _sessaoValida) {
        w06Message(context, w06Error(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _operando = false);
    }
  }

  Future<void> _revogar(DispositivoFuncionario aparelho) async {
    if (_operando || _carregando || !_sessaoValida) return;
    setState(() => _operando = true);
    try {
      final confirmar = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (_) => AlertDialog(
          title: const Text('Revogar acesso ao aparelho?'),
          content: Text(
            aparelho.tipo == TipoAparelho.relogio
                ? 'Somente o acesso de ${widget.funcionario.nome} a este relógio será revogado. Os demais funcionários permanecem autorizados.'
                : 'Este aparelho não poderá enviar novas marcações. O histórico será preservado.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Revogar acesso'),
            ),
          ],
        ),
      );
      if (confirmar != true || !_sessaoValida) return;
      setState(() => _revogando = true);
      await ref
          .read(dispositivoRepositoryProvider)
          .revogar(widget.funcionario.id, aparelho.id);
      if (mounted && _sessaoValida) {
        w06Message(context, 'Acesso ao aparelho revogado.');
        await _carregar();
      }
    } catch (error) {
      if (mounted && _sessaoValida) {
        w06Message(context, w06Error(error), error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _operando = false;
          _revogando = false;
        });
      }
    }
  }

  Future<void> _copiar(String texto) async {
    try {
      await Clipboard.setData(ClipboardData(text: texto));
      if (mounted && _sessaoValida) w06Message(context, 'Código copiado.');
    } catch (_) {
      if (mounted && _sessaoValida) {
        w06Message(context, 'Não foi possível copiar o código.', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessao = ref.watch(authProvider).asData?.value;
    if (!_sessaoValida) {
      return const Text('Entre novamente para consultar os aparelhos.');
    }
    final rh = sessao?.user.role == UserRole.rh;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.exibirTitulo) ...[
          Text(
            'Aparelhos / Segurança',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Gerencie os aparelhos autorizados para este funcionário.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (_carregando || _revogando) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
        ],
        if (_erro != null) ...[
          Text(_erro!, style: TextStyle(color: colors.error)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _carregando || _operando ? null : _carregar,
              child: const Text('Tentar novamente'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_dados case final dados?) ...[
          if (!dados.temAcessoApp)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Gere o acesso ao aplicativo para este funcionário antes de autorizar aparelhos.',
              ),
            ),
          if (rh) ...[
            LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: constraints.maxWidth < 480 ? double.infinity : null,
                  child: FilledButton.icon(
                    key: const Key('autorizar-aparelho'),
                    onPressed: !dados.temAcessoApp || _carregando || _operando
                        ? null
                        : _autorizar,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      textStyle: TextStyle(
                        fontFamily: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.add_to_home_screen, size: 20),
                    label: const Text('Autorizar Novo Aparelho'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (dados.dispositivos.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.devices_other_outlined,
                      size: 32,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Nenhum aparelho vinculado a este funcionário.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Solicite o código exibido na tela de entrada do aplicativo.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          for (final aparelho in dados.dispositivos)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AparelhoCard(
                key: ValueKey('aparelho-card-${aparelho.id}'),
                aparelho: aparelho,
                podeGerenciar: rh,
                copiarCodigo: () => _copiar(aparelho.deviceUuid),
                copiarId: () => _copiar(aparelho.id),
                revogar: !aparelho.ativo || _carregando || _operando
                    ? null
                    : () => _revogar(aparelho),
              ),
            ),
        ],
      ],
    );
  }
}

class AutorizarAparelhoDialog extends StatefulWidget {
  const AutorizarAparelhoDialog({
    super.key,
    required this.funcionarioId,
    required this.repository,
    required this.setores,
    required this.sessaoValida,
  });
  final String funcionarioId;
  final DispositivoRepository repository;
  final List<SetorResumo> setores;
  final bool Function() sessaoValida;
  @override
  State<AutorizarAparelhoDialog> createState() =>
      _AutorizarAparelhoDialogState();
}

class _AutorizarAparelhoDialogState extends State<AutorizarAparelhoDialog> {
  final _form = GlobalKey<FormState>();
  final _codigo = TextEditingController();
  final _nome = TextEditingController();
  TipoAparelho _tipo = TipoAparelho.pessoal;
  String? _setorId;
  bool _salvando = false;
  bool _confirmando = false;
  bool get _bloqueado => _salvando || _confirmando;
  @override
  void initState() {
    super.initState();
    if (widget.setores.length == 1) _setorId = widget.setores.single.id;
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nome.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_bloqueado || !_form.currentState!.validate()) return;
    if (!widget.sessaoValida()) {
      w06Message(
        context,
        'A sessão foi alterada. Entre novamente.',
        error: true,
      );
      return;
    }
    var converter = false;
    for (var tentativa = 0; tentativa < 2; tentativa++) {
      setState(() => _salvando = true);
      try {
        await widget.repository.vincular(
          widget.funcionarioId,
          deviceUuid: _codigo.text,
          tipo: _tipo,
          nome: _nome.text,
          setorId: _tipo == TipoAparelho.relogio ? _setorId : null,
          converterParaRelogio: converter,
        );
        if (mounted) Navigator.pop(context, widget.sessaoValida());
        return;
      } catch (error) {
        if (!mounted || !widget.sessaoValida()) return;
        if (!converter &&
            _tipo == TipoAparelho.relogio &&
            error is RepositoryFailure &&
            error.code == 'CONVERSAO_RELOGIO_NECESSARIA') {
          setState(() {
            _salvando = false;
            _confirmando = true;
          });
          final confirmado = await _confirmarConversao();
          if (!mounted || !widget.sessaoValida()) return;
          setState(() => _confirmando = false);
          if (confirmado != true) return;
          converter = true;
          continue;
        }
        w06Message(context, w06Error(error), error: true);
        return;
      } finally {
        if (mounted) {
          setState(() {
            _salvando = false;
            _confirmando = false;
          });
        }
      }
    }
  }

  Future<bool?> _confirmarConversao() {
    final setor =
        widget.setores.where((s) => s.id == _setorId).firstOrNull?.nome ??
        'setor selecionado';
    return showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Converter para Relógio Compartilhado?'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Text(
              'Este código já está cadastrado como aparelho pessoal.\n\n'
              'Ele passará a ser um relógio compartilhado com uma autorização para o setor $setor. '
              'O histórico e os acessos ativos do usuário atual serão preservados nos setores onde ele já está alocado. '
              'Vínculos revogados não serão reativados.\n\n'
              'Será necessário entrar novamente no aplicativo para carregar o modo compartilhado.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('aparelho-confirmar-conversao'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Converter e autorizar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_bloqueado,
    child: AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Autorizar Novo Aparelho'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Código do aparelho',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                // Mobile: exibir device_uuid da instalação no login e enviá-lo ao /auth/login.
                // É um identificador público; a senha e a autorização do RH continuam obrigatórias.
                TextFormField(
                  key: const Key('aparelho-codigo'),
                  controller: _codigo,
                  enabled: !_bloqueado,
                  decoration: const InputDecoration(
                    hintText: 'UUID exibido no aplicativo',
                  ),
                  validator: (v) =>
                      RegExp(
                        r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
                      ).hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Informe o UUID completo exibido no aplicativo.',
                ),
                const SizedBox(height: 16),
                const Text('Nome identificador (opcional)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nome,
                  enabled: !_bloqueado,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    hintText: 'Ex.: Celular da Portaria',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Tipo de aparelho'),
                const SizedBox(height: 8),
                DropdownButtonFormField<TipoAparelho>(
                  key: const Key('aparelho-tipo'),
                  initialValue: _tipo,
                  isExpanded: true,
                  items: [
                    for (final tipo in TipoAparelho.values)
                      DropdownMenuItem(value: tipo, child: Text(tipo.label)),
                  ],
                  onChanged: _bloqueado
                      ? null
                      : (v) => setState(() => _tipo = v!),
                ),
                const SizedBox(height: 8),
                Text(
                  _tipo == TipoAparelho.pessoal
                      ? 'Pessoal é exclusivo de um funcionário. Para dividir o mesmo aparelho, selecione Relógio Compartilhado.'
                      : 'O mesmo aparelho pode atender vários setores. Autorizar um setor preserva os demais vínculos. Se o código já for pessoal, será solicitada a confirmação da conversão.',
                ),
                if (_tipo == TipoAparelho.relogio) ...[
                  const SizedBox(height: 16),
                  const Text('Setor para esta autorização'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const Key('aparelho-setor'),
                    initialValue: _setorId,
                    isExpanded: true,
                    items: [
                      for (final setor in widget.setores)
                        DropdownMenuItem(
                          value: setor.id,
                          child: Text(setor.nome),
                        ),
                    ],
                    onChanged: _bloqueado
                        ? null
                        : (v) => setState(() => _setorId = v),
                    validator: (v) => v == null
                        ? 'É necessária uma alocação vigente neste setor.'
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _bloqueado ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          key: const Key('aparelho-salvar'),
          onPressed: _bloqueado ? null : _salvar,
          icon: _salvando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_salvando ? 'Salvando…' : 'Autorizar'),
        ),
      ],
    ),
  );
}
