import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth_session.dart';
import '../../models/management_mock.dart';
import '../../providers/auth_provider.dart';
import '../../providers/management_mock_provider.dart';
import '../modules/module_placeholder_view.dart';

class EscalasScreen extends ConsumerStatefulWidget {
  const EscalasScreen({super.key});
  @override
  ConsumerState<EscalasScreen> createState() => _EscalasScreenState();
}

class _EscalasScreenState extends ConsumerState<EscalasScreen> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _formulario([EscalaMock? escala]) async {
    final user = ref.read(authProvider).asData?.value?.user;
    if (user?.role != UserRole.rh || user?.companyId == null) return;
    final resultado = await showDialog<EscalaMock>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _EscalaDialog(
        escala: escala,
        empresaId: user!.companyId!,
        existentes: ref.read(escalasMockProvider),
      ),
    );
    if (!mounted ||
        resultado == null ||
        ref.read(authProvider).asData?.value?.user.id != user!.id ||
        ref.read(authProvider).asData?.value?.user.companyId !=
            user.companyId) {
      return;
    }
    ref.read(escalasMockProvider.notifier).salvar(resultado);
  }

  Future<void> _remover(EscalaMock escala) async {
    final confirmar = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Remover escala?'),
        content: Text(
          'Remover a escala "${escala.nome}" desta lista de demonstração?',
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
    if (mounted && confirmar == true) {
      ref.read(escalasMockProvider.notifier).remover(escala);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).asData?.value?.user;
    if (user?.role != UserRole.rh || user?.companyId == null) {
      return const ModulePlaceholderView(
        title: 'Acesso negado',
        message: 'Esta área é exclusiva do RH da empresa.',
      );
    }
    final escalas = ref.watch(escalasMockProvider);
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
                'Escalas',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              FilledButton.icon(
                onPressed: _formulario,
                icon: const Icon(Icons.add),
                label: const Text('Nova Escala'),
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
                    DataColumn(label: Text('Nome da Escala')),
                    DataColumn(label: Text('Entrada')),
                    DataColumn(label: Text('Saída')),
                    DataColumn(label: Text('Dias da Semana')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Ações')),
                  ],
                  rows: [
                    for (final escala in escalas)
                      DataRow(
                        key: ValueKey(escala.id),
                        cells: [
                          DataCell(Text(escala.nome)),
                          DataCell(
                            Text(
                              EscalaMock.formatarHorario(escala.entradaMinutos),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${EscalaMock.formatarHorario(escala.saidaMinutos)}${escala.terminaNoDiaSeguinte ? ' (+1 dia)' : ''}',
                            ),
                          ),
                          DataCell(Text(escala.diasFormatados)),
                          DataCell(Text(escala.ativa ? 'Ativa' : 'Inativa')),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: Key('editar-escala-${escala.id}'),
                                  tooltip: 'Editar ${escala.nome}',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _formulario(escala),
                                ),
                                IconButton(
                                  key: Key('remover-escala-${escala.id}'),
                                  tooltip: 'Remover ${escala.nome}',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _remover(escala),
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
          if (escalas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhuma escala cadastrada.'),
            ),
        ],
      ),
    );
  }
}

class _EscalaDialog extends StatefulWidget {
  const _EscalaDialog({
    this.escala,
    required this.empresaId,
    required this.existentes,
  });
  final EscalaMock? escala;
  final String empresaId;
  final List<EscalaMock> existentes;
  @override
  State<_EscalaDialog> createState() => _EscalaDialogState();
}

class _EscalaDialogState extends State<_EscalaDialog> {
  final _form = GlobalKey<FormState>();
  final _dias = GlobalKey<FormFieldState<Set<int>>>();
  late final TextEditingController _nome;
  late final TextEditingController _entrada;
  late final TextEditingController _saida;
  late bool _ativa;
  @override
  void initState() {
    super.initState();
    _nome = TextEditingController(text: widget.escala?.nome ?? '');
    _entrada = TextEditingController(
      text: EscalaMock.formatarHorario(widget.escala?.entradaMinutos ?? 480),
    );
    _saida = TextEditingController(
      text: EscalaMock.formatarHorario(widget.escala?.saidaMinutos ?? 1020),
    );
    _ativa = widget.escala?.ativa ?? true;
  }

  @override
  void dispose() {
    _nome.dispose();
    _entrada.dispose();
    _saida.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      EscalaMock(
        id: widget.escala?.id ?? '',
        empresaId: widget.empresaId,
        nome: _nome.text.trim(),
        entradaMinutos: EscalaMock.lerHorario(_entrada.text)!,
        saidaMinutos: EscalaMock.lerHorario(_saida.text)!,
        diasSemana: _dias.currentState!.value!,
        ativa: _ativa,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.escala == null ? 'Nova Escala' : 'Editar Escala'),
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
              key: const Key('escala-nome'),
              controller: _nome,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nome da Escala'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Informe o nome da escala.';
                }
                if (widget.existentes.any(
                  (item) =>
                      item.id != widget.escala?.id &&
                      item.nome.toLowerCase() == value.trim().toLowerCase(),
                )) {
                  return 'Nome de escala já cadastrado.';
                }
                return null;
              },
            ),
            TextFormField(
              key: const Key('escala-entrada'),
              controller: _entrada,
              maxLength: 5,
              keyboardType: TextInputType.datetime,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Entrada (HH:mm)'),
              validator: (value) => EscalaMock.lerHorario(value ?? '') == null
                  ? 'Use HH:mm entre 00:00 e 23:59.'
                  : null,
            ),
            TextFormField(
              key: const Key('escala-saida'),
              controller: _saida,
              maxLength: 5,
              keyboardType: TextInputType.datetime,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Saída (HH:mm)',
                helperText: 'Saída anterior à entrada termina no dia seguinte.',
                helperMaxLines: 2,
              ),
              validator: (value) {
                final saida = EscalaMock.lerHorario(value ?? '');
                if (saida == null) return 'Use HH:mm entre 00:00 e 23:59.';
                if (saida == EscalaMock.lerHorario(_entrada.text)) {
                  return 'Entrada e saída devem ser diferentes.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            const Text('Dias da Semana'),
            FormField<Set<int>>(
              key: _dias,
              initialValue: widget.escala?.diasSemana ?? const {1, 2, 3, 4, 5},
              validator: (value) => value == null || value.isEmpty
                  ? 'Selecione ao menos um dia.'
                  : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var dia = 1; dia <= 7; dia++)
                        FilterChip(
                          key: Key('dia-$dia'),
                          label: Text(EscalaMock.dias[dia - 1]),
                          selected: field.value!.contains(dia),
                          onSelected: (selected) {
                            final dias = {...field.value!};
                            if (selected) {
                              dias.add(dia);
                            } else {
                              dias.remove(dia);
                            }
                            field.didChange(dias);
                          },
                        ),
                    ],
                  ),
                  if (field.hasError)
                    Text(
                      field.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Escala ativa'),
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
