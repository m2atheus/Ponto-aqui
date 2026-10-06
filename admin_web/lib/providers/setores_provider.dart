import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/setor.dart';
import '../repositories/repository_failure.dart';
import 'alocacoes_provider.dart';
import 'auth_provider.dart';

// Permite testes do mapa sem acessar servidores de tiles.
final setorTileProviderFactoryProvider = Provider<TileProvider Function()>(
  (ref) =>
      () => NetworkTileProvider(),
);

final setoresProvider = AsyncNotifierProvider<SetoresController, List<Setor>>(
  SetoresController.new,
  retry: (count, error) => null,
);

AuthSession _sessao(AuthSession? value) {
  if (value == null ||
      value.isMock ||
      value.user.role != UserRole.rh ||
      value.user.companyId == null) {
    throw const RepositoryFailure(
      'Entre com uma conta real de RH para gerenciar os setores.',
    );
  }
  return value;
}

class SetoresController extends AsyncNotifier<List<Setor>> {
  @override
  Future<List<Setor>> build() async {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null || session.user.role != UserRole.rh) return [];
    _sessao(session);
    final cancel = CancelToken();
    ref.onDispose(() => cancel.cancel('Sessão ou consulta encerrada.'));
    return ref.watch(setorRepositoryProvider).listar(cancelToken: cancel);
  }

  void _conferirSessao(AuthSession anterior) {
    if (!ref.mounted) {
      throw const RepositoryFailure('A sessão foi alterada. Entre novamente.');
    }
    final atual = ref.read(authProvider).asData?.value;
    if (atual?.accessToken != anterior.accessToken ||
        atual?.user.companyId != anterior.user.companyId) {
      throw const RepositoryFailure('A sessão foi alterada. Atualize a tela.');
    }
  }

  Future<void> salvar(Setor dto) async {
    final session = _sessao(ref.read(authProvider).asData?.value);
    final repository = ref.read(setorRepositoryProvider);
    final saved = dto.id.isEmpty
        ? await repository.criar(dto)
        : await repository.atualizar(dto);
    _conferirSessao(session);
    final rows = state.asData?.value ?? [];
    final updated = [
      for (final row in rows)
        if (row.id == saved.id) saved else row,
      if (!rows.any((row) => row.id == saved.id)) saved,
    ]..sort((a, b) => a.nome.compareTo(b.nome));
    state = AsyncData(List.unmodifiable(updated));
    ref.invalidate(alocacoesProvider);
  }

  Future<void> remover(Setor dto) async {
    final session = _sessao(ref.read(authProvider).asData?.value);
    await ref.read(setorRepositoryProvider).remover(dto);
    _conferirSessao(session);
    state = AsyncData(
      List.unmodifiable(
        (state.asData?.value ?? []).where((row) => row.id != dto.id),
      ),
    );
    ref.invalidate(alocacoesProvider);
  }
}
