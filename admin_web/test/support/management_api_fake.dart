import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';

import 'auth_fakes.dart';

Map<String, dynamic> funcionarioJson({String empresaId = 'empresa-1'}) => {
  'id': 'funcionario-1',
  'nome': 'Ana Silva',
  'matricula': '001',
  'cargo': null,
  'empresa_id': empresaId,
  'ativo': true,
};

Map<String, dynamic> alocacaoJson() => {
  'id': 'alocacao-1',
  'funcionario_id': 'funcionario-1',
  'setor_id': 'setor-1',
  'data_inicio': '2026-10-01',
  'data_fim': null,
  'empresa_id': 'empresa-1',
  'escala_id': 'escala-1',
};

Map<String, dynamic> setorJson() => {
  'id': 'setor-1',
  'nome': 'Sede',
  'empresa_id': 'empresa-1',
  'ativo': true,
  'endereco': 'Rua do Trabalho, 100',
  'latitude': -8.0476,
  'longitude': -34.877,
  'raio_metros': 100,
  'exige_selfie': false,
  'acao_fora_perimetro': 'BLOQUEAR',
  'ignorar_localizacao': false,
};

ResponseBody jsonResponse(Object? body, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

// Simula somente o contrato HTTP nos testes; não é usado pela aplicação.
class ManagementApiFake implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final funcionarios = [funcionarioJson()];
  final alocacoes = [alocacaoJson()];
  Map<String, dynamic> get alocacao => alocacoes.first;
  final setores = <Map<String, dynamic>>[setorJson()];
  int? nextStatus;
  Object? nextBody;
  Completer<void>? writeGate;
  FutureOr<ResponseBody> Function(RequestOptions)? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (handler != null) return handler!(options);
    if (options.uri.path.endsWith('/auth/me')) {
      return jsonResponse({'usuario': sessionFor(UserRole.rh).user.toJson()});
    }
    if (options.method != 'GET') await writeGate?.future;
    if (nextStatus != null) {
      final status = nextStatus!;
      final body = nextBody;
      nextStatus = null;
      nextBody = null;
      return jsonResponse(body, status);
    }
    if (options.uri.path.contains('/funcionarios')) {
      if (options.method == 'GET') {
        return jsonResponse({'funcionarios': funcionarios});
      }
      final values = Map<String, dynamic>.from(options.data as Map);
      if (options.method == 'POST') {
        final row = {
          ...values,
          'id': 'funcionario-${funcionarios.length + 1}',
          'empresa_id': 'empresa-1',
          'ativo': true,
        };
        funcionarios.add(row);
        return jsonResponse({'funcionario': row}, 201);
      }
      final row = funcionarios.firstWhere(
        (item) => item['id'] == options.uri.pathSegments.last,
      )..addAll(values);
      return jsonResponse({'funcionario': row});
    }
    if (options.uri.path.contains('/setores')) {
      if (options.method == 'GET') {
        return jsonResponse({'setores': setores});
      }
      if (options.method == 'DELETE') {
        setores.removeWhere(
          (row) => row['id'] == options.uri.pathSegments.last,
        );
        return ResponseBody.fromString('', 204);
      }
      final values = Map<String, dynamic>.from(options.data as Map);
      if (options.method == 'POST') {
        final row = {
          ...values,
          'id': 'setor-${setores.length + 1}',
          'empresa_id': 'empresa-1',
          'ativo': true,
        };
        setores.add(row);
        return jsonResponse({'setor': row}, 201);
      }
      final row = setores.firstWhere(
        (item) => item['id'] == options.uri.pathSegments.last,
      )..addAll(values);
      return jsonResponse({'setor': row});
    }
    if (options.method == 'GET') {
      return jsonResponse({'alocacoes': alocacoes});
    }
    final values = Map<String, dynamic>.from(options.data as Map);
    if (options.method == 'POST') {
      final row = {
        ...values,
        'id': 'alocacao-${alocacoes.length + 1}',
        'empresa_id': 'empresa-1',
        'escala_id': values['escala_id'],
      };
      alocacoes.add(row);
      return jsonResponse({'alocacao': row}, 201);
    }
    final row = alocacoes.firstWhere(
      (item) => item['id'] == options.uri.pathSegments.last,
    )..addAll(values);
    return jsonResponse({'alocacao': row});
  }

  @override
  void close({bool force = false}) {}
}
