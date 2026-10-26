import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/management_json.dart';
import '../repositories/repository_failure.dart';
import 'api_providers.dart';
import 'auth_provider.dart';
import 'silent_refresh.dart';

final dashboardProvider =
    AsyncNotifierProvider<DashboardController, Map<String, int>>(
      DashboardController.new,
      retry: (count, error) => null,
    );

class DashboardController extends AsyncNotifier<Map<String, int>>
    with SilentRefresh<Map<String, int>> {
  @override
  Future<Map<String, int>> build() {
    ref.watch(authProvider);
    ref.watch(dioProvider);
    final cancel = CancelToken();
    ref.onDispose(() => cancel.cancel('Sessão ou consulta encerrada.'));
    return loadForPolling(cancel);
  }

  @override
  Future<Map<String, int>> loadForPolling(CancelToken cancelToken) {
    final session = ref.read(authProvider).asData?.value;
    if (session == null || session.isMock) {
      throw const RepositoryFailure(
        'Entre com uma conta real para consultar os indicadores.',
      );
    }
    final dio = ref.read(dioProvider);
    return repositoryRequest(() async {
      final response = await dio.get<Object?>(
        'dashboard',
        cancelToken: cancelToken,
      );
      final j = managementObject(response.data);
      if (!j.containsKey('empresa_id') ||
          j['empresa_id'] != session.user.companyId) {
        throw const FormatException('Empresa incompatível.');
      }
      final indicadores = managementObject(j['indicadores']);
      final campos = session.user.role == UserRole.superadmin
          ? ['empresas']
          : [
              'funcionarios',
              'setores',
              'escalas_ativas',
              'justificativas_pendentes',
            ];
      return Map.unmodifiable({
        for (final name in campos) name: _contador(indicadores[name]),
      });
    });
  }
}

int _contador(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Contagem inválida.');
  }
  return value;
}
