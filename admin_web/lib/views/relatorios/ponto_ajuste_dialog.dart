import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../repositories/ponto_admin_repository.dart';
import '../../repositories/repository_failure.dart';
import '../../utils/civil_date.dart';

bool _timeZonesInicializados = false;
void _inicializarFusos() {
  if (!_timeZonesInicializados) {
    tzdata.initializeTimeZones();
    _timeZonesInicializados = true;
  }
}

/// Conversão no fuso IANA da empresa, independente do fuso do navegador.
/// Base oficial: https://pub.dev/packages/timezone
List<DateTime> instantesDaBatida(String fuso, DateTime data, TimeOfDay hora) {
  _inicializarFusos();
  final location = tz.getLocation(fuso);
  final civil = DateTime.utc(
    data.year,
    data.month,
    data.day,
    hora.hour,
    hora.minute,
  );
  final offsets = <Duration>{
    for (final delta in [-2, 0, 2])
      tz.TZDateTime.from(
        civil.add(Duration(days: delta)),
        location,
      ).timeZoneOffset,
  };
  final candidatos = <DateTime>[];
  for (final offset in offsets) {
    final utc = civil.subtract(offset);
    final local = tz.TZDateTime.from(utc, location);
    if (local.year == data.year &&
        local.month == data.month &&
        local.day == data.day &&
        local.hour == hora.hour &&
        local.minute == hora.minute) {
      candidatos.add(utc);
    }
  }
  candidatos.sort();
  return candidatos;
}

/// Retorna true após persistir. A recarga é separada para não repetir um POST
/// que já foi confirmado caso apenas a consulta seguinte falhe.
Future<bool> mostrarAjustePontoDialog({
  required BuildContext context,
  required PontoAdminRepository repository,
  required String funcionarioNome,
  required String fusoHorario,
  required bool Function() sessaoValida,
  required Future<void> Function() recarregar,
  String? usuarioId,
  String? registroOriginalId,
  DateTime? dataHoraInicial,
}) async {
  if (!sessaoValida()) return false;
  final messenger = ScaffoldMessenger.of(context);
  final salvo = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: false,
    builder: (_) => PontoAjusteDialog(
      repository: repository,
      funcionarioNome: funcionarioNome,
      fusoHorario: fusoHorario,
      sessaoValida: sessaoValida,
      usuarioId: usuarioId,
      registroOriginalId: registroOriginalId,
      dataHoraInicial: dataHoraInicial,
    ),
  );
  if (salvo != true || !context.mounted || !sessaoValida()) return false;
  messenger.showSnackBar(
    const SnackBar(
      backgroundColor: Color(0xFF237A48),
      content: Text(
        'Ajuste aprovado e salvo com sucesso.',
        style: TextStyle(color: Colors.white),
      ),
    ),
  );
  try {
    await recarregar();
  } catch (_) {
    if (context.mounted && sessaoValida()) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(
            'O ajuste foi salvo, mas a lista não pôde ser atualizada. Consulte o espelho novamente.',
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
        ),
      );
    }
  }
  return true;
}

class PontoAjusteDialog extends StatefulWidget {
  const PontoAjusteDialog({
    super.key,
    required this.repository,
    required this.funcionarioNome,
    required this.fusoHorario,
    required this.sessaoValida,
    this.usuarioId,
    this.registroOriginalId,
    this.dataHoraInicial,
  });
  final PontoAdminRepository repository;
  final String funcionarioNome;
  final String fusoHorario;
  final bool Function() sessaoValida;
  final String? usuarioId;
  final String? registroOriginalId;
  final DateTime? dataHoraInicial;

  @override
  State<PontoAjusteDialog> createState() => _PontoAjusteDialogState();
}

class _PontoAjusteDialogState extends State<PontoAjusteDialog> {
  final _form = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  late DateTime _data;
  late TimeOfDay _hora;
  TipoBatida _tipo = TipoBatida.entrada;
  DateTime? _instanteEscolhido;
  List<DateTime> _instantes = [];
  String? _erroHorario;
  bool _salvando = false;
  bool _selecionando = false;
  bool get _correcao => widget.registroOriginalId != null;

  @override
  void initState() {
    super.initState();
    _inicializarFusos();
    DateTime inicial;
    try {
      inicial = tz.TZDateTime.from(
        widget.dataHoraInicial ?? DateTime.now(),
        tz.getLocation(widget.fusoHorario),
      );
    } catch (_) {
      // O formulário permanece acessível; horário inválido bloqueia o envio.
      inicial = widget.dataHoraInicial ?? DateTime.now();
    }
    _data = DateTime(inicial.year, inicial.month, inicial.day);
    _hora = TimeOfDay(hour: inicial.hour, minute: inicial.minute);
    _atualizarHorario();
    final original = widget.dataHoraInicial?.toUtc();
    _instanteEscolhido = _instantes
        .where(
          (i) =>
              original != null && i.difference(original).inSeconds.abs() < 60,
        )
        .firstOrNull;
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _atualizarHorario() {
    _instanteEscolhido = null;
    try {
      _instantes = instantesDaBatida(widget.fusoHorario, _data, _hora);
      _erroHorario = _instantes.isEmpty
          ? 'Esse horário não existe no fuso da empresa. Escolha outro horário.'
          : null;
    } catch (_) {
      _instantes = [];
      _erroHorario = 'Fuso da empresa inválido. Confira o cadastro da empresa.';
    }
  }

  Future<void> _selecionar({required bool data}) async {
    if (_salvando || _selecionando) return;
    setState(() => _selecionando = true);
    try {
      if (data) {
        final valor = await showDatePicker(
          context: context,
          initialDate: _data.year >= 1900 && _data.year <= 2100
              ? _data
              : DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2100, 12, 31),
          helpText: 'Data da batida',
          cancelText: 'Cancelar',
          confirmText: 'Confirmar',
        );
        if (mounted && valor != null) {
          setState(() {
            _data = valor;
            _atualizarHorario();
          });
        }
      } else {
        final valor = await showTimePicker(
          context: context,
          initialTime: _hora,
          helpText: 'Hora da batida',
          cancelText: 'Cancelar',
          confirmText: 'Confirmar',
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
        if (mounted && valor != null) {
          setState(() {
            _hora = valor;
            _atualizarHorario();
          });
        }
      }
    } finally {
      if (mounted) setState(() => _selecionando = false);
    }
  }

  Future<void> _salvar() async {
    if (_salvando || _selecionando || !_form.currentState!.validate()) return;
    final instante =
        _instanteEscolhido ??
        (_instantes.length == 1 ? _instantes.single : null);
    if (_erroHorario != null || instante == null) return;
    if (!widget.sessaoValida()) {
      _erro('A sessão foi alterada. Entre novamente.');
      return;
    }
    setState(() => _salvando = true);
    try {
      if (_correcao) {
        await widget.repository.corrigirPontoExistente(
          registroOriginalId: widget.registroOriginalId!,
          novaDataHora: instante,
          motivoTexto: _motivo.text,
        );
      } else {
        if (widget.usuarioId == null) {
          throw const RepositoryFailure(
            'O funcionário precisa de uma conta de usuário vinculada.',
          );
        }
        await widget.repository.inserirPontoManual(
          usuarioId: widget.usuarioId!,
          novaDataHora: instante,
          motivoTexto: _motivo.text,
          tipo: _tipo,
        );
      }
      if (mounted) Navigator.of(context).pop(widget.sessaoValida());
    } catch (error) {
      if (mounted && widget.sessaoValida()) {
        _erro(
          error is RepositoryFailure
              ? error.message
              : 'Não foi possível salvar o ajuste. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _erro(String mensagem) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: colors.error,
        content: Text(mensagem, style: TextStyle(color: colors.onError)),
      ),
    );
  }

  String _offset(DateTime utc) {
    final minutos = tz.TZDateTime.from(
      utc,
      tz.getLocation(widget.fusoHorario),
    ).timeZoneOffset.inMinutes;
    return 'UTC${minutos < 0 ? '-' : '+'}${(minutos.abs() ~/ 60).toString().padLeft(2, '0')}:${(minutos.abs() % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_salvando && !_selecionando,
    child: AlertDialog(
      title: Text(_correcao ? 'Editar Batida' : 'Inserir Ponto Manual'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.funcionarioNome,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Fuso da empresa: ${widget.fusoHorario}'),
                const SizedBox(height: 20),
                if (!_correcao) ...[
                  DropdownButtonFormField<TipoBatida>(
                    key: const Key('ponto-tipo'),
                    initialValue: _tipo,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo da batida',
                    ),
                    items: [
                      for (final tipo in TipoBatida.values)
                        DropdownMenuItem(value: tipo, child: Text(tipo.label)),
                    ],
                    onChanged: _salvando
                        ? null
                        : (value) => setState(() => _tipo = value!),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  key: ValueKey('ponto-data-${civilDateIso(_data)}'),
                  initialValue: civilDateDisplay(civilDateIso(_data)),
                  readOnly: true,
                  enabled: !_salvando && !_selecionando,
                  decoration: const InputDecoration(
                    labelText: 'Data',
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  onTap: () => _selecionar(data: true),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: ValueKey('ponto-hora-${_hora.hour}-${_hora.minute}'),
                  initialValue:
                      '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}',
                  readOnly: true,
                  enabled: !_salvando && !_selecionando,
                  decoration: const InputDecoration(
                    labelText: 'Hora',
                    suffixIcon: Icon(Icons.schedule),
                  ),
                  onTap: () => _selecionar(data: false),
                ),
                if (_erroHorario != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _erroHorario!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_instantes.length > 1) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<DateTime>(
                    key: ValueKey(
                      'ponto-fuso-${civilDateIso(_data)}-${_hora.hour}-${_hora.minute}',
                    ),
                    initialValue: _instanteEscolhido,
                    decoration: const InputDecoration(
                      labelText: 'Horário repetido: escolha o fuso',
                    ),
                    items: [
                      for (final instante in _instantes)
                        DropdownMenuItem(
                          value: instante,
                          child: Text(_offset(instante)),
                        ),
                    ],
                    onChanged: _salvando
                        ? null
                        : (value) => setState(() => _instanteEscolhido = value),
                    validator: (value) => value == null
                        ? 'Selecione qual ocorrência do horário.'
                        : null,
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('ponto-motivo'),
                  controller: _motivo,
                  enabled: !_salvando,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    labelText: 'Motivo da Correção',
                    hintText: 'Ex.: funcionário esqueceu o celular',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Informe a justificativa do ajuste.'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando || _selecionando
              ? null
              : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          key: const Key('ponto-salvar'),
          onPressed: _salvando || _selecionando || _erroHorario != null
              ? null
              : _salvar,
          icon: _salvando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_salvando ? 'Salvando…' : 'Salvar'),
        ),
      ],
    ),
  );
}
