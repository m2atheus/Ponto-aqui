import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../models/auth_session.dart';
import '../models/w06.dart';
import '../repositories/repository_failure.dart';
import '../repositories/w06_repository.dart';
import '../repositories/ponto_admin_repository.dart';
import '../repositories/dispositivo_repository.dart';
import 'api_providers.dart';
import 'dashboard_provider.dart';
import 'auth_provider.dart';
import 'silent_refresh.dart';

final dispositivoRepositoryProvider = Provider<DispositivoRepository>((ref) {
  final session = ref.watch(authProvider).asData?.value;
  if (session == null ||
      session.isMock ||
      session.user.companyId == null ||
      !{UserRole.rh, UserRole.gestor}.contains(session.user.role) ||
      !session.expiresAt.isAfter(DateTime.now())) {
    throw const RepositoryFailure('Entre com uma conta real de RH ou Gestor.');
  }
  return DispositivoRepository(
    ref.watch(dioProvider),
    empresaId: session.user.companyId!,
  );
});

final pontoAdminRepositoryProvider = Provider<PontoAdminRepository>((ref) {
  final session = ref.watch(authProvider).asData?.value;
  if (session == null ||
      session.isMock ||
      !{UserRole.rh, UserRole.gestor}.contains(session.user.role) ||
      session.user.companyId == null ||
      !session.expiresAt.isAfter(DateTime.now())) {
    throw const RepositoryFailure(
      'Somente RH e Gestor da empresa podem administrar batidas.',
      statusCode: 403,
    );
  }
  return PontoAdminRepository(
    ref.watch(dioProvider),
    empresaId: session.user.companyId!,
  );
});

final w06RepositoryProvider = Provider<W06Repository>((ref) {
  final session = ref.watch(authProvider).asData?.value;
  final user = session?.user;
  if (user == null ||
      user.companyId == null ||
      user.role == UserRole.superadmin) {
    throw const RepositoryFailure(
      'Entre com uma conta da empresa.',
      statusCode: 403,
    );
  }
  if (session!.isMock) {
    throw const RepositoryFailure(
      'Entre com uma conta real da empresa para consultar o banco.',
    );
  }
  return W06Repository(ref.watch(dioProvider), empresaId: user.companyId!);
});

// Injetável: testes não abrem o seletor nativo do navegador.
final selecionarAtestadoProvider = Provider<Future<AnexoLocal?> Function()>(
  (ref) => () async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (file == null) return null;
    final length = file.lengthSync() ?? await file.length();
    if (!{
          'pdf',
          'png',
          'jpg',
          'jpeg',
        }.contains(file.extension?.toLowerCase()) ||
        length == null ||
        length <= 0 ||
        length > 10 * 1024 * 1024) {
      throw const RepositoryFailure(
        'Selecione um PDF, PNG ou JPG de até 10 MB.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != length) {
      throw const RepositoryFailure(
        'Não foi possível ler o arquivo completo. Selecione-o novamente.',
      );
    }
    return AnexoLocal(file.name, length, bytes: bytes);
  },
);

final w06Provider = AsyncNotifierProvider<W06Controller, W06Data>(
  W06Controller.new,
  retry: (count, error) => null,
);

class W06Controller extends AsyncNotifier<W06Data> with SilentRefresh<W06Data> {
  @override
  Future<W06Data> loadForPolling(CancelToken cancelToken) =>
      ref.read(w06RepositoryProvider).carregar(cancelToken: cancelToken);

  @override
  Future<W06Data> build() {
    final cancel = CancelToken();
    ref.onDispose(() => cancel.cancel());
    return ref.watch(w06RepositoryProvider).carregar(cancelToken: cancel);
  }

  Future<void> salvar(Future<void> Function(W06Repository) operation) async {
    final session = ref.read(authProvider).asData?.value;
    if (session == null || session.isMock || session.user.role != UserRole.rh) {
      throw const RepositoryFailure(
        'Somente o RH pode realizar cadastros.',
        statusCode: 403,
      );
    }
    final repository = ref.read(w06RepositoryProvider);
    await operation(repository);
    if (!ref.mounted ||
        ref.read(authProvider).asData?.value?.accessToken !=
            session.accessToken) {
      throw const RepositoryFailure('A sessão foi alterada. Entre novamente.');
    }
    final data = await AsyncValue.guard(() => repository.carregar());
    if (ref.mounted &&
        ref.read(authProvider).asData?.value?.accessToken ==
            session.accessToken) {
      state = data;
      ref.invalidate(dashboardProvider);
    }
  }
}
