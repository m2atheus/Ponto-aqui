import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/management_json.dart';
import '../repositories/repository_failure.dart';
import 'api_providers.dart';
import 'auth_provider.dart';

final dashboardProvider = FutureProvider<Map<String, int>>((ref) async {
  final session = ref.watch(authProvider).asData?.value;
  if (session == null || session.isMock || session.user.companyId == null) {
    throw const RepositoryFailure(
      'Entre com uma conta real da empresa para consultar os indicadores.',
    );
  }
  return repositoryRequest(() async {
    final response = await ref.watch(dioProvider).get<Object?>('dashboard');
    final j = managementObject(response.data);
    if (j['empresa_id'] != session.user.companyId) {
      throw const FormatException('Empresa incompatível.');
    }
    final indicadores = managementObject(j['indicadores']);
    return Map.unmodifiable({
      for (final name in [
        'funcionarios',
        'setores',
        'escalas_ativas',
        'justificativas_pendentes',
      ])
        name: _contador(indicadores[name]),
    });
  });
}, retry: (count, error) => null);

int _contador(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Contagem inválida.');
  }
  return value;
}
