import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/providers/api_providers.dart';
import 'package:ponto_aqui_admin/providers/auth_provider.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/theme/app_theme.dart';
import 'package:ponto_aqui_admin/views/auth/login_view.dart';
import 'package:ponto_aqui_admin/views/widgets/brand_backdrop.dart';

import 'support/auth_fakes.dart';

void main() {
  setUpAll(() async {
    // The default Ahem test font hid the overflow seen with browser fonts.
    TestWidgetsFlutterBinding.ensureInitialized();
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        (jsonDecode(await config.readAsString())
                as Map<String, dynamic>)['packages']
            as List<dynamic>;
    final flutter = packages.cast<Map<String, dynamic>>().firstWhere(
      (p) => p['name'] == 'flutter',
    );
    final packageRoot = config.uri.resolve('${flutter['rootUri']}/');
    final font = File.fromUri(
      packageRoot.resolve(
        '../../bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ),
    );
    await (FontLoader(
      'Roboto',
    )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
  });

  for (final (size, scale) in [
    (const Size(1147, 802), 1.0),
    (const Size(1440, 900), 1.0),
    (const Size(900, 560), 1.0),
    (const Size(1147, 802), 1.5),
    (const Size(1147, 802), 2.0),
    (const Size(390, 700), 1.5),
  ]) {
    testWidgets('login sem overflow com fonte real: $size, escala $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final storage = MemoryTokenStorage();
      final dio = createDioClient(
        baseUrl: 'https://api.example.com/api/web/',
        tokenStorage: storage,
      )..httpClientAdapter = AuthAdapter();
      addTearDown(dio.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            dioProvider.overrideWithValue(dio),
            mockAuthEnabledProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const LoginView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width >= 900) {
        final panel = tester.getRect(
          find.byKey(const Key('login-presentation')),
        );
        final art = tester.getRect(find.byType(BrandJourneyArt));
        expect(art.bottom, lessThanOrEqualTo(panel.bottom));
      }
      await tester.ensureVisible(find.text('Entrar'));
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('Informe um e-mail válido.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
