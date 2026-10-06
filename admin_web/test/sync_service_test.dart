import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_sync_dto_test.dart' show example;

class MemoryPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};
  final failures = <String>{};
  bool get failWrites => failures.contains('write');
  set failWrites(bool value) {
    value ? failures.add('write') : failures.remove('write');
  }

  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    if (failWrites) throw StateError('Armazenamento indisponível');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SyncAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Object? payload = example('pessoal');
  int status = 200;
  bool offline = false;
  String? timestampHeader;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (timestampHeader != null) 'x-server-timestamp': [timestampHeader!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const deviceUuid = '88888888-8888-4888-8888-888888888888';
String token({String user = 'user-1', String company = 'company-1'}) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'empresa_id': company, 'exp': 1}))).replaceAll('=', '')}.signature';

Matcher failure(String code, {int? status}) => isA<SyncFailure>()
    .having((error) => error.codigo, 'código', code)
    .having((error) => error.statusCode, 'HTTP status', status);

void main() {
  late MemoryPreferences preferences;
  late SyncAdapter adapter;
  late SyncService service;
  late DateTime localNow;
  setUp(() {
    preferences = MemoryPreferences();
    adapter = SyncAdapter();
    localNow = DateTime.utc(2026, 10, 5, 14, 59, 55);
    service = SyncService(
      apiBaseUrl: 'https://api.example/api/web',
      preferences: preferences,
      adapter: adapter,
      now: () => localNow,
    );
  });
  tearDown(() => service.dispose());

  Future<SyncSnapshot> sync() =>
      service.sincronizar(tokenJwt: token(), deviceUuid: deviceUuid);
  Future<SyncSnapshot?> read() =>
      service.lerUltimaSincronizacao(tokenJwt: token(), deviceUuid: deviceUuid);

  test(
    'envia JWT e UUID à rota mobile e salva offset positivo sem JWT',
    () async {
      final result = await sync();
      expect(
        adapter.requests.single.uri.toString(),
        'https://api.example/api/v1/mobile/sync',
      );
      expect(adapter.requests.single.method, 'GET');
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer ${token()}',
      );
      expect(adapter.requests.single.headers['X-Device-UUID'], deviceUuid);
      expect(result.clockOffsetMs, 5000);
      final persisted = jsonDecode(preferences.values.values.single) as Map;
      expect(persisted['clock_offset_ms'], 5000);
      expect(preferences.values.values.single, isNot(contains(token())));
      expect(await read(), isNotNull);
      expect(
        await service.agoraServidorEstimado(
          tokenJwt: token(),
          deviceUuid: deviceUuid,
        ),
        DateTime.utc(2026, 10, 5, 15),
      );
    },
  );

  test(
    'offset negativo e milissegundos sobrevivem à recriação do serviço',
    () async {
      localNow = DateTime.utc(2026, 10, 5, 15, 0, 2, 750);
      await sync();
      final restarted = SyncService(
        apiBaseUrl: 'https://api.example',
        preferences: preferences,
      );
      addTearDown(restarted.dispose);
      final cached = await restarted.lerUltimaSincronizacao(
        tokenJwt: token(),
        deviceUuid: deviceUuid,
      );
      expect(cached!.clockOffsetMs, -2750);
      expect(cached.dados.funcionario!.nome, 'Ana Silva');
      expect(cached.recebidoEm, localNow);
    },
  );

  test('HTTP 200 sem escala é uma sincronização válida', () async {
    adapter.payload = example('pessoal')
      ..['status'] = 'SEM_ALOCACAO'
      ..['setor'] = null
      ..['escala'] = null
      ..['alocacoes'] = [];
    final result = await sync();
    expect(result.dados.status, 'SEM_ALOCACAO');
    expect(result.dados.setor, isNull);
    expect(result.dados.escala, isNull);
    expect((await read())!.dados.escala, isNull);
  });

  test('modo relógio também é persistido para funcionamento offline', () async {
    adapter.payload = example('relogio');
    await sync();
    final cached = await read();
    expect(cached!.dados.funcionarios.single.funcionario.matricula, '001');
    expect(cached.dados.escalas.single.turnos.single.horaInicio, '19:00');
  });

  for (final cause in ['timeout', '503', 'JSON', 'timestamp']) {
    test(
      '$cause preserva última carga válida sem simular novo sucesso',
      () async {
        await sync();
        final previous = Map<String, String>.from(preferences.values);
        var code = 'SYNC_INDISPONIVEL';
        int? status;
        switch (cause) {
          case 'timeout':
            adapter.offline = true;
          case '503':
            adapter.status = status = 503;
          case 'JSON':
            adapter.payload = {'server_timestamp': 'inválido'};
            code = 'PAYLOAD_INVALIDO';
          case 'timestamp':
            adapter.timestampHeader = '2026-10-05T16:00:00Z';
            code = 'PAYLOAD_INVALIDO';
        }
        await expectLater(sync(), throwsA(failure(code, status: status)));
        expect(preferences.values, previous);
        expect((await read())!.clockOffsetMs, 5000);
      },
    );
  }

  for (final status in [401, 403]) {
    test('$status invalida a carga da sessão recusada', () async {
      await sync();
      adapter.status = status;
      adapter.payload = {
        'erro': {'codigo': 'SESSAO_RECUSADA', 'mensagem': 'Sessão recusada.'},
      };
      await expectLater(
        sync(),
        throwsA(failure('SESSAO_RECUSADA', status: status)),
      );
      expect(await read(), isNull);
    });
  }

  test(
    'contas, empresas, aparelhos e servidores não compartilham cache',
    () async {
      await sync();
      for (final other in [
        token(user: 'user-2'),
        token(company: 'company-2'),
      ]) {
        expect(
          await service.lerUltimaSincronizacao(
            tokenJwt: other,
            deviceUuid: deviceUuid,
          ),
          isNull,
        );
      }
      expect(
        await service.lerUltimaSincronizacao(
          tokenJwt: token(),
          deviceUuid: '99999999-9999-4999-8999-999999999999',
        ),
        isNull,
      );
      final otherApi = SyncService(
        apiBaseUrl: 'https://other.example',
        preferences: preferences,
      );
      addTearDown(otherApi.dispose);
      expect(
        await otherApi.lerUltimaSincronizacao(
          tokenJwt: token(),
          deviceUuid: deviceUuid,
        ),
        isNull,
      );
    },
  );

  test('falha ao persistir não anuncia sincronização completa', () async {
    await sync();
    final previous = Map<String, String>.from(preferences.values);
    preferences.failWrites = true;
    await expectLater(sync(), throwsA(failure('CACHE_INDISPONIVEL')));
    expect(preferences.values, previous);
  });

  test('cache corrompido gera erro tratável', () async {
    await sync();
    preferences.values[preferences.values.keys.single] = '{inválido';
    await expectLater(read(), throwsA(failure('CACHE_INVALIDO')));
  });

  test(
    'sem sincronização o offset é desconhecido, não presumido como zero',
    () async {
      expect(
        await service.lerClockOffsetMs(
          tokenJwt: token(),
          deviceUuid: deviceUuid,
        ),
        isNull,
      );
      expect(
        await service.agoraServidorEstimado(
          tokenJwt: token(),
          deviceUuid: deviceUuid,
        ),
        isNull,
      );
    },
  );

  test('sessão ou UUID inválidos falham antes da requisição', () async {
    await expectLater(
      service.sincronizar(tokenJwt: 'inválido', deviceUuid: deviceUuid),
      throwsA(failure('SESSAO_INVALIDA')),
    );
    await expectLater(
      service.sincronizar(tokenJwt: token(), deviceUuid: 'aparelho'),
      throwsA(failure('SESSAO_INVALIDA')),
    );
    expect(adapter.requests, isEmpty);
  });
}
