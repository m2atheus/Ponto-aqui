import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/mobile_sync_dto.dart';

Map<String, dynamic> example(String mode) =>
    jsonDecode(File('../docs/examples/w08-$mode.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('lê os exemplos reais da API nos dois modos e preserva o contrato', () {
    for (final mode in ['pessoal', 'relogio']) {
      final dto = MobileSyncDto.fromJson(example(mode));
      expect(dto.serverTimestamp.isUtc, isTrue);
      expect(dto.setor!.latitude, -8.0);
      expect(dto.setor!.politicas.acaoForaPerimetro, 'BLOQUEAR');
      expect(MobileSyncDto.fromJson(dto.toJson()).toJson(), dto.toJson());
      if (mode == 'pessoal') {
        expect(dto.modoOperacao, ModoOperacao.pessoal);
        expect(dto.funcionario!.matricula, '001');
        expect(dto.escala!.turnos.single.horaFim, '07:00');
        expect(dto.alocacoes.single.dataFim, isNull);
      } else {
        expect(dto.modoOperacao, ModoOperacao.relogio);
        expect(
          dto.funcionarios.single.alocacoes.single.escalaId,
          dto.escalas.single.id,
        );
      }
    }
  });

  test('sem alocação ou funcionário mantém campos nulos e listas vazias', () {
    final json = example('pessoal')
      ..['status'] = 'SEM_ALOCACAO'
      ..['setor'] = null
      ..['escala'] = null
      ..['alocacoes'] = null
      ..remove('marcacoes_recentes');
    final dto = MobileSyncDto.fromJson(json);
    expect(dto.funcionario, isNotNull);
    expect(dto.setor, isNull);
    expect(dto.escala, isNull);
    expect(dto.alocacoes, isEmpty);
    expect(dto.marcacoesRecentes, isEmpty);
    json['funcionario'] = null;
    json['status'] = 'SEM_FUNCIONARIO';
    expect(MobileSyncDto.fromJson(json).funcionario, isNull);
  });

  test('múltiplas alocações mantêm seus setores com resumo nulo', () {
    final json = example('pessoal')
      ..['status'] = 'MULTIPLAS_ALOCACOES'
      ..['setor'] = null
      ..['escala'] = null;
    (json['alocacoes'] as List).add(
      jsonDecode(jsonEncode((json['alocacoes'] as List).first)),
    );
    final dto = MobileSyncDto.fromJson(json);
    expect(dto.setor, isNull);
    expect(dto.alocacoes, hasLength(2));
    expect(dto.alocacoes.first.setor.nome, 'Sede');
  });

  test('relógio aceita funcionário sem conta, cargo ou escala', () {
    final json = example('relogio');
    final employee = (json['funcionarios'] as List).single as Map;
    employee['usuario_id'] = null;
    employee['cargo'] = null;
    (employee['alocacoes'] as List).single['escala_id'] = null;
    json['escalas'] = null;
    final dto = MobileSyncDto.fromJson(json);
    expect(dto.funcionarios.single.funcionario.usuarioId, isNull);
    expect(dto.funcionarios.single.funcionario.cargo, isNull);
    expect(dto.funcionarios.single.alocacoes.single.escalaId, isNull);
    expect(dto.escalas, isEmpty);
  });

  test('marcações recentes preservam UUID, UTC e motivos', () {
    final json = example('pessoal');
    json['marcacoes_recentes'] = [
      {
        'id': '66666666-6666-4666-8666-666666666666',
        'evento_cliente_id': '77777777-7777-4777-8777-777777777777',
        'tipo': 'Entrada',
        'situacao': 'PendenteAnalise',
        'ocorrido_em': '2026-10-05T15:00:00.123456Z',
        'recebido_em': '2026-10-05T15:01:00+00:00',
        'motivos': ['FORA_PERIMETRO'],
      },
    ];
    final mark = MobileSyncDto.fromJson(json).marcacoesRecentes.single;
    expect(mark.ocorridoEm.microsecond, 456);
    expect(mark.recebidoEm.isUtc, isTrue);
    expect(mark.motivos, ['FORA_PERIMETRO']);
  });

  for (final timestamp in [
    '2026-02-30T15:00:00Z',
    '2026-10-05T25:00:00Z',
    '2026-10-05T15:00:00',
    '2026-10-05T15:00:00-03:00',
    null,
  ]) {
    test('rejeita timestamp UTC inválido: $timestamp', () {
      final json = example('pessoal')..['server_timestamp'] = timestamp;
      expect(() => MobileSyncDto.fromJson(json), throwsFormatException);
    });
  }

  test('erros de tipos e datas produzem FormatException tratável', () {
    final json = example('pessoal');
    (json['setor'] as Map)['latitude'] = '-8';
    expect(() => MobileSyncDto.fromJson(json), throwsFormatException);
    json['setor'] = null;
    json['data_referencia'] = '2026-02-29';
    expect(() => MobileSyncDto.fromJson(json), throwsFormatException);
    json['data_referencia'] = '2026-10-05';
    json['alocacoes'] = 'inválido';
    expect(() => MobileSyncDto.fromJson(json), throwsFormatException);
  });

  test('relógio rejeita referência a escala ausente no catálogo', () {
    final json = example('relogio')..['escalas'] = [];
    expect(() => MobileSyncDto.fromJson(json), throwsFormatException);
  });
}
