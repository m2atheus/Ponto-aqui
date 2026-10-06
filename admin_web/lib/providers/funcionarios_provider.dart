import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/funcionario.dart';
import '../repositories/alocacao_repository.dart';
import '../repositories/funcionario_repository.dart';
import '../repositories/repository_failure.dart';
import 'api_providers.dart';
import 'auth_provider.dart';

AuthSession _requireRh(AuthSession? session) {
  if (session == null ||
      session.user.role != UserRole.rh ||
      session.user.companyId == null) {
    throw const RepositoryFailure('Esta área é exclusiva do RH da empresa.');
  }
  if (session.isMock) {
    throw const RepositoryFailure(
      'Entre com uma conta real de RH para acessar estes cadastros.',
    );
  }
  return session;
}

final funcionarioRepositoryProvider = Provider<FuncionarioRepository>((ref) {
  final session = _requireRh(ref.watch(authProvider).asData?.value);
  return FuncionarioRepository(
    ref.watch(dioProvider),
    empresaId: session.user.companyId!,
  );
});

final alocacaoRepositoryProvider = Provider<AlocacaoRepository>((ref) {
  final session = _requireRh(ref.watch(authProvider).asData?.value);
  return AlocacaoRepository(
    ref.watch(dioProvider),
    empresaId: session.user.companyId!,
  );
});

final funcionariosProvider =
    AsyncNotifierProvider<FuncionariosController, List<Funcionario>>(
      FuncionariosController.new,
      retry: (count, error) => null,
    );

class FuncionariosController extends AsyncNotifier<List<Funcionario>> {
  @override
  Future<List<Funcionario>> build() async {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null || session.user.role != UserRole.rh) return [];
    _requireRh(session);
    final cancel = CancelToken();
    ref.onDispose(() => cancel.cancel('Sessão ou consulta encerrada.'));
    return ref.watch(funcionarioRepositoryProvider).listar(cancelToken: cancel);
  }

  Future<void> _mutate(
    Future<Funcionario> Function(FuncionarioRepository) action,
  ) async {
    final session = _requireRh(ref.read(authProvider).asData?.value);
    final saved = await action(ref.read(funcionarioRepositoryProvider));
    if (!ref.mounted) {
      throw const RepositoryFailure('A sessão foi alterada. Entre novamente.');
    }
    final current = ref.read(authProvider).asData?.value;
    if (current?.accessToken != session.accessToken ||
        current?.user.companyId != session.user.companyId) {
      throw const RepositoryFailure('A sessão foi alterada. Atualize a tela.');
    }
    final rows = state.asData?.value ?? [];
    state = AsyncData(
      List<Funcionario>.unmodifiable([
        for (final row in rows)
          if (row.id == saved.id) saved else row,
        if (!rows.any((row) => row.id == saved.id)) saved,
      ]),
    );
  }

  Future<void> salvar(Funcionario dto) => _mutate(
    (repository) =>
        dto.id.isEmpty ? repository.criar(dto) : repository.atualizar(dto),
  );
  Future<void> desativar(Funcionario dto) =>
      _mutate((repository) => repository.desativar(dto));
}
