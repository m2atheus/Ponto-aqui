import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/responsive_table_container.dart';

import '../../models/auth_session.dart';
import '../../models/empresa.dart';
import '../../providers/auth_provider.dart';
import '../../providers/empresas_provider.dart';
import '../../services/empresa_service.dart';
import '../modules/module_placeholder_view.dart';
import '../widgets/status_badge.dart';

class EmpresasScreen extends ConsumerStatefulWidget {
  const EmpresasScreen({super.key, this.abrirCadastro = false});
  final bool abrirCadastro;
  @override
  ConsumerState<EmpresasScreen> createState() => _EmpresasScreenState();
}

class _EmpresasScreenState extends ConsumerState<EmpresasScreen> {
  final _scroll = ScrollController();
  bool _desativando = false;
  @override
  void initState() {
    super.initState();
    if (widget.abrirCadastro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _formulario();
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _formulario([Empresa? empresa]) async {
    final session = ref.read(authProvider).asData?.value;
    if (session == null || session.isMock) return;
    final resultado = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => _EmpresaDialog(
        empresa: empresa,
        existentes: ref.read(empresasProvider).asData?.value ?? [],
      ),
    );
    if (!mounted ||
        resultado != true ||
        ref.read(authProvider).asData?.value?.accessToken !=
            session.accessToken) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Empresa salva no banco de dados.')),
    );
  }

  Future<void> _desativar(Empresa empresa) async {
    final token = ref.read(authProvider).asData?.value?.accessToken;
    final confirmar = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Desativar empresa?'),
        content: Text(
          'Desativar ${empresa.razaoSocial}? O cadastro será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (mounted &&
        confirmar == true &&
        ref.read(authProvider).asData?.value?.accessToken == token) {
      setState(() => _desativando = true);
      try {
        await ref.read(empresasProvider.notifier).desativar(empresa);
      } on EmpresaFailure catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
      } finally {
        if (mounted) setState(() => _desativando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authProvider).asData?.value?.user.role !=
        UserRole.superadmin) {
      return const ModulePlaceholderView(
        title: 'Acesso negado',
        message: 'Esta área é exclusiva do Superadmin.',
      );
    }
    final dados = ref.watch(empresasProvider);
    final empresas = dados.asData?.value ?? <Empresa>[];
    final podeGravar =
        ref.watch(authProvider).asData?.value?.isMock == false &&
        !dados.isLoading &&
        !dados.hasError &&
        !_desativando;
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
                'Empresas',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              FilledButton.icon(
                onPressed: podeGravar ? _formulario : null,
                icon: const Icon(Icons.add),
                label: const Text('Nova Empresa'),
              ),
              IconButton(
                tooltip: 'Atualizar empresas',
                onPressed: dados.isLoading || _desativando
                    ? null
                    : () => ref.invalidate(empresasProvider),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Empresas cadastradas no banco de dados.'),
          const SizedBox(height: 24),
          if (dados.isLoading) const LinearProgressIndicator(),
          if (dados.hasError)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                dados.error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Card(
            child: ResponsiveTableContainer(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 12),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Razão Social')),
                  DataColumn(label: Text('CNPJ')),
                  DataColumn(label: Text('Administrador/RH')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Ações')),
                ],
                rows: [
                  for (final empresa in empresas)
                    DataRow(
                      key: ValueKey(empresa.id),
                      cells: [
                        DataCell(Text(empresa.razaoSocial)),
                        DataCell(Text(empresa.cnpjFormatado)),
                        DataCell(Text(empresa.adminEmail)),
                        DataCell(StatusBadge(ativo: empresa.ativa)),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('editar-empresa-${empresa.id}'),
                                tooltip: 'Editar ${empresa.razaoSocial}',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: podeGravar
                                    ? () => _formulario(empresa)
                                    : null,
                              ),
                              IconButton(
                                key: Key('desativar-empresa-${empresa.id}'),
                                tooltip: 'Desativar ${empresa.razaoSocial}',
                                icon: const Icon(Icons.block),
                                onPressed: empresa.ativa && podeGravar
                                    ? () => _desativar(empresa)
                                    : null,
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
          if (empresas.isEmpty && !dados.isLoading && !dados.hasError)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhuma empresa cadastrada.'),
            ),
        ],
      ),
    );
  }
}

class _EmpresaDialog extends ConsumerStatefulWidget {
  const _EmpresaDialog({this.empresa, required this.existentes});
  final Empresa? empresa;
  final List<Empresa> existentes;
  @override
  ConsumerState<_EmpresaDialog> createState() => _EmpresaDialogState();
}

class _EmpresaDialogState extends ConsumerState<_EmpresaDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _cnpj;
  late final TextEditingController _email;
  late final TextEditingController _adminNome;
  final _senha = TextEditingController();
  bool _salvando = false;
  String? _erro;
  late bool _ativa;
  @override
  void initState() {
    super.initState();
    _nome = TextEditingController(text: widget.empresa?.razaoSocial ?? '');
    _cnpj = TextEditingController(text: widget.empresa?.cnpjFormatado ?? '');
    _email = TextEditingController(text: widget.empresa?.adminEmail ?? '');
    _adminNome = TextEditingController(text: widget.empresa?.adminNome ?? '');
    _ativa = widget.empresa?.ativa ?? true;
  }

  @override
  void dispose() {
    _nome.dispose();
    _cnpj.dispose();
    _email.dispose();
    _adminNome.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || !_form.currentState!.validate()) return;
    final token = ref.read(authProvider).asData?.value?.accessToken;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref
          .read(empresasProvider.notifier)
          .salvar(
            Empresa(
              id: widget.empresa?.id ?? '',
              razaoSocial: _nome.text.trim(),
              cnpj: _cnpj.text.replaceAll(RegExp(r'\D'), ''),
              adminEmail: _email.text.trim().toLowerCase(),
              adminNome: _adminNome.text.trim(),
              ativa: _ativa,
            ),
            senhaInicial: _senha.text.isEmpty ? null : _senha.text,
          );
      if (mounted &&
          ref.read(authProvider).asData?.value?.accessToken == token) {
        Navigator.pop(context, true);
      }
    } on EmpresaFailure catch (error) {
      if (mounted) setState(() => _erro = error.message);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.empresa == null ? 'Nova Empresa' : 'Editar Empresa'),
    scrollable: true,
    content: SizedBox(
      width: 480,
      child: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('empresa-nome'),
              enabled: !_salvando,
              controller: _nome,
              maxLength: 200,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Razão Social'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe a razão social.'
                  : null,
            ),
            TextFormField(
              key: const Key('empresa-cnpj'),
              enabled: !_salvando,
              controller: _cnpj,
              maxLength: 18,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9./-]')),
              ],
              decoration: const InputDecoration(labelText: 'CNPJ'),
              validator: (value) {
                final cnpj = (value ?? '').replaceAll(RegExp(r'\D'), '');
                if (cnpj.length != 14) return 'Informe os 14 dígitos do CNPJ.';
                if (widget.existentes.any(
                  (item) => item.id != widget.empresa?.id && item.cnpj == cnpj,
                )) {
                  return 'CNPJ já cadastrado.';
                }
                return null;
              },
            ),
            TextFormField(
              key: const Key('empresa-admin-nome'),
              controller: _adminNome,
              enabled: !_salvando,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Nome do Administrador/RH',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe o nome do RH.'
                  : null,
            ),
            TextFormField(
              key: const Key('empresa-email'),
              enabled: !_salvando,
              controller: _email,
              maxLength: 254,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _salvar(),
              decoration: const InputDecoration(
                labelText: 'E-mail do Administrador/RH',
              ),
              validator: (value) =>
                  value == null ||
                      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                          .hasMatch(value.trim())
                  ? 'Informe um e-mail válido.'
                  : null,
            ),
            TextFormField(
              key: const Key('empresa-admin-senha'),
              controller: _senha,
              obscureText: true,
              enabled: !_salvando,
              maxLength: 1024,
              decoration: InputDecoration(
                labelText:
                    widget.empresa == null || widget.empresa!.adminEmail.isEmpty
                    ? 'Senha inicial do RH'
                    : 'Nova senha do RH (opcional)',
              ),
              validator: (value) =>
                  ((widget.empresa == null ||
                          widget.empresa!.adminEmail.isEmpty ||
                          (value ?? '').isNotEmpty) &&
                      (value ?? '').length < 8)
                  ? 'Use uma senha com pelo menos 8 caracteres.'
                  : null,
            ),
            if (_erro != null)
              Text(
                _erro!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Empresa ativa'),
              value: _ativa,
              onChanged: _salvando
                  ? null
                  : (value) => setState(() => _ativa = value ?? true),
            ),
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
  );
}
