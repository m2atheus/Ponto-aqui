import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../repositories/alocacao_repository.dart';
import '../repositories/repository_failure.dart';
import 'api_providers.dart';
import 'auth_provider.dart';

// Permite somente o fluxo de mudança. O servidor continua protegendo os CRUDs do RH.
final mudancaAlocacaoRepositoryProvider = Provider<AlocacaoRepository>((ref) {
  final sessao = ref.watch(authProvider).asData?.value;
  if (sessao == null ||
      sessao.isMock ||
      sessao.user.companyId == null ||
      !{UserRole.rh, UserRole.gestor}.contains(sessao.user.role) ||
      !sessao.expiresAt.isAfter(DateTime.now())) {
    throw const RepositoryFailure(
      'Entre com uma conta de RH ou Gestor da empresa.',
    );
  }
  return AlocacaoRepository(
    ref.watch(dioProvider),
    empresaId: sessao.user.companyId!,
  );
});
