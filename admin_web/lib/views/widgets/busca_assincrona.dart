import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../../repositories/repository_failure.dart';

class BuscaAssincrona<T> extends StatefulWidget {
  const BuscaAssincrona({
    super.key,
    required this.inputId,
    required this.titulo,
    required this.hint,
    required this.validationMessage,
    required this.icon,
    required this.buscar,
    required this.label,
    required this.onChanged,
    required this.enabled,
  });
  final String inputId, titulo, hint, validationMessage;
  final IconData icon;
  final bool enabled;
  final Future<List<T>> Function(String, CancelToken) buscar;
  final String Function(T) label;
  final ValueChanged<T?> onChanged;
  @override
  State<BuscaAssincrona<T>> createState() => BuscaAssincronaState<T>();
}

class BuscaAssincronaState<T> extends State<BuscaAssincrona<T>> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _field = GlobalKey<FormFieldState<T>>();
  final _suggestions = SuggestionsController<T>();
  Timer? _debounce;
  CancelToken? _cancel;
  Completer<List<T>>? _pending;
  int _request = 0;
  T? _selected;
  String _lastText = '';
  String? _error;
  bool _loading = false, _empty = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_textChanged);
  }

  void _cancelPending() {
    _request++;
    _debounce?.cancel();
    _cancel?.cancel('Busca substituída ou formulário encerrado.');
    if (_pending != null && !_pending!.isCompleted) _pending!.complete([]);
  }

  void _textChanged() {
    if (_text.text == _lastText) return;
    _lastText = _text.text;
    _cancelPending();
    if (_selected != null && _text.text != widget.label(_selected as T)) {
      _selected = null;
      _field.currentState?.didChange(null);
      widget.onChanged(null);
    }
  }

  @override
  void didUpdateWidget(covariant BuscaAssincrona<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _cancelPending();
      _loading = false;
      _focus.unfocus();
      _suggestions.close();
    }
  }

  Future<List<T>> _options(String text) {
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
        (_selected != null && text == widget.label(_selected as T))) {
      return Future.value([]);
    }
    final pending = _pending = Completer<List<T>>();
    Future<void> fetch() async {
      if (!mounted || request != _request || !_focus.hasFocus) {
        if (!pending.isCompleted) pending.complete([]);
        return;
      }
      final cancel = _cancel = CancelToken();
      setState(() => _loading = true);
      try {
        final rows = await widget.buscar(q, cancel);
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
              : 'Não foi possível concluir a busca.';
        });
        if (!pending.isCompleted) pending.complete([]);
      }
    }

    if (q.isEmpty) {
      unawaited(
        fetch(),
      ); // Lista inicial: até 20 registros, sem esperar 500 ms.
    } else {
      _debounce = Timer(const Duration(milliseconds: 500), fetch);
    }
    return pending.future;
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FormField<T>(
      key: _field,
      validator: (_) =>
          _selected == null || _text.text != widget.label(_selected as T)
          ? widget.validationMessage
          : null,
      builder: (field) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.titulo,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TypeAheadField<T>(
            controller: _text,
            focusNode: _focus,
            suggestionsController: _suggestions,
            showOnFocus: true,
            debounceDuration:
                Duration.zero, // Debounce condicional em _options.
            offset: Offset.zero,
            direction: VerticalDirection.down,
            autoFlipDirection: false,
            constrainWidth: true,
            constraints: const BoxConstraints(maxHeight: 240),
            retainOnLoading: false,
            hideOnLoading: true,
            hideOnEmpty: true,
            transitionBuilder: (context, animation, child) => child,
            suggestionsCallback: _options,
            onSelected: (value) {
              _cancelPending();
              setState(() {
                _selected = value;
                _loading = false;
                _empty = false;
                _error = null;
              });
              _text.text = widget.label(value);
              field.didChange(value);
              if (field.hasError) field.validate();
              widget.onChanged(value);
            },
            builder: (context, controller, focus) => TextField(
              key: Key(widget.inputId),
              controller: controller,
              focusNode: focus,
              enabled: widget.enabled,
              maxLength: 150,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: widget.hint,
                counterText: '',
                prefixIcon: Icon(widget.icon),
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
                        tooltip: 'Tentar buscar novamente',
                        icon: const Icon(Icons.refresh),
                        onPressed: !widget.enabled
                            ? null
                            : () {
                                focus.requestFocus();
                                _suggestions.refresh();
                                _suggestions.open(gainFocus: false);
                              },
                      )
                    : controller.text.isEmpty
                    ? const Icon(Icons.keyboard_arrow_down)
                    : IconButton(
                        tooltip: 'Limpar seleção',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: !widget.enabled
                            ? null
                            : () {
                                _selected = null;
                                field.didChange(null);
                                controller.clear();
                                widget.onChanged(null);
                                focus.requestFocus();
                              },
                      ),
              ),
            ),
            decorationBuilder: (context, child) => Material(
              key: Key('${widget.inputId}-sugestoes'),
              color: colors.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
            listBuilder: (context, children) => ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: children,
            ),
            itemBuilder: (context, value) => ListTile(
              dense: true,
              title: Text(
                widget.label(value),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (field.hasError || _error != null || _empty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  field.errorText ?? _error ?? 'Nenhum resultado encontrado.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: field.hasError || _error != null
                        ? colors.error
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
