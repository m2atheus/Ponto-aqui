import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth_session.dart';
import '../../models/escala.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escalas_provider.dart';
import '../../utils/civil_date.dart';
import '../widgets/status_badge.dart';
import '../widgets/w06_widgets.dart';

class EscalasScreen extends ConsumerStatefulWidget {
  const EscalasScreen({super.key});
  @override
  ConsumerState<EscalasScreen> createState() => _EscalasScreenState();
}

class _EscalasScreenState extends ConsumerState<EscalasScreen> {
  bool _ocupado = false;
  Future<void> _formulario([Escala? escala]) async {
    final session = ref.read(authProvider).asData?.value;
    if (_ocupado ||
        session == null ||
        session.isMock ||
        session.user.role != UserRole.rh) {
      return;
    }
    setState(() => _ocupado = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => _EscalaDialog(
          escala: escala,
          empresaId: session.user.companyId!,
          token: session.accessToken,
        ),
      );
      if (mounted &&
          saved == true &&
          ref.read(authProvider).asData?.value?.accessToken ==
              session.accessToken) {
        w06Message(context, 'Escala salva no banco.');
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _remover(Escala escala) async {
    if (_ocupado) return;
    final token = ref.read(authProvider).asData?.value?.accessToken;
    setState(() => _ocupado = true);
    try {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('Remover escala?'),
          content: Text(
            'Remover "${escala.nome}"? Escalas com histórico de alocações devem ser desativadas.',
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
          ok != true ||
          token != ref.read(authProvider).asData?.value?.accessToken) {
        return;
      }
      await ref.read(escalasProvider.notifier).remover(escala.id);
      if (mounted) w06Message(context, 'Escala removida do banco.');
    } catch (error) {
      if (mounted) w06Message(context, w06Error(error), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authProvider).asData?.value?.user.role != UserRole.rh) {
      return const Center(child: Text('Acesso exclusivo do RH.'));
    }
    final state = ref.watch(escalasProvider);
    return W06PageLayout(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Escalas',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              FilledButton.icon(
                onPressed: _ocupado || !state.hasValue
                    ? null
                    : () => _formulario(),
                icon: const Icon(Icons.add),
                label: const Text('Nova Escala'),
              ),
              IconButton(
                tooltip: 'Atualizar escalas',
                onPressed: _ocupado
                    ? null
                    : () => ref.invalidate(escalasProvider),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Turnos e ciclos da empresa. Escalas já utilizadas preservam seus horários históricos.',
          ),
          const SizedBox(height: 20),
          state.when(
            skipLoadingOnRefresh: false,
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w06Error(error)),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(escalasProvider),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
            data: (escalas) => W06Table(
              emptyMessage: 'Nenhuma escala cadastrada.',
              columns: const [
                DataColumn(label: Text('Nome da Escala')),
                DataColumn(label: Text('Modelo')),
                DataColumn(label: Text('Turnos')),
                DataColumn(label: Text('Dias da Semana')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Ações')),
              ],
              rows: [
                for (final e in escalas)
                  DataRow(
                    cells: [
                      DataCell(Text(e.nome)),
                      DataCell(Text(e.modelo)),
                      DataCell(
                        SizedBox(
                          width: 180,
                          child: Text(
                            e.turnos.isEmpty
                                ? 'Sem turnos estruturados'
                                : e.turnos
                                      .map(
                                        (t) =>
                                            '${Escala.formatarHorario(t.inicio)}–${Escala.formatarHorario(t.fim)}${t.fim < t.inicio || t.diaSeguinte ? ' (+1 dia)' : ''} · ${t.intervalo} min',
                                      )
                                      .join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          e.ciclica
                              ? 'Ciclo contínuo'
                              : (e.turnos.expand((t) => t.dias).toSet().toList()
                                      ..sort())
                                    .map((d) => Escala.dias[d - 1])
                                    .join(', '),
                        ),
                      ),
                      DataCell(StatusBadge(ativo: e.ativa)),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: Key('editar-escala-${e.id}'),
                              tooltip: 'Editar escala',
                              onPressed: _ocupado ? null : () => _formulario(e),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              key: Key('remover-escala-${e.id}'),
                              tooltip: 'Remover escala',
                              onPressed: _ocupado ? null : () => _remover(e),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CamposTurno {
  _CamposTurno(TurnoEscala t)
    : inicio = TextEditingController(text: Escala.formatarHorario(t.inicio)),
      fim = TextEditingController(text: Escala.formatarHorario(t.fim)),
      intervalo = TextEditingController(text: '${t.intervalo}'),
      dias = {...t.dias},
      diaSeguinte = t.diaSeguinte;
  final TextEditingController inicio, fim, intervalo;
  final Set<int> dias;
  bool diaSeguinte;
  void dispose() {
    inicio.dispose();
    fim.dispose();
    intervalo.dispose();
  }

  TurnoEscala dto() => TurnoEscala(
    inicio: Escala.lerHorario(inicio.text)!,
    fim: Escala.lerHorario(fim.text)!,
    intervalo: int.parse(intervalo.text),
    dias: dias,
    diaSeguinte: diaSeguinte,
  );
}

class _EscalaDialog extends ConsumerStatefulWidget {
  const _EscalaDialog({
    this.escala,
    required this.empresaId,
    required this.token,
  });
  final Escala? escala;
  final String empresaId, token;
  @override
  ConsumerState<_EscalaDialog> createState() => _EscalaDialogState();
}

class _EscalaDialogState extends ConsumerState<_EscalaDialog> {
  final _form = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.escala?.nome ?? '');
  late final _referencia = TextEditingController(
    text: widget.escala?.dataReferencia == null
        ? ''
        : civilDateDisplay(widget.escala!.dataReferencia!),
  );
  late String _modelo = widget.escala?.modelo ?? '5x2';
  late bool _ativa = widget.escala?.ativa ?? true;
  late final _turnos = [
    for (final t
        in widget.escala?.turnos.isNotEmpty == true
            ? widget.escala!.turnos
            : [TurnoEscala(inicio: 480, fim: 1020, intervalo: 60)])
      _CamposTurno(t),
  ];
  bool _salvando = false;
  String? _erro;
  @override
  void dispose() {
    _nome.dispose();
    _referencia.dispose();
    for (final t in _turnos) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || !_form.currentState!.validate()) return;
    if (_modelo != 'Legado' && _turnos.any((t) => t.dias.isEmpty)) {
      setState(() => _erro = 'Selecione ao menos um dia.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref
          .read(escalasProvider.notifier)
          .salvar(
            Escala(
              id: widget.escala?.id ?? '',
              empresaId: widget.empresaId,
              nome: _nome.text.trim(),
              modelo: _modelo,
              ativa: _ativa,
              dataReferencia: _modelo == '12x36' || _modelo == '24x72'
                  ? civilDateFromInput(_referencia.text)
                  : null,
              turnos: _modelo == 'Legado'
                  ? widget.escala?.turnos ?? []
                  : _turnos.map((t) => t.dto()),
            ),
          );
      if (mounted &&
          ref.read(authProvider).asData?.value?.accessToken == widget.token) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _erro = w06Error(error));
        w06Message(context, _erro!, error: true);
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_salvando,
    child: AlertDialog(
      title: Text(widget.escala == null ? 'Nova Escala' : 'Editar Escala'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('escala-nome'),
                  controller: _nome,
                  enabled: !_salvando,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Nome da Escala',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Informe o nome da escala.'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const Key('escala-modelo'),
                  initialValue: _modelo,
                  decoration: const InputDecoration(labelText: 'Modelo'),
                  items: [
                    for (final m in Escala.modelos.where(
                      (m) => m != 'Legado' || widget.escala?.modelo == 'Legado',
                    ))
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: _salvando
                      ? null
                      : (v) => setState(() => _modelo = v!),
                ),
                if (_modelo == '12x36' || _modelo == '24x72') ...[
                  const SizedBox(height: 16),
                  W06DateField(
                    key: const Key('escala-referencia'),
                    controller: _referencia,
                    label: 'Data de referência',
                    enabled: !_salvando,
                  ),
                ],
                if (_modelo == 'Legado')
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Escala legada: nome e status podem ser editados. Para definir turnos, selecione um modelo estruturado.',
                    ),
                  ),
                if (_modelo != 'Legado') ...[
                  for (var i = 0; i < _turnos.length; i++)
                    _turno(_turnos[i], i),
                  OutlinedButton.icon(
                    onPressed: _salvando || _turnos.length >= 16
                        ? null
                        : () => setState(
                            () => _turnos.add(
                              _CamposTurno(TurnoEscala(inicio: 480, fim: 1020)),
                            ),
                          ),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar turno'),
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Escala ativa'),
                  value: _ativa,
                  onChanged: _salvando
                      ? null
                      : (v) => setState(() => _ativa = v!),
                ),
                if (_erro != null)
                  Text(
                    _erro!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_salvando) const LinearProgressIndicator(),
              ],
            ),
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
          child: Text(_salvando ? 'Salvando…' : 'Salvar'),
        ),
      ],
    ),
  );

  Widget _turno(_CamposTurno t, int i) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Turno ${i + 1}')),
              if (_turnos.length > 1)
                IconButton(
                  tooltip: 'Remover turno',
                  onPressed: _salvando
                      ? null
                      : () {
                          setState(() => _turnos.remove(t));
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => t.dispose(),
                          );
                        },
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          TextFormField(
            key: i == 0 ? const Key('escala-entrada') : null,
            controller: t.inicio,
            enabled: !_salvando,
            decoration: const InputDecoration(labelText: 'Entrada (HH:mm)'),
            validator: (v) => Escala.lerHorario(v ?? '') == null
                ? 'Use HH:mm entre 00:00 e 23:59.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: i == 0 ? const Key('escala-saida') : null,
            controller: t.fim,
            enabled: !_salvando,
            decoration: const InputDecoration(
              labelText: 'Saída (HH:mm)',
              helperText: 'Saída anterior à entrada cruza a meia-noite.',
              helperMaxLines: 2,
            ),
            validator: (v) => Escala.lerHorario(v ?? '') == null
                ? 'Use HH:mm entre 00:00 e 23:59.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: t.intervalo,
            enabled: !_salvando,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Intervalo (minutos)'),
            validator: (v) => int.tryParse(v ?? '') == null || int.parse(v!) < 0
                ? 'Informe um intervalo não negativo.'
                : null,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fim no dia seguinte (obrigatório para 24h)'),
            value: t.diaSeguinte,
            onChanged: _salvando
                ? null
                : (v) => setState(() => t.diaSeguinte = v!),
          ),
          if (_modelo != '12x36' && _modelo != '24x72')
            Wrap(
              spacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    key: i == 0 ? Key('dia-$d') : null,
                    label: Text(Escala.dias[d - 1]),
                    selected: t.dias.contains(d),
                    onSelected: _salvando
                        ? null
                        : (v) => setState(() {
                            if (v) {
                              t.dias.add(d);
                            } else {
                              t.dias.remove(d);
                            }
                          }),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}
