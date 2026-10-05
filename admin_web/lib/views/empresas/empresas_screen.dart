import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth_session.dart';
import '../../models/management_mock.dart';
import '../../providers/auth_provider.dart';
import '../../providers/management_mock_provider.dart';
import '../modules/module_placeholder_view.dart';

class EmpresasScreen extends ConsumerStatefulWidget {
  const EmpresasScreen({super.key, this.abrirCadastro = false});
  final bool abrirCadastro;
  @override
  ConsumerState<EmpresasScreen> createState() => _EmpresasScreenState();
}

class _EmpresasScreenState extends ConsumerState<EmpresasScreen> {
  final _scroll = ScrollController();
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

  Future<void> _formulario([EmpresaMock? empresa]) async {
    final usuarioId = ref.read(authProvider).asData?.value?.user.id;
    final resultado = await showDialog<EmpresaMock>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _EmpresaDialog(
        empresa: empresa,
        existentes: ref.read(empresasMockProvider),
      ),
    );
    if (!mounted ||
        resultado == null ||
        ref.read(authProvider).asData?.value?.user.id != usuarioId) {
      return;
    }
    ref.read(empresasMockProvider.notifier).salvar(resultado);
  }

  Future<void> _desativar(EmpresaMock empresa) async {
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
    if (mounted && confirmar == true) {
      ref.read(empresasMockProvider.notifier).desativar(empresa);
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
    final empresas = ref.watch(empresasMockProvider);
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
                onPressed: _formulario,
                icon: const Icon(Icons.add),
                label: const Text('Nova Empresa'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Dados de demonstração. Alterações ficam em memória até encerrar a sessão ou recarregar a página.',
          ),
          const SizedBox(height: 24),
          Card(
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
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
                          DataCell(Text(empresa.ativa ? 'Ativa' : 'Inativa')),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: Key('editar-empresa-${empresa.id}'),
                                  tooltip: 'Editar ${empresa.razaoSocial}',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _formulario(empresa),
                                ),
                                IconButton(
                                  key: Key('desativar-empresa-${empresa.id}'),
                                  tooltip: 'Desativar ${empresa.razaoSocial}',
                                  icon: const Icon(Icons.block),
                                  onPressed: empresa.ativa
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
          ),
          if (empresas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhuma empresa cadastrada.'),
            ),
        ],
      ),
    );
  }
}

class _EmpresaDialog extends StatefulWidget {
  const _EmpresaDialog({this.empresa, required this.existentes});
  final EmpresaMock? empresa;
  final List<EmpresaMock> existentes;
  @override
  State<_EmpresaDialog> createState() => _EmpresaDialogState();
}

class _EmpresaDialogState extends State<_EmpresaDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _cnpj;
  late final TextEditingController _email;
  late bool _ativa;
  @override
  void initState() {
    super.initState();
    _nome = TextEditingController(text: widget.empresa?.razaoSocial ?? '');
    _cnpj = TextEditingController(text: widget.empresa?.cnpjFormatado ?? '');
    _email = TextEditingController(text: widget.empresa?.adminEmail ?? '');
    _ativa = widget.empresa?.ativa ?? true;
  }

  @override
  void dispose() {
    _nome.dispose();
    _cnpj.dispose();
    _email.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      EmpresaMock(
        id: widget.empresa?.id ?? '',
        razaoSocial: _nome.text.trim(),
        cnpj: _cnpj.text.replaceAll(RegExp(r'\D'), ''),
        adminEmail: _email.text.trim().toLowerCase(),
        ativa: _ativa,
      ),
    );
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
              key: const Key('empresa-email'),
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
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Empresa ativa'),
              value: _ativa,
              onChanged: (value) => setState(() => _ativa = value ?? true),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _salvar, child: const Text('Salvar')),
    ],
  );
}
