import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth_session.dart';
import '../../models/funcionario.dart';
import '../../providers/auth_provider.dart';
import '../../providers/funcionarios_provider.dart';
import '../../repositories/repository_failure.dart';
import '../modules/module_placeholder_view.dart';
import '../widgets/status_badge.dart';
import '../widgets/responsive_table_container.dart';
import 'vincular_acesso_dialog.dart';

class FuncionariosScreen extends ConsumerStatefulWidget {
  const FuncionariosScreen({super.key});
  @override
  ConsumerState<FuncionariosScreen> createState() => _FuncionariosScreenState();
}

class _FuncionariosScreenState extends ConsumerState<FuncionariosScreen> {
  final _scroll = ScrollController();
  bool _dialogAberto = false;
  bool _confirmando = false;
  String? _alterandoStatusId;
  bool get _ocupado =>
      _dialogAberto || _confirmando || _alterandoStatusId != null;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _mesmaSessao(String token) =>
      mounted && ref.read(authProvider).asData?.value?.accessToken == token;

  Future<void> _formulario([Funcionario? funcionario]) async {
    final session = ref.read(authProvider).asData?.value;
    if (_ocupado ||
        session == null ||
        session.isMock ||
        session.user.role != UserRole.rh) {
      return;
    }
    setState(() => _dialogAberto = true);
    try {
      final salvo = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => _FuncionarioDialog(
          funcionario: funcionario,
          empresaId: session.user.companyId!,
          sessionToken: session.accessToken,
        ),
      );
      if (mounted && salvo == true && _mesmaSessao(session.accessToken)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Funcionário salvo com sucesso.')),
        );
      }
    } finally {
      if (mounted) setState(() => _dialogAberto = false);
    }
  }

  Future<void> _vincularAcesso(Funcionario funcionario) async {
    final session = ref.read(authProvider).asData?.value;
    if (_ocupado ||
        session == null ||
        session.isMock ||
        session.user.role != UserRole.rh ||
        session.user.companyId != funcionario.empresaId ||
        !funcionario.ativo ||
        funcionario.temAcessoApp) {
      return;
    }
    setState(() => _dialogAberto = true);
    try {
      final criado = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => VincularAcessoDialog(
          funcionario: funcionario,
          sessionToken: session.accessToken,
        ),
      );
      if (mounted && criado == true && _mesmaSessao(session.accessToken)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF237A48),
            content: Text(
              'Acesso do funcionário ao App gerado com sucesso.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _dialogAberto = false);
    }
  }

  Future<void> _alterarStatus(Funcionario funcionario) async {
    final session = ref.read(authProvider).asData?.value;
    if (_ocupado ||
        session == null ||
        session.isMock ||
        session.user.role != UserRole.rh ||
        session.user.companyId != funcionario.empresaId) {
      return;
    }
    final reativar = !funcionario.ativo;
    final acao = reativar ? 'Reativar' : 'Desativar';
    setState(() => _confirmando = true);
    try {
      final confirmar = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text('$acao funcionário?'),
          content: Text(
            reativar
                ? 'Reativar ${funcionario.nome}? O funcionário voltará a ficar ativo, mantendo seu cadastro e histórico.'
                : 'Desativar ${funcionario.nome}? O cadastro e o histórico serão preservados.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(acao),
            ),
          ],
        ),
      );
      if (!mounted || confirmar != true || !_mesmaSessao(session.accessToken)) {
        return;
      }
      setState(() {
        _confirmando = false;
        _alterandoStatusId = funcionario.id;
      });
      final controller = ref.read(funcionariosProvider.notifier);
      if (reativar) {
        await controller.reativar(funcionario.id);
      } else {
        await controller.desativar(funcionario);
      }
      if (mounted && _mesmaSessao(session.accessToken)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF237A48),
            content: Text(
              reativar ? 'Funcionário reativado.' : 'Funcionário desativado.',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } on RepositoryFailure catch (error) {
      if (mounted && _mesmaSessao(session.accessToken)) {
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
      if (mounted) {
        setState(() {
          _confirmando = false;
          _alterandoStatusId = null;
        });
      }
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
    final dados = ref.watch(funcionariosProvider);
    final podeGravar =
        !session!.isMock && !dados.isLoading && !dados.hasError && !_ocupado;
    final podeAtualizar = !session.isMock && !dados.isLoading && !_ocupado;
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
                'Funcionários',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              FilledButton.icon(
                key: const Key('novo-funcionario'),
                onPressed: podeGravar ? _formulario : null,
                icon: const Icon(Icons.add),
                label: const Text('Novo Funcionário'),
              ),
              IconButton(
                tooltip: 'Atualizar funcionários',
                onPressed: podeAtualizar
                    ? () => ref.invalidate(funcionariosProvider)
                    : null,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Cadastros da sua empresa. Desativar mantém o histórico de trabalho.',
          ),
          const SizedBox(height: 24),
          if (dados.isLoading || _alterandoStatusId != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(),
            ),
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
                          : 'Não foi possível carregar os funcionários.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: podeAtualizar
                          ? () => ref.invalidate(funcionariosProvider)
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          if (dados.asData?.value case final rows?) ...[
            if (rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhum funcionário cadastrado.'),
                ),
              )
            else
              Card(
                child: ResponsiveTableContainer(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Nome')),
                      DataColumn(label: Text('Matrícula')),
                      DataColumn(label: Text('Cargo')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Ações')),
                    ],
                    rows: [
                      for (final funcionario in rows)
                        DataRow(
                          key: ValueKey(funcionario.id),
                          cells: [
                            DataCell(Text(funcionario.nome)),
                            DataCell(Text(funcionario.matricula)),
                            DataCell(
                              Text(
                                funcionario.cargo?.trim().isNotEmpty == true
                                    ? funcionario.cargo!
                                    : '—',
                              ),
                            ),
                            DataCell(StatusBadge(ativo: funcionario.ativo)),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: Key(
                                      'gerar-acesso-app-${funcionario.id}',
                                    ),
                                    tooltip: funcionario.temAcessoApp
                                        ? 'Acesso ao App já gerado'
                                        : 'Gerar Acesso App',
                                    onPressed:
                                        podeGravar &&
                                            funcionario.ativo &&
                                            !funcionario.temAcessoApp
                                        ? () => _vincularAcesso(funcionario)
                                        : null,
                                    icon: Icon(
                                      funcionario.temAcessoApp
                                          ? Icons.verified_user_outlined
                                          : Icons.key_outlined,
                                    ),
                                  ),
                                  IconButton(
                                    key: Key(
                                      'editar-funcionario-${funcionario.id}',
                                    ),
                                    tooltip: 'Editar ${funcionario.nome}',
                                    onPressed: podeGravar
                                        ? () => _formulario(funcionario)
                                        : null,
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    key: Key(
                                      '${funcionario.ativo ? 'desativar' : 'reativar'}-funcionario-${funcionario.id}',
                                    ),
                                    tooltip:
                                        '${funcionario.ativo ? 'Desativar' : 'Reativar'} ${funcionario.nome}',
                                    onPressed: podeGravar
                                        ? () => _alterarStatus(funcionario)
                                        : null,
                                    icon: _alterandoStatusId == funcionario.id
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            funcionario.ativo
                                                ? Icons.person_off_outlined
                                                : Icons
                                                      .person_add_alt_1_outlined,
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
              ),
          ],
        ],
      ),
    );
  }
}

class _FuncionarioDialog extends ConsumerStatefulWidget {
  const _FuncionarioDialog({
    this.funcionario,
    required this.empresaId,
    required this.sessionToken,
  });
  final Funcionario? funcionario;
  final String empresaId;
  final String sessionToken;
  @override
  ConsumerState<_FuncionarioDialog> createState() => _FuncionarioDialogState();
}

class _FuncionarioDialogState extends ConsumerState<_FuncionarioDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _matricula;
  late final TextEditingController _cargo;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _nome = TextEditingController(text: widget.funcionario?.nome ?? '');
    _matricula = TextEditingController(
      text: widget.funcionario?.matricula ?? '',
    );
    _cargo = TextEditingController(text: widget.funcionario?.cargo ?? '');
  }

  @override
  void dispose() {
    _nome.dispose();
    _matricula.dispose();
    _cargo.dispose();
    super.dispose();
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
      await ref
          .read(funcionariosProvider.notifier)
          .salvar(
            Funcionario(
              id: widget.funcionario?.id ?? '',
              nome: _nome.text.trim(),
              matricula: _matricula.text.trim(),
              cargo: _cargo.text.trim().isEmpty ? null : _cargo.text.trim(),
              empresaId: widget.empresaId,
              ativo: widget.funcionario?.ativo ?? true,
            ),
          );
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_salvando,
    child: AlertDialog(
      title: Text(
        widget.funcionario == null ? 'Novo Funcionário' : 'Editar Funcionário',
      ),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('funcionario-nome'),
                controller: _nome,
                enabled: !_salvando,
                maxLength: 150,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o nome.'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('funcionario-matricula'),
                controller: _matricula,
                enabled: !_salvando,
                maxLength: 50,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Matrícula'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe a matrícula.'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('funcionario-cargo'),
                controller: _cargo,
                enabled: !_salvando,
                maxLength: 120,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _salvar(),
                decoration: const InputDecoration(
                  labelText: 'Cargo (opcional)',
                ),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(
                  _erro!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          child: Text(_salvando ? 'Salvando...' : 'Salvar'),
        ),
      ],
    ),
  );
}
