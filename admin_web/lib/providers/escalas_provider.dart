import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/escala.dart';
import '../repositories/escala_repository.dart';
import '../repositories/repository_failure.dart';
import 'api_providers.dart';
import 'auth_provider.dart';
import 'silent_refresh.dart';
import 'dashboard_provider.dart';
import 'w06_provider.dart';
import 'alocacoes_provider.dart';

final escalaRepositoryProvider = Provider<EscalaRepository>((ref) {
  final session = ref.watch(authProvider).asData?.value;
  if (session == null ||
      session.isMock ||
      session.user.role != UserRole.rh ||
      session.user.companyId == null) {
    throw const RepositoryFailure(
      'Entre com uma conta real de RH para gerenciar escalas.',
    );
  }
  return EscalaRepository(
    ref.watch(dioProvider),
    empresaId: session.user.companyId!,
  );
});
final escalasProvider = AsyncNotifierProvider<EscalasController, List<Escala>>(
  EscalasController.new,
  retry: (count, error) => null,
);

class EscalasController extends AsyncNotifier<List<Escala>>
    with SilentRefresh<List<Escala>> {
  @override
  Future<List<Escala>> loadForPolling(CancelToken cancelToken) =>
      ref.read(escalaRepositoryProvider).listar(cancelToken: cancelToken);

  @override
  Future<List<Escala>> build() {
    final cancel = CancelToken();
    ref.onDispose(() => cancel.cancel());
    return ref.watch(escalaRepositoryProvider).listar(cancelToken: cancel);
  }

  void _sessao(String? token) {
    if (!ref.mounted ||
        ref.read(authProvider).asData?.value?.accessToken != token) {
      throw const RepositoryFailure('A sessão foi alterada. Entre novamente.');
    }
  }

  Future<void> salvar(Escala dto) async {
    final token = ref.read(authProvider).asData?.value?.accessToken;
    final saved = await ref.read(escalaRepositoryProvider).salvar(dto);
    _sessao(token);
    state = AsyncData(
      List.unmodifiable(
        [...state.asData?.value.where((e) => e.id != saved.id) ?? [], saved]
          ..sort((a, b) => a.nome.compareTo(b.nome)),
      ),
    );
    ref.invalidate(dashboardProvider);
    ref.invalidate(w06Provider);
    ref.invalidate(alocacoesProvider);
  }

  Future<void> remover(String id) async {
    final token = ref.read(authProvider).asData?.value?.accessToken;
    await ref.read(escalaRepositoryProvider).remover(id);
    _sessao(token);
    state = AsyncData(
      List.unmodifiable(state.requireValue.where((e) => e.id != id)),
    );
    ref.invalidate(dashboardProvider);
    ref.invalidate(w06Provider);
    ref.invalidate(alocacoesProvider);
  }
}
