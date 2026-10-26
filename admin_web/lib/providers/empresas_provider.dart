import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/empresa.dart';
import '../services/empresa_service.dart';
import 'api_providers.dart';
import 'auth_provider.dart';
import 'silent_refresh.dart';
import 'dashboard_provider.dart';

final empresaServiceProvider = Provider<EmpresaService>(
  (ref) => EmpresaService(ref.watch(dioProvider)),
);
final empresasProvider =
    AsyncNotifierProvider<EmpresasController, List<Empresa>>(
      EmpresasController.new,
      retry: (count, error) => null,
    );

class EmpresasController extends AsyncNotifier<List<Empresa>>
    with SilentRefresh<List<Empresa>> {
  @override
  Future<List<Empresa>> loadForPolling(CancelToken cancelToken) =>
      ref.read(empresaServiceProvider).listar(cancelToken: cancelToken);

  @override
  Future<List<Empresa>> build() async {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null || session.user.role != UserRole.superadmin) return [];
    if (session.isMock) {
      throw const EmpresaFailure(
        'Entre com uma conta real de Superadmin para acessar o banco.',
      );
    }
    return ref.watch(empresaServiceProvider).listar();
  }

  AuthSession _session() {
    final session = ref.read(authProvider).asData?.value;
    if (session == null ||
        session.isMock ||
        session.user.role != UserRole.superadmin) {
      throw const EmpresaFailure(
        'Entre com uma conta real de Superadmin para salvar empresas.',
      );
    }
    return session;
  }

  Future<void> _mutate(Future<Empresa> Function(EmpresaService) action) async {
    final token = _session().accessToken;
    final empresa = await action(ref.read(empresaServiceProvider));
    if (!ref.mounted ||
        ref.read(authProvider).asData?.value?.accessToken != token) {
      return;
    }
    final lista = state.asData?.value ?? [];
    state = AsyncData([
      for (final item in lista)
        if (item.id == empresa.id) empresa else item,
      if (!lista.any((item) => item.id == empresa.id)) empresa,
    ]);
    ref.invalidate(dashboardProvider);
  }

  Future<void> salvar(Empresa empresa, {String? senhaInicial}) =>
      _mutate((service) => service.salvar(empresa, senhaInicial: senhaInicial));
  Future<void> desativar(Empresa empresa) =>
      _mutate((service) => service.desativar(empresa));
}
