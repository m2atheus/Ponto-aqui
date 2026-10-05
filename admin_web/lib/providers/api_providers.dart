import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api/dio_client.dart';
import '../services/storage/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(SharedPreferencesAsync());
});

final dioProvider = Provider<Dio>((ref) {
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000/api/web/',
  );

  final dio = createDioClient(
    baseUrl: baseUrl,
    tokenStorage: ref.watch(tokenStorageProvider),
  );
  ref.onDispose(() => dio.close(force: true));
  return dio;
});
