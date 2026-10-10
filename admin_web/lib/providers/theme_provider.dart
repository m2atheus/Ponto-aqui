import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeStorage {
  ThemeStorage(this.preferences);
  final SharedPreferencesAsync preferences;
  // Também lida pelo index.html durante o bootstrap Web (API Async sem prefixo).
  static const key = 'ponto_aqui_theme';

  Future<ThemeMode> load() async {
    try {
      return await preferences.getString(key) == 'dark'
          ? ThemeMode.dark
          : ThemeMode.light;
    } catch (_) {
      // Navegadores com armazenamento indisponível ainda podem abrir o painel.
      return ThemeMode.light;
    }
  }

  Future<void> save(ThemeMode mode) =>
      preferences.setString(key, mode == ThemeMode.dark ? 'dark' : 'light');
}

final themeStorageProvider = Provider<ThemeStorage>(
  (ref) => ThemeStorage(SharedPreferencesAsync()),
);
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.light);
final themeProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);

class ThemeController extends Notifier<ThemeMode> {
  bool _saving = false;

  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> toggle() async {
    if (_saving) return;
    _saving = true;
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    try {
      await ref.read(themeStorageProvider).save(next);
      if (ref.mounted) state = next;
    } finally {
      _saving = false;
    }
  }
}
