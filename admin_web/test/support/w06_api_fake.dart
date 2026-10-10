import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';

import 'auth_fakes.dart';
import 'management_api_fake.dart';

class W06ApiFake extends ManagementApiFake {
  W06ApiFake({this.role = UserRole.rh}) {
    funcionarios.add({
      ...funcionarioJson(),
      'id': 'funcionario-2',
      'nome': 'Bruno Santos',
      'matricula': '002',
    });
    setores.add({...setorJson(), 'id': 'setor-2', 'nome': 'Filial'});
  }
  final UserRole role;
  final feriados = <Map<String, dynamic>>[
    {
      'id': 'feriado-1',
      'empresa_id': 'empresa-1',
      'data': '2026-10-01',
      'descricao': 'Feriado de teste',
      'setor_id': null,
    },
  ];
  final afastamentos = <Map<String, dynamic>>[
    {
      'id': 'afastamento-1',
      'empresa_id': 'empresa-1',
      'funcionario_id': 'funcionario-2',
      'tipo': 'FERIAS',
      'data_inicio': '2026-10-03',
      'data_fim': '2026-10-07',
      'anexo_url': null,
    },
  ];
  final historico = <Map<String, dynamic>>[
    {
      'id': 'historico-1',
      'empresa_id': 'empresa-1',
      'funcionario_id': 'funcionario-1',
      'setor_id': 'setor-1',
      'escala_nome': 'Comercial 08h–17h',
      'data_inicio': '2026-07-01',
      'data_fim': '2026-10-10',
    },
    {
      'id': 'historico-2',
      'empresa_id': 'empresa-1',
      'funcionario_id': 'funcionario-1',
      'setor_id': 'setor-2',
      'escala_nome': 'Comercial 09h–18h',
      'data_inicio': '2026-10-11',
      'data_fim': null,
    },
    {
      'id': 'historico-3',
      'empresa_id': 'empresa-1',
      'funcionario_id': 'funcionario-2',
      'setor_id': 'setor-1',
      'escala_nome': 'Comercial 08h–17h',
      'data_inicio': '2026-07-01',
      'data_fim': null,
    },
  ];
  int _seq = 3;
  Completer<void>? readGate;
  Object? reportOverride;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path.endsWith('/auth/me')) {
      requests.add(options);
      return jsonResponse({'usuario': sessionFor(role).user.toJson()});
    }
    final path = options.uri.path;
    if (!(path.contains('/feriados') ||
        path.contains('/afastamentos') ||
        path.endsWith('/equipe') ||
        path.endsWith('/relatorios/espelho'))) {
      return super.fetch(options, requestStream, cancelFuture);
    }
    requests.add(options);
    if (options.method == 'GET') await readGate?.future;
    if (options.method != 'GET') await writeGate?.future;
    if (handler != null) return handler!(options);
    if (nextStatus != null) {
      final response = jsonResponse(nextBody, nextStatus!);
      nextStatus = null;
      nextBody = null;
      return response;
    }
    if (path.endsWith('/equipe')) {
      return jsonResponse({
        'funcionarios': funcionarios,
        'setores': setores,
        'historico': historico,
      });
    }
    if (path.endsWith('/relatorios/espelho')) {
      return jsonResponse({
        'espelho':
            reportOverride ??
            report(
              options.queryParameters['funcionario_id'] as String,
              int.parse(options.queryParameters['ano'].toString()),
              int.parse(options.queryParameters['mes'].toString()),
            ),
      });
    }
    final feriado = path.contains('/feriados');
    final rows = feriado ? feriados : afastamentos;
    final plural = feriado ? 'feriados' : 'afastamentos';
    final singular = feriado ? 'feriado' : 'afastamento';
    if (options.method == 'GET') return jsonResponse({plural: rows});
    final id = options.uri.pathSegments.last;
    if (options.method == 'DELETE') {
      rows.removeWhere((r) => r['id'] == id);
      return jsonResponse({'id': id, 'removido': true});
    }
    final raw = options.data;
    final values = raw is FormData
        ? <String, dynamic>{for (final f in raw.fields) f.key: f.value}
        : Map<String, dynamic>.from(raw as Map);
    final row = options.method == 'POST'
        ? {
            'id': '$singular-${_seq++}',
            'empresa_id': 'empresa-1',
            if (!feriado) 'anexo_url': null,
            ...values,
          }
        : rows.firstWhere((r) => r['id'] == id);
    row.addAll(values);
    if (raw is FormData && raw.files.isNotEmpty) {
      row['anexo_url'] =
          'https://api.example.com/api/web/afastamentos/${row['id']}/anexo';
    }
    if (options.method == 'POST') rows.add(row);
    return jsonResponse({singular: row}, options.method == 'POST' ? 201 : 200);
  }

  Map<String, dynamic> report(String fid, int year, int month) {
    final person = funcionarios.firstWhere((f) => f['id'] == fid);
    final histories = historico
        .where((h) => h['funcionario_id'] == fid)
        .toList();
    final days = <Map<String, dynamic>>[];
    for (var d = 1; d <= DateTime(year, month + 1, 0).day; d++) {
      final date = DateTime(year, month, d),
          iso =
              '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final h = histories
          .where(
            (a) =>
                (a['data_inicio'] as String).compareTo(iso) <= 0 &&
                (a['data_fim'] == null ||
                    (a['data_fim'] as String).compareTo(iso) >= 0),
          )
          .firstOrNull;
      final hol = feriados
          .where(
            (f) =>
                f['data'] == iso &&
                (f['setor_id'] == null || f['setor_id'] == h?['setor_id']),
          )
          .toList();
      final leaves = afastamentos
          .where(
            (a) =>
                a['funcionario_id'] == fid &&
                (a['data_inicio'] as String).compareTo(iso) <= 0 &&
                (a['data_fim'] as String).compareTo(iso) >= 0,
          )
          .toList();
      final previsto = h != null && date.weekday <= 5 ? 480 : 0;
      final abono = h != null && (hol.isNotEmpty || leaves.isNotEmpty);
      final sector = setores
          .where((s) => s['id'] == h?['setor_id'])
          .firstOrNull;
      days.add({
        'data': iso,
        'status': h == null
            ? 'SEM_ALOCACAO'
            : abono
            ? 'ABONADO_JUSTIFICADO'
            : previsto == 0
            ? 'FOLGA'
            : 'TRABALHADO',
        'minutos_previstos': previsto,
        'minutos_trabalhados': abono ? 0 : previsto,
        'minutos_abonados': abono ? previsto : 0,
        'minutos_faltas': 0,
        'minutos_atrasos': 0,
        'intervalos_previstos': h == null
            ? []
            : [
                {
                  'setor_nome': sector!['nome'],
                  'escala_nome': h['escala_nome'],
                },
              ],
        'feriados': hol,
        'afastamentos': leaves,
        'pendencias': [],
      });
    }
    return {
      'empresa_id': 'empresa-1',
      'funcionario': person,
      'ano': year,
      'mes': month,
      'fuso_horario': 'America/Sao_Paulo',
      'apuracao_definitiva': false,
      'tem_pendencias': false,
      'alocacoes_historicas': [],
      'dias': days,
      'totais': {
        for (final k in [
          'previstos',
          'trabalhados',
          'abonados',
          'faltas',
          'atrasos',
          'exigiveis',
        ])
          'minutos_$k': days.fold<int>(
            0,
            (sum, d) => sum + ((d['minutos_$k'] ?? 0) as int),
          ),
      },
    };
  }
}
