import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/auth_session.dart';
import '../../models/w06.dart';
import '../../providers/auth_provider.dart';
import '../../providers/w06_provider.dart';
import '../../utils/civil_date.dart';
import '../widgets/w06_widgets.dart';

class JustificativasScreen extends ConsumerStatefulWidget {
  const JustificativasScreen({super.key});
  @override
  ConsumerState<JustificativasScreen> createState() =>
      _JustificativasScreenState();
}

class _JustificativasScreenState extends ConsumerState<JustificativasScreen> {
  bool _dialogAberto = false;
  Future<void> _cadastrar(
    W06Data data, {
    required bool feriado,
    FeriadoResumo? itemFeriado,
    AfastamentoResumo? itemAfastamento,
  }) async {
    final session = ref.read(authProvider).asData?.value;
    if (_dialogAberto || session?.user.role != UserRole.rh) return;
    setState(() => _dialogAberto = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => _CadastroDialog(
          data: data,
          feriado: feriado,
          sessionToken: session!.accessToken,
          itemFeriado: itemFeriado,
          itemAfastamento: itemAfastamento,
        ),
      );
      if (mounted &&
          saved == true &&
          ref.read(authProvider).asData?.value?.accessToken ==
              session!.accessToken) {
        w06Message(context, 'Cadastro salvo no banco.');
      }
    } finally {
      if (mounted) setState(() => _dialogAberto = false);
    }
  }

  Future<void> _remover(
    String id,
    String label, {
    required bool feriado,
  }) async {
    final session = ref.read(authProvider).asData?.value;
    if (_dialogAberto ||
        session == null ||
        session.isMock ||
        session.user.role != UserRole.rh) {
      return;
    }
    setState(() => _dialogAberto = true);
    try {
      final confirmar = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text('Remover ${feriado ? 'feriado' : 'afastamento'}?'),
          content: Text(
            'Remover "$label"? O período deixará de abonar a jornada nos relatórios.',
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
          confirmar != true ||
          ref.read(authProvider).asData?.value?.accessToken !=
              session.accessToken) {
        return;
      }
      await ref
          .read(w06Provider.notifier)
          .salvar(
            (r) => feriado ? r.removerFeriado(id) : r.removerAfastamento(id),
          );
      if (mounted &&
          ref.read(authProvider).asData?.value?.accessToken ==
              session.accessToken) {
        w06Message(context, 'Registro removido do banco.');
      }
    } catch (error) {
      if (mounted) w06Message(context, w06Error(error), error: true);
    } finally {
      if (mounted) setState(() => _dialogAberto = false);
    }
  }

  Future<void> _baixar(AfastamentoResumo afastamento) async {
    if (_dialogAberto) return;
    final token = ref.read(authProvider).asData?.value?.accessToken;
    setState(() => _dialogAberto = true);
    try {
      final anexo = await ref
          .read(w06RepositoryProvider)
          .baixarAnexo(afastamento.id);
      if (!mounted ||
          ref.read(authProvider).asData?.value?.accessToken != token) {
        return;
      }
      await FilePicker.saveFile(
        fileName: anexo.nome,
        bytes: anexo.bytes,
        mimeType: anexo.mime,
      );
    } catch (error) {
      if (mounted) w06Message(context, w06Error(error), error: true);
    } finally {
      if (mounted) setState(() => _dialogAberto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final podeCadastrar =
        ref.watch(authProvider).asData?.value?.user.role == UserRole.rh;
    return W06Content(
      path: '/justificativas',
      builder: (data) => DefaultTabController(
        length: 2,
        child: W06PageLayout(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Justificativas e ajustes',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Gerencie feriados e afastamentos que justificam a jornada.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _dialogAberto
                    ? null
                    : () => ref.invalidate(w06Provider),
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar dados'),
              ),
              if (!podeCadastrar)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Consulta da equipe · Cadastros são realizados pelo RH.',
                  ),
                ),
              const TabBar(
                tabs: [
                  Tab(text: 'Feriados'),
                  Tab(text: 'Afastamentos'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  children: [
                    _abaFeriados(data, podeCadastrar),
                    _abaAfastamentos(data, podeCadastrar),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _abaFeriados(W06Data data, bool editar) {
    final feriados = [...data.feriados]
      ..sort((a, b) => a.data.compareTo(b.data));
    return ListView(
      children: [
        if (editar)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('novo-feriado'),
              onPressed: _dialogAberto
                  ? null
                  : () => _cadastrar(data, feriado: true),
              icon: const Icon(Icons.add),
              label: const Text('Novo Feriado'),
            ),
          ),
        const SizedBox(height: 16),
        W06Table(
          emptyMessage: 'Nenhum feriado cadastrado.',
          columns: [
            DataColumn(label: Text('Data')),
            DataColumn(label: Text('Descrição')),
            DataColumn(label: Text('Abrangência')),
            if (editar) const DataColumn(label: Text('Ações')),
          ],
          rows: [
            for (final f in feriados)
              DataRow(
                cells: [
                  DataCell(Text(civilDateDisplay(f.data))),
                  DataCell(
                    SizedBox(
                      width: 220,
                      child: Text(
                        f.descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text(data.setorNome(f.setorId))),
                  if (editar)
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: ValueKey('editar-feriado-${f.id}'),
                            tooltip: 'Editar feriado',
                            onPressed: _dialogAberto
                                ? null
                                : () => _cadastrar(
                                    data,
                                    feriado: true,
                                    itemFeriado: f,
                                  ),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            key: ValueKey('remover-feriado-${f.id}'),
                            tooltip: 'Remover feriado',
                            onPressed: _dialogAberto
                                ? null
                                : () => _remover(
                                    f.id,
                                    f.descricao,
                                    feriado: true,
                                  ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _abaAfastamentos(W06Data data, bool editar) {
    final afastamentos = [...data.afastamentos]
      ..sort((a, b) => b.inicio.compareTo(a.inicio));
    return ListView(
      children: [
        if (editar)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('novo-afastamento'),
              onPressed: _dialogAberto || !data.funcionarios.any((f) => f.ativo)
                  ? null
                  : () => _cadastrar(data, feriado: false),
              icon: const Icon(Icons.add),
              label: const Text('Novo Afastamento'),
            ),
          ),
        const SizedBox(height: 16),
        W06Table(
          emptyMessage: 'Nenhum afastamento cadastrado.',
          columns: [
            DataColumn(label: Text('Funcionário')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Início')),
            DataColumn(label: Text('Fim')),
            DataColumn(label: Text('Anexo')),
            if (editar) const DataColumn(label: Text('Ações')),
          ],
          rows: [
            for (final a in afastamentos)
              DataRow(
                cells: [
                  DataCell(Text(data.funcionarioNome(a.funcionarioId))),
                  DataCell(Text(a.tipo.label)),
                  DataCell(Text(civilDateDisplay(a.inicio))),
                  DataCell(Text(civilDateDisplay(a.fim))),
                  DataCell(
                    a.anexoUrl == null
                        ? const Text('—')
                        : IconButton(
                            key: ValueKey('baixar-anexo-${a.id}'),
                            tooltip: 'Baixar atestado',
                            onPressed: _dialogAberto ? null : () => _baixar(a),
                            icon: const Icon(Icons.download_outlined),
                          ),
                  ),
                  if (editar)
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: ValueKey('editar-afastamento-${a.id}'),
                            tooltip: 'Editar afastamento',
                            onPressed: _dialogAberto
                                ? null
                                : () => _cadastrar(
                                    data,
                                    feriado: false,
                                    itemAfastamento: a,
                                  ),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            key: ValueKey('remover-afastamento-${a.id}'),
                            tooltip: 'Remover afastamento',
                            onPressed: _dialogAberto
                                ? null
                                : () => _remover(
                                    a.id,
                                    data.funcionarioNome(a.funcionarioId),
                                    feriado: false,
                                  ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _CadastroDialog extends ConsumerStatefulWidget {
  const _CadastroDialog({
    required this.data,
    required this.feriado,
    required this.sessionToken,
    this.itemFeriado,
    this.itemAfastamento,
  });
  final W06Data data;
  final bool feriado;
  final String sessionToken;
  final FeriadoResumo? itemFeriado;
  final AfastamentoResumo? itemAfastamento;
  @override
  ConsumerState<_CadastroDialog> createState() => _CadastroDialogState();
}

class _CadastroDialogState extends ConsumerState<_CadastroDialog> {
  final _form = GlobalKey<FormState>();
  final _descricao = TextEditingController();
  final _inicio = TextEditingController();
  final _fim = TextEditingController();
  String _setorId = 'empresa';
  String? _funcionarioId;
  TipoAfastamento _tipo = TipoAfastamento.atestado;
  AnexoLocal? _anexo;
  bool _removerAnexo = false;
  bool _salvando = false;
  bool _selecionando = false;
  String? _erro;
  bool get _ocupado => _salvando || _selecionando;
  bool get _mesmaSessao =>
      mounted &&
      ref.read(authProvider).asData?.value?.accessToken ==
          widget.sessionToken &&
      ref.read(authProvider).asData?.value?.user.role == UserRole.rh;

  @override
  void initState() {
    super.initState();
    final f = widget.itemFeriado, a = widget.itemAfastamento;
    if (f != null) {
      _descricao.text = f.descricao;
      _inicio.text = civilDateDisplay(f.data);
      _setorId = f.setorId ?? 'empresa';
    }
    if (a != null) {
      _funcionarioId = a.funcionarioId;
      _tipo = a.tipo;
      _inicio.text = civilDateDisplay(a.inicio);
      _fim.text = civilDateDisplay(a.fim);
    }
  }

  @override
  void dispose() {
    _descricao.dispose();
    _inicio.dispose();
    _fim.dispose();
    super.dispose();
  }

  void _falha(Object error) {
    final message = w06Error(error);
    setState(() => _erro = message);
    w06Message(context, message, error: true);
  }

  Future<void> _selecionar() async {
    if (_ocupado || !_mesmaSessao) return;
    setState(() {
      _selecionando = true;
      _erro = null;
    });
    try {
      final anexo = await ref.read(selecionarAtestadoProvider)();
      if (_mesmaSessao && anexo != null) setState(() => _anexo = anexo);
    } catch (error) {
      if (_mesmaSessao) _falha(error);
    } finally {
      if (mounted) setState(() => _selecionando = false);
    }
  }

  Future<void> _salvar() async {
    if (_ocupado || !_mesmaSessao || !_form.currentState!.validate()) return;
    final inicio = civilDateFromInput(_inicio.text);
    final fim = widget.feriado ? inicio : civilDateFromInput(_fim.text);
    if (fim.compareTo(inicio) < 0) {
      setState(() => _erro = 'O fim deve ser igual ou posterior ao início.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref
          .read(w06Provider.notifier)
          .salvar(
            (repository) => widget.feriado
                ? repository.salvarFeriado(
                    id: widget.itemFeriado?.id,
                    data: inicio,
                    descricao: _descricao.text,
                    setorId: _setorId == 'empresa' ? null : _setorId,
                  )
                : repository.salvarAfastamento(
                    id: widget.itemAfastamento?.id,
                    funcionarioId: _funcionarioId!,
                    tipo: _tipo,
                    inicio: inicio,
                    fim: fim,
                    anexo: _anexo,
                    removerAnexo: _removerAnexo,
                  ),
          );
      if (mounted && _mesmaSessao) Navigator.pop(context, true);
    } catch (error) {
      if (_mesmaSessao) _falha(error);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_ocupado,
    child: AlertDialog(
      title: Text(
        widget.feriado
            ? (widget.itemFeriado == null ? 'Novo Feriado' : 'Editar Feriado')
            : (widget.itemAfastamento == null
                  ? 'Novo Afastamento'
                  : 'Editar Afastamento'),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.feriado) ...[
                  TextFormField(
                    key: const Key('feriado-descricao'),
                    controller: _descricao,
                    enabled: !_ocupado,
                    maxLength: 255,
                    decoration: const InputDecoration(labelText: 'Descrição'),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Informe a descrição.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('feriado-setor'),
                    initialValue: _setorId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Abrangência'),
                    items: [
                      const DropdownMenuItem(
                        value: 'empresa',
                        child: Text('Empresa inteira'),
                      ),
                      for (final s in widget.data.setores)
                        DropdownMenuItem(value: s.id, child: Text(s.nome)),
                    ],
                    onChanged: _ocupado
                        ? null
                        : (v) => setState(() => _setorId = v!),
                  ),
                ] else ...[
                  DropdownButtonFormField<String>(
                    key: const Key('afastamento-funcionario'),
                    initialValue: _funcionarioId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Funcionário'),
                    items: [
                      for (final f in widget.data.funcionarios.where(
                        (f) =>
                            f.ativo ||
                            f.id == widget.itemAfastamento?.funcionarioId,
                      ))
                        DropdownMenuItem(
                          value: f.id,
                          child: Text(
                            '${f.nome} · ${f.matricula}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _ocupado || widget.itemAfastamento != null
                        ? null
                        : (v) => setState(() => _funcionarioId = v),
                    validator: (v) =>
                        v == null ? 'Selecione um funcionário.' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TipoAfastamento>(
                    key: const Key('afastamento-tipo'),
                    initialValue: _tipo,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: [
                      for (final t in TipoAfastamento.values)
                        DropdownMenuItem(value: t, child: Text(t.label)),
                    ],
                    onChanged: _ocupado
                        ? null
                        : (v) => setState(() => _tipo = v!),
                  ),
                ],
                const SizedBox(height: 16),
                W06DateField(
                  key: const Key('w06-inicio'),
                  controller: _inicio,
                  label: widget.feriado ? 'Data' : 'Início',
                  enabled: !_ocupado,
                ),
                if (!widget.feriado) ...[
                  const SizedBox(height: 16),
                  W06DateField(
                    key: const Key('w06-fim'),
                    controller: _fim,
                    label: 'Fim',
                    enabled: !_ocupado,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const Key('anexar-atestado'),
                    onPressed: _ocupado ? null : _selecionar,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      _selecionando ? 'Selecionando…' : 'Anexar Arquivo',
                    ),
                  ),
                  const Text(
                    'PDF, PNG ou JPG · Até 10 MB. O arquivo será enviado ao salvar.',
                  ),
                  if (_anexo != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_anexo!.nome),
                      subtitle: Text(
                        '${(_anexo!.tamanho / 1024).ceil()} KB · Pronto para envio',
                      ),
                      trailing: IconButton(
                        tooltip: 'Remover anexo',
                        onPressed: _ocupado
                            ? null
                            : () => setState(() => _anexo = null),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  if (widget.itemAfastamento?.anexoUrl != null &&
                      _anexo == null)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Remover o atestado atual'),
                      value: _removerAnexo,
                      onChanged: _ocupado
                          ? null
                          : (v) => setState(() => _removerAnexo = v!),
                    ),
                ],
                if (_erro != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _erro!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_salvando)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _ocupado ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('w06-salvar'),
          onPressed: _ocupado ? null : _salvar,
          child: Text(_salvando ? 'Salvando…' : 'Salvar'),
        ),
      ],
    ),
  );
}
