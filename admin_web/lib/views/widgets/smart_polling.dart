import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';

/// Um timer por tela visível, sem chamadas simultâneas ou polling em segundo plano.
mixin SmartPolling<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, WidgetsBindingObserver {
  Timer? _pollTimer;
  CancelToken? _pollCancel;
  bool _polling = false;
  bool _resumePending = false;
  bool _wasStarted = false;
  bool _routeVisible = false;
  late AppLifecycleState _lifecycle;

  Duration get pollingInterval => const Duration(seconds: 60);
  bool get pollingEnabled => true;
  Future<void> refreshForPolling(CancelToken cancelToken);

  bool get _canRun {
    if (!mounted || !_routeVisible || _lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    final session = ref.read(authProvider).asData?.value;
    return session != null &&
        !session.isMock &&
        session.expiresAt.isAfter(DateTime.now());
  }

  bool get _canPoll => _canRun && pollingEnabled;

  @override
  void initState() {
    super.initState();
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncPolling(refresh: state == AppLifecycleState.resumed);
  }

  void _syncPolling({bool refresh = false}) {
    if (!_canRun) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _resumePending = false;
      _pollCancel?.cancel('Tela fora de foco.');
      return;
    }
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(pollingInterval, (_) => unawaited(_poll()));
    // A carga inicial pertence ao provider. Retornos à tela/aba atualizam uma vez.
    if (_wasStarted || refresh) {
      scheduleMicrotask(() => _poll(queueIfBusy: true));
    }
    _wasStarted = true;
  }

  Future<void> _poll({bool queueIfBusy = false}) async {
    if (!_canPoll) {
      _syncPolling();
      return;
    }
    if (_polling) {
      if (queueIfBusy) _resumePending = true;
      return;
    }
    _polling = true;
    final cancel = _pollCancel = CancelToken();
    try {
      await refreshForPolling(cancel);
    } catch (_) {
      // Atualizações automáticas preservam os dados e não abrem alertas.
    } finally {
      _polling = false;
      _pollCancel = null;
      if (_resumePending && _canPoll) {
        _resumePending = false;
        unawaited(_poll());
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollCancel?.cancel('Tela encerrada.');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
