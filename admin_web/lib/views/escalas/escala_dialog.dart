import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/escala.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escalas_provider.dart';
import '../../utils/civil_date.dart';
import '../widgets/w06_widgets.dart';

class EscalaDialog extends ConsumerStatefulWidget {
  const EscalaDialog({
    super.key,
    this.escala,
    required this.empresaId,
    required this.token,
  });

  final Escala? escala;
  final String empresaId, token;

  @override
  ConsumerState<EscalaDialog> createState() => _EscalaDialogState();
}

class _EscalaDialogState extends ConsumerState<EscalaDialog> {
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
    for (final turno
        in widget.escala?.turnos.isNotEmpty == true
            ? widget.escala!.turnos
            : [TurnoEscala(inicio: 480, fim: 1020, intervalo: 60)])
      _CamposTurno(turno),
  ];
  bool _salvando = false;
  String? _erro;

  bool get _ciclica => _modelo == '12x36' || _modelo == '24x72';

  @override
  void dispose() {
    _nome.dispose();
    _referencia.dispose();
    for (final turno in _turnos) {
      turno.dispose();
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
              dataReferencia: _ciclica
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

  Future<void> _selecionarReferencia() async {
    var initial = DateTime.now();
    try {
      initial = DateTime.parse(civilDateFromInput(_referencia.text));
    } on FormatException {
      // Um campo vazio ou incompleto abre o calendário na data atual.
    }
    if (initial.year < 1900 || initial.year > 2100) initial = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Selecionar data de referência',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );
    if (mounted && date != null) {
      _referencia.text = civilDateDisplay(civilDateIso(date));
    }
  }

  InputDecoration _input(String hint, {Widget? suffixIcon}) {
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: colors.onSurfaceVariant),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      filled: true,
      fillColor: colors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colors.secondary, width: 1.5),
      ),
      errorMaxLines: 3,
      counterText: '',
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_salvando,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 24, 24),
        actionsAlignment: MainAxisAlignment.end,
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actionsOverflowButtonSpacing: 12,
        buttonPadding: const EdgeInsets.only(left: 12),
        title: Text(widget.escala == null ? 'Nova Escala' : 'Editar Escala'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Defina os horários e os dias de trabalho da equipe.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _CampoRotulado(
                    titulo: 'Nome da Escala',
                    child: TextFormField(
                      key: const Key('escala-nome'),
                      controller: _nome,
                      enabled: !_salvando,
                      maxLength: 120,
                      textInputAction: TextInputAction.next,
                      decoration: _input('Ex.: Comercial — segunda a sexta'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Informe o nome da escala.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _CampoRotulado(
                    titulo: 'Modelo',
                    child: DropdownButtonFormField<String>(
                      key: const Key('escala-modelo'),
                      initialValue: _modelo,
                      isExpanded: true,
                      decoration: _input('Selecione o modelo'),
                      items: [
                        for (final m in Escala.modelos.where(
                          (m) =>
                              m != 'Legado' ||
                              widget.escala?.modelo == 'Legado',
                        ))
                          DropdownMenuItem(value: m, child: Text(m)),
                      ],
                      onChanged: _salvando
                          ? null
                          : (v) => setState(() => _modelo = v!),
                    ),
                  ),
                  if (_ciclica) ...[
                    const SizedBox(height: 20),
                    _CampoRotulado(
                      key: const Key('escala-referencia'),
                      titulo: 'Data de referência',
                      child: TextFormField(
                        controller: _referencia,
                        enabled: !_salvando,
                        keyboardType: TextInputType.datetime,
                        decoration: _input(
                          'DD/MM/AAAA',
                          suffixIcon: IconButton(
                            tooltip: 'Selecionar Data de referência',
                            onPressed: _salvando ? null : _selecionarReferencia,
                            icon: const Icon(Icons.calendar_month_outlined),
                          ),
                        ),
                        validator: (value) {
                          try {
                            final iso = civilDateFromInput(value ?? '');
                            final ano = int.parse(iso.substring(0, 4));
                            return ano < 1900 || ano > 2100
                                ? 'Use um ano entre 1900 e 2100.'
                                : null;
                          } on FormatException {
                            return 'Informe uma data válida (DD/MM/AAAA).';
                          }
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (_modelo == 'Legado')
                    const Text(
                      'Escala legada: nome e status podem ser editados. '
                      'Para definir turnos, selecione um modelo estruturado.',
                    )
                  else ...[
                    for (var i = 0; i < _turnos.length; i++) ...[
                      _turno(_turnos[i], i),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.all(16),
                        ),
                        onPressed: _salvando || _turnos.length >= 16
                            ? null
                            : () => setState(
                                () => _turnos.add(
                                  _CamposTurno(
                                    TurnoEscala(inicio: 480, fim: 1020),
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar turno'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Escala ativa'),
                    subtitle: const Text('Disponível para novas alocações.'),
                    value: _ativa,
                    onChanged: _salvando
                        ? null
                        : (v) => setState(() => _ativa = v),
                  ),
                  if (_erro != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _erro!,
                        style: TextStyle(color: theme.colorScheme.error),
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
            onPressed: _salvando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(112, 48)),
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(_salvando ? 'Salvando…' : 'Salvar'),
          ),
        ],
      ),
    );
  }

  Widget _horario(String titulo, TextEditingController controller, Key? key) =>
      _CampoRotulado(
        titulo: titulo,
        child: TextFormField(
          key: key,
          controller: controller,
          enabled: !_salvando,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.next,
          decoration: _input('HH:mm'),
          validator: (v) => Escala.lerHorario(v ?? '') == null
              ? 'Use HH:mm entre 00:00 e 23:59.'
              : null,
        ),
      );

  Widget _turno(_CamposTurno t, int i) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      key: ObjectKey(t),
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Turno ${i + 1}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
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
                    icon: const Icon(Icons.close, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final entrada = _horario(
                  'Entrada',
                  t.inicio,
                  i == 0 ? const Key('escala-entrada') : null,
                );
                final saida = _horario(
                  'Saída',
                  t.fim,
                  i == 0 ? const Key('escala-saida') : null,
                );
                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [entrada, const SizedBox(height: 16), saida],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: entrada),
                    const SizedBox(width: 16),
                    Expanded(child: saida),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Saída anterior à entrada cruza a meia-noite.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            _CampoRotulado(
              titulo: 'Intervalo (minutos)',
              child: TextFormField(
                controller: t.intervalo,
                enabled: !_salvando,
                keyboardType: TextInputType.number,
                decoration: _input('Ex.: 60'),
                validator: (v) =>
                    int.tryParse(v ?? '') == null || int.parse(v!) < 0
                    ? 'Informe um intervalo não negativo.'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fim no dia seguinte'),
              subtitle: const Text('Obrigatório para turnos de 24 horas.'),
              value: t.diaSeguinte,
              onChanged: _salvando
                  ? null
                  : (v) => setState(() => t.diaSeguinte = v),
            ),
            if (!_ciclica) ...[
              const SizedBox(height: 20),
              _CampoRotulado(
                titulo: 'Dias de trabalho',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        key: i == 0 ? Key('dia-$d') : null,
                        label: Text(Escala.dias[d - 1]),
                        selected: t.dias.contains(d),
                        backgroundColor: colors.surface,
                        selectedColor: colors.secondaryContainer,
                        checkmarkColor: colors.secondary,
                        labelStyle: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                        side: BorderSide(
                          color: t.dias.contains(d)
                              ? colors.secondary.withValues(alpha: .3)
                              : colors.outlineVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CampoRotulado extends StatelessWidget {
  const _CampoRotulado({super.key, required this.titulo, required this.child});
  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        titulo,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );
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

  TurnoEscala dto() => TurnoEscala(
    inicio: Escala.lerHorario(inicio.text)!,
    fim: Escala.lerHorario(fim.text)!,
    intervalo: int.parse(intervalo.text),
    dias: dias,
    diaSeguinte: diaSeguinte,
  );

  void dispose() {
    inicio.dispose();
    fim.dispose();
    intervalo.dispose();
  }
}
