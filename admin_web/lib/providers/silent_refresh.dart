import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

/// Mantém AsyncData durante a consulta e descarta respostas de sessão ou estado antigos.
mixin SilentRefresh<T> on AsyncNotifier<T> {
  bool _refreshing = false;
  Future<T> loadForPolling(CancelToken cancelToken);

  Future<void> refreshSilently(CancelToken cancelToken) async {
    if (_refreshing || state.isLoading || cancelToken.isCancelled) return;
    final session = ref.read(authProvider).asData?.value;
    if (session == null ||
        session.isMock ||
        !session.expiresAt.isAfter(DateTime.now())) {
      return;
    }
    final previous = state;
    _refreshing = true;
    bool current() =>
        ref.mounted &&
        !cancelToken.isCancelled &&
        ref.read(authProvider).asData?.value?.accessToken ==
            session.accessToken &&
        identical(state, previous);
    try {
      final value = await loadForPolling(cancelToken);
      if (current()) state = AsyncData(value);
    } catch (error, stack) {
      if (current() && !previous.hasValue) state = AsyncError(error, stack);
    } finally {
      _refreshing = false;
    }
  }
}
