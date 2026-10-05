import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/services/storage/token_storage.dart';

class _MemoryTokenStorage implements TokenStorage {
  String? token;
  bool fail = false;
  int reads = 0;

  @override
  Future<String?> readAccessToken() async {
    reads++;
    if (fail) throw StateError('storage unavailable');
    return token;
  }

  @override
  Future<void> saveAccessToken(String value) async => token = value;

  @override
  Future<void> clearAccessToken() async => token = null;

  @override
  Future<Map<String, dynamic>?> readSession() async => null;

  @override
  Future<void> saveSession(Map<String, dynamic> session) async {
    token = session['access_token'] as String;
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _MemoryTokenStorage storage;
  late _RecordingAdapter adapter;
  late Dio dio;

  setUp(() {
    storage = _MemoryTokenStorage();
    adapter = _RecordingAdapter();
    dio = createDioClient(
      baseUrl: 'https://api.example.com/api/web',
      tokenStorage: storage,
    )..httpClientAdapter = adapter;
  });

  tearDown(() => dio.close(force: true));

  test('JWT acompanha cada método HTTP e preserva o prefixo da API', () async {
    storage.token = 'jwt-atual';
    for (final method in ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']) {
      await dio.request('setores', options: Options(method: method));
    }

    expect(storage.reads, 5);
    expect(adapter.requests.map((r) => r.method), [
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
    ]);
    for (final request in adapter.requests) {
      expect(request.headers['Authorization'], 'Bearer jwt-atual');
      expect(request.uri.toString(), 'https://api.example.com/api/web/setores');
    }
  });

  test('troca e remoção de sessão não reutilizam o JWT anterior', () async {
    storage.token = 'primeiro';
    await dio.get('setores');
    storage.token = 'segundo';
    await dio.get('setores');
    storage.token = null;
    await dio.get(
      'setores',
      options: Options(headers: {'authorization': 'Bearer antigo'}),
    );

    expect(adapter.requests[0].headers['Authorization'], 'Bearer primeiro');
    expect(adapter.requests[1].headers['Authorization'], 'Bearer segundo');
    expect(
      adapter.requests[2].headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('authorization')),
    );
  });

  test('chamadas públicas dispensam armazenamento e JWT', () async {
    storage.fail = true;
    await dio.post(
      'login',
      options: Options(
        extra: {'skipAuth': true},
        headers: {'Authorization': 'Bearer antigo'},
      ),
    );

    expect(storage.reads, 0);
    expect(
      adapter.requests.single.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('authorization')),
    );
  });

  test('destinos externos são bloqueados antes do envio', () async {
    storage.token = 'privado';
    for (final url in [
      'https://outro.example.com/coleta',
      'http://api.example.com/coleta',
      'https://api.example.com:8443/coleta',
    ]) {
      await expectLater(dio.get(url), throwsA(isA<DioException>()));
    }
    expect(storage.reads, 0);
    expect(adapter.requests, isEmpty);
  });

  test('falha no armazenamento impede uma requisição sem sessão', () async {
    storage.fail = true;
    await expectLater(dio.get('setores'), throwsA(isA<DioException>()));
    expect(adapter.requests, isEmpty);
  });

  test('JWT de teste não é enviado ao Flask', () async {
    storage.token = 'header.payload.ponto-aqui-mock';
    await expectLater(dio.get('setores'), throwsA(isA<DioException>()));
    expect(adapter.requests, isEmpty);
  });
}
