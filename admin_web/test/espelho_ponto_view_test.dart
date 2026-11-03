import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/w06.dart';
import 'package:ponto_aqui_admin/views/relatorios/espelho_ponto_view.dart';

import 'support/w06_api_fake.dart';

Map<String, dynamic> mesSemOcorrencias() {
  final json = W06ApiFake().report('funcionario-1', 2026, 10);
  for (final dia in json['dias'] as List) {
    dia['status'] = [
      'PREVISTO',
      'FOLGA',
      'SEM_ALOCACAO',
    ][int.parse(dia['data'].substring(8)) % 3];
    dia['minutos_trabalhados'] = 0;
    dia['minutos_abonados'] = 0;
    dia['minutos_faltas'] = 0;
    dia['feriados'] = [];
    dia['afastamentos'] = [];
    dia['marcacoes'] = [];
  }
  return json;
}

void main() {
  testWidgets(
    'filtra dias vazios preservando feriado, afastamento, falta e batidas auditadas',
    (tester) async {
      final json = mesSemOcorrencias();
      final dias = json['dias'] as List;
      dias[0]['feriados'] = [
        {'descricao': 'Feriado futuro'},
      ];
      dias[1]['minutos_trabalhados'] = 480;
      dias[1]['status'] = 'TRABALHADO';
      dias[2]['marcacoes'] = [
        {
          'id': 'ponto-invalidado',
          'tipo': 'Entrada',
          'situacao': 'Aceita',
          'ocorrido_em': '2026-10-03T08:00:00-03:00',
          'invalidado': true,
          'invalidacao': {'motivo_texto': 'Foto incorreta'},
        },
      ];
      dias[3]['status'] = 'FALTA';
      dias[3]['minutos_previstos'] = 480;
      dias[3]['minutos_faltas'] = 480;
      dias[4]['status'] = 'ABONADO_JUSTIFICADO';
      dias[4]['afastamentos'] = [
        {'tipo': 'ATESTADO'},
      ];
      final espelho = EspelhoMensal.fromJson(json, 'empresa-1');
      final totalApi = espelho.totalApi('previstos');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EspelhoPontoView(dias: espelho.dias),
            ),
          ),
        ),
      );

      final tabela = tester.widget<DataTable>(find.byType(DataTable));
      expect(tabela.rows.map((r) => r.key), [
        for (var dia = 1; dia <= 5; dia++) ValueKey('espelho-2026-10-0$dia'),
      ]);
      expect(find.text('Feriado futuro'), findsOneWidget);
      expect(find.text('Atestado'), findsOneWidget);
      expect(espelho.dias, hasLength(31));
      expect(espelho.totalApi('previstos'), totalApi);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mês sem ocorrências mostra ícone e mensagem em tela estreita', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final espelho = EspelhoMensal.fromJson(mesSemOcorrencias(), 'empresa-1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EspelhoPontoView(dias: espelho.dias)),
      ),
    );

    expect(find.byType(DataTable), findsNothing);
    expect(find.byIcon(Icons.event_note_outlined), findsOneWidget);
    expect(
      find.text('Nenhum registro ou feriado encontrado para este período.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
