import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../services/auth_service.dart';
import 'api_providers.dart';

final mockAuthEnabledProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment('ENABLE_MOCK_AUTH', defaultValue: false),
);
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    ref.watch(dioProvider),
    ref.watch(tokenStorageProvider),
    enableMock: ref.watch(mockAuthEnabledProvider),
  ),
);
final authProvider = AsyncNotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
  retry: (retryCount, error) => null,
);

class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() =>
      ref.read(authServiceProvider).restoreSession();
  Future<void> login(String email, String password) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).login(email, password),
    );
  }

  Future<void> logout() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authServiceProvider).logout();
      return null;
    });
  }
}
