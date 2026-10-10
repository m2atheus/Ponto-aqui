import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final storage = ThemeStorage(SharedPreferencesAsync());
  final savedTheme = await storage.load();
  runApp(
    ProviderScope(
      overrides: [
        themeStorageProvider.overrideWithValue(storage),
        initialThemeModeProvider.overrideWithValue(savedTheme),
      ],
      child: const AdminApp(),
    ),
  );
}
