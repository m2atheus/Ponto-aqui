import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alocacao.dart';
import '../models/auth_session.dart';
import '../models/funcionario.dart';
import '../models/setor.dart';
import '../models/escala.dart';
import '../repositories/repository_failure.dart';
import '../repositories/setor_repository.dart';
import 'api_providers.dart';
import 'auth_provider.dart';
import 'funcionarios_provider.dart';
import 'escalas_provider.dart';
import 'w06_provider.dart';

AuthSession _sessaoRh(AuthSession? session) {
  if (session == null ||
      session.isMock ||
      session.user.role != UserRole.rh ||
      session.user.companyId == null) {
    throw const RepositoryFailure(
      'Entre com uma conta real de RH para acessar as alocações.',
    );
  }
  return session;
}

final setorRepositoryProvider = Provider<SetorRepository>((ref) {
  final session = _sessaoRh(ref.watch(authProvider).asData?.value);
  return SetorRepository(
    ref.watch(dioProvider),
    empresaId: session.user.companyId!,
  );
});

class AlocacoesData {
  AlocacoesData({
    required List<Alocacao> alocacoes,
    required List<Funcionario> funcionarios,
    required List<Setor> setores,
    List<Escala> escalas = const [],
  }) : alocacoes = List.unmodifiable(alocacoes),
       funcionarios = List.unmodifiable(funcionarios),
       setores = List.unmodifiable(setores),
       escalas = List.unmodifiable(escalas);
  final List<Alocacao> alocacoes;
  final List<Funcionario> funcionarios;
  final List<Setor> setores;
  final List<Escala> escalas;
}

final alocacoesProvider =
    AsyncNotifierProvider<AlocacoesController, AlocacoesData>(
      AlocacoesController.new,
      retry: (count, error) => null,
    );

class AlocacoesController extends AsyncNotifier<AlocacoesData> {
  @override
  Future<AlocacoesData> build() async {
    final auth = ref.watch(authProvider).asData?.value;
    if (auth == null || auth.user.role != UserRole.rh) {
      return AlocacoesData(alocacoes: [], funcionarios: [], setores: []);
    }
    _sessaoRh(auth);
    final cancel = CancelToken();
    ref.onDispose(() => cancel.cancel('Sessão ou consulta encerrada.'));
    final alocacoes = ref.watch(alocacaoRepositoryProvider);
    final funcionarios = ref.watch(funcionarioRepositoryProvider);
    final setores = ref.watch(setorRepositoryProvider);
    final escalas = ref.watch(escalaRepositoryProvider);
    // Consultas independentes; aguarda todas, inclusive em falha, antes de
    // liberar uma nova tentativa com dados consistentes da mesma sessão.
    final results = await Future.wait<Object>([
      alocacoes.listar(cancelToken: cancel),
      funcionarios.listar(cancelToken: cancel),
      setores.listar(cancelToken: cancel),
      escalas.listar(cancelToken: cancel),
    ]);
    return AlocacoesData(
      alocacoes: results[0] as List<Alocacao>,
      funcionarios: results[1] as List<Funcionario>,
      setores: results[2] as List<Setor>,
      escalas: results[3] as List<Escala>,
    );
  }

  Future<void> salvar(Alocacao dto) async {
    final session = _sessaoRh(ref.read(authProvider).asData?.value);
    final previous = state.asData?.value;
    if (previous == null) {
      throw const RepositoryFailure('Aguarde o carregamento das alocações.');
    }
    final repository = ref.read(alocacaoRepositoryProvider);
    final saved = dto.id.isEmpty
        ? await repository.criar(dto)
        : await repository.atualizar(dto);
    if (!ref.mounted) {
      throw const RepositoryFailure('A sessão foi alterada. Entre novamente.');
    }
    final current = ref.read(authProvider).asData?.value;
    if (current?.accessToken != session.accessToken ||
        current?.user.companyId != session.user.companyId) {
      throw const RepositoryFailure('A sessão foi alterada. Atualize a tela.');
    }
    final latest = state.asData?.value;
    if (latest == null) {
      throw const RepositoryFailure(
        'Atualize a lista para conferir a operação.',
      );
    }
    final rows =
        [
          for (final row in latest.alocacoes)
            if (row.id == saved.id) saved else row,
          if (!latest.alocacoes.any((row) => row.id == saved.id)) saved,
        ]..sort((a, b) {
          final order = b.dataInicio.compareTo(a.dataInicio);
          return order != 0 ? order : a.id.compareTo(b.id);
        });
    state = AsyncData(
      AlocacoesData(
        alocacoes: rows,
        funcionarios: latest.funcionarios,
        setores: latest.setores,
        escalas: latest.escalas,
      ),
    );
    ref.invalidate(w06Provider);
  }
}
