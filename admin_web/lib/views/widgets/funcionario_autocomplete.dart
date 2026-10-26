import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../../models/funcionario.dart';
import '../../repositories/funcionario_repository.dart';
import '../../repositories/repository_failure.dart';

/// Lista inicial no foco; busca digitada com debounce e proteção contra respostas antigas.
class FuncionarioAutocomplete extends StatefulWidget {
  const FuncionarioAutocomplete({
    super.key,
    required this.repository,
    required this.onChanged,
    this.enabled = true,
  });

  final FuncionarioRepository repository;
  final ValueChanged<Funcionario?> onChanged;
  final bool enabled;

  @override
  State<FuncionarioAutocomplete> createState() =>
      _FuncionarioAutocompleteState();
}

class _FuncionarioAutocompleteState extends State<FuncionarioAutocomplete> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _suggestions = SuggestionsController<Funcionario>();
  final _fieldKey = GlobalKey<FormFieldState<Funcionario>>();
  Timer? _debounce;
  CancelToken? _cancel;
  Completer<List<Funcionario>>? _pending;
  int _request = 0;
  bool _loading = false;
  bool _empty = false;
  String? _error;
  Funcionario? _selected;
  String _lastText = '';

  static String _label(Funcionario f) => '${f.nome} · ${f.matricula}';

  @override
  void initState() {
    super.initState();
    _text.addListener(_textChanged);
  }

  void _textChanged() {
    if (_text.text == _lastText) return;
    _lastText = _text.text;
    // Cancela já na edição: o TypeAhead pode estar aguardando a chamada anterior.
    _cancelPending();
    if (_selected != null && _text.text != _label(_selected!)) {
      _selected = null;
      _fieldKey.currentState?.didChange(null);
      widget.onChanged(null);
    }
  }

  void _cancelPending() {
    _request++;
    _debounce?.cancel();
    _cancel?.cancel('Busca substituída ou campo encerrado.');
    if (_pending != null && !_pending!.isCompleted) _pending!.complete([]);
  }

  @override
  void didUpdateWidget(covariant FuncionarioAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _cancelPending();
      _loading = false;
      _focus.unfocus();
    }
  }

  @override
  void dispose() {
    _cancelPending();
    _text.removeListener(_textChanged);
    _text.dispose();
    _focus.dispose();
    _suggestions.dispose();
    super.dispose();
  }

  Future<List<Funcionario>> _options(String text) {
    _cancelPending();
    final request = _request;
    final q = text.trim();
    setState(() {
      _loading = false;
      _empty = false;
      _error = null;
    });
    if (!widget.enabled ||
        !_focus.hasFocus ||
        (_selected != null && text == _label(_selected!))) {
      return Future.value(const <Funcionario>[]);
    }
    final pending = _pending = Completer<List<Funcionario>>();
    Future<void> fetch() async {
      if (!mounted || request != _request) return;
      final cancel = _cancel = CancelToken();
      setState(() => _loading = true);
      try {
        final rows = await widget.repository.buscar(q, cancelToken: cancel);
        if (!mounted || request != _request) return;
        setState(() {
          _loading = false;
          _empty = rows.isEmpty;
        });
        if (!pending.isCompleted) pending.complete(rows);
      } catch (error) {
        if (!mounted || request != _request || cancel.isCancelled) return;
        setState(() {
          _loading = false;
          _error = error is RepositoryFailure
              ? error.message
              : 'Não foi possível buscar funcionários.';
        });
        if (!pending.isCompleted) pending.complete([]);
      }
    }

    if (q.isEmpty) {
      // Campo vazio: carrega imediatamente a lista padrão de até 20 pessoas.
      unawaited(fetch());
    } else {
      _debounce = Timer(const Duration(milliseconds: 500), fetch);
    }
    return pending.future;
  }

  @override
  Widget build(BuildContext context) => FormField<Funcionario>(
    key: _fieldKey,
    validator: (_) => _selected == null || _text.text != _label(_selected!)
        ? 'Selecione um funcionário da busca.'
        : null,
    builder: (field) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TypeAheadField<Funcionario>(
          controller: _text,
          focusNode: _focus,
          suggestionsController: _suggestions,
          showOnFocus: true,
          debounceDuration:
              Duration.zero, // O debounce condicional é controlado em _options.
          retainOnLoading: false,
          hideOnLoading: true,
          hideOnEmpty: true,
          offset: Offset.zero,
          direction: VerticalDirection.down,
          autoFlipDirection: false,
          constrainWidth: true,
          transitionBuilder: (context, animation, child) => child,
          constraints: const BoxConstraints(maxHeight: 260),
          suggestionsCallback: _options,
          onSelected: (f) {
            _cancelPending();
            setState(() {
              _selected = f;
              _loading = false;
              _empty = false;
              _error = null;
            });
            _text.text = _label(f);
            field.didChange(f);
            if (field.hasError) field.validate();
            widget.onChanged(f);
          },
          // Somente a caixa de entrada participa da âncora do overlay.
          builder: (context, controller, focus) => TextField(
            key: const Key('funcionario-busca-input'),
            controller: controller,
            focusNode: focus,
            enabled: widget.enabled,
            maxLength: 150,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Funcionário',
              hintText: 'Selecione ou busque um funcionário',
              counterText: '',
              prefixIcon: const Icon(Icons.person_search_outlined),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _error != null
                  ? IconButton(
                      tooltip: 'Tentar buscar funcionários novamente',
                      icon: const Icon(Icons.refresh),
                      onPressed: !widget.enabled
                          ? null
                          : () {
                              _focus.requestFocus();
                              _suggestions.refresh();
                              _suggestions.open(gainFocus: false);
                            },
                    )
                  : _text.text.isEmpty
                  ? const Icon(Icons.keyboard_arrow_down)
                  : IconButton(
                      tooltip: 'Limpar funcionário',
                      onPressed: !widget.enabled
                          ? null
                          : () {
                              _selected = null;
                              field.didChange(null);
                              controller.clear();
                              widget.onChanged(null);
                              focus.requestFocus();
                            },
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),
          ),
          decorationBuilder: (context, child) => Material(
            key: const Key('funcionario-sugestoes'),
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
          listBuilder: (context, children) => ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: children,
          ),
          itemBuilder: (context, funcionario) => ListTile(
            dense: true,
            title: Text(
              _label(funcionario),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: funcionario.ativo
                ? null
                : const Text('Inativo · histórico disponível'),
          ),
        ),
        // Ajuda e validação ficam fora do alvo do CompositedTransformFollower.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Semantics(
            liveRegion: field.hasError || _error != null,
            child: Text(
              field.errorText ??
                  _error ??
                  (_empty
                      ? 'Nenhum funcionário encontrado.'
                      : 'Selecione na lista ou busque por nome ou matrícula.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: field.hasError || _error != null
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
