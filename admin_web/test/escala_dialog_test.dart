import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/escala.dart';
import 'package:ponto_aqui_admin/providers/auth_provider.dart';
import 'package:ponto_aqui_admin/theme/app_theme.dart';
import 'package:ponto_aqui_admin/views/escalas/escala_dialog.dart';
import 'package:ponto_aqui_admin/views/escalas/escalas_screen.dart';

import 'support/w06_api_fake.dart';
import 'w06_screens_test.dart' show mount;

void main() {
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('editar escala em $width pixels; tema escuro=$dark', (
        tester,
      ) async {
        final api = W06ApiFake();
        final container = await mount(
          tester,
          '/escalas',
          api: api,
          size: Size(width, 900),
        );
        final session = container.read(authProvider).asData!.value!;
        unawaited(
          showDialog<bool>(
            context: tester.element(find.byType(EscalasScreen)),
            useRootNavigator: false,
            builder: (_) => Theme(
              data: dark ? AppTheme.dark : AppTheme.light,
              child: EscalaDialog(
                escala: Escala.fromJson(api.escalas.first),
                empresaId: session.user.companyId!,
                token: session.accessToken,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final entry in {
          'escala-nome': 'Nome da Escala',
          'escala-entrada': 'Entrada',
          'escala-saida': 'Saída',
        }.entries) {
          final input = find.byKey(Key(entry.key));
          expect(
            tester
                .widget<TextField>(
                  find.descendant(of: input, matching: find.byType(TextField)),
                )
                .decoration
                ?.labelText,
            isNull,
          );
          final label = tester.getRect(
            find.descendant(
              of: find.byType(EscalaDialog),
              matching: find.text(entry.value),
            ),
          );
          expect(tester.getTopLeft(input).dy - label.bottom, closeTo(8, 1));
        }

        final entrada = tester.getRect(find.byKey(const Key('escala-entrada')));
        final saida = tester.getRect(find.byKey(const Key('escala-saida')));
        if (width >= 800) {
          expect(saida.top, closeTo(entrada.top, 1));
          expect(saida.left - entrada.right, closeTo(16, 1));
        } else {
          expect(saida.top, greaterThan(entrada.bottom));
        }
        final salvar = find.widgetWithText(FilledButton, 'Salvar');
        final cancelRect = tester.getRect(
          find.widgetWithText(TextButton, 'Cancelar'),
        );
        final saveRect = tester.getRect(salvar);
        if (saveRect.top >= cancelRect.bottom) {
          expect(cancelRect.right, closeTo(saveRect.right, 1));
        } else {
          expect(cancelRect.right, lessThan(saveRect.left));
        }
        await tester.ensureVisible(find.byKey(const Key('escala-entrada')));
        await tester.enterText(
          find.byKey(const Key('escala-entrada')),
          '25:00',
        );
        await tester.tap(salvar);
        await tester.pumpAndSettle();
        expect(find.text('Use HH:mm entre 00:00 e 23:59.'), findsOneWidget);
        expect(api.requests.where((r) => r.method == 'PUT'), isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'adicionar e remover turno mantém os horários do turno original',
    (tester) async {
      await mount(tester, '/escalas');
      await tester.tap(find.text('Nova Escala'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('escala-entrada')), '09:30');
      final adicionar = find.widgetWithText(OutlinedButton, 'Adicionar turno');
      await tester.ensureVisible(adicionar);
      await tester.tap(adicionar);
      await tester.pumpAndSettle();
      expect(find.text('Turno 2'), findsOneWidget);
      final remover = find.byTooltip('Remover turno').last;
      await tester.ensureVisible(remover);
      await tester.tap(remover);
      await tester.pumpAndSettle();
      expect(find.text('Turno 2'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('escala-entrada')))
            .controller!
            .text,
        '09:30',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
