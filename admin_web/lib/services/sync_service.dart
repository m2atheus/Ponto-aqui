import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mobile_sync_dto.dart';

class SyncFailure implements Exception {
  const SyncFailure(this.codigo, this.mensagem, {this.statusCode});
  final String codigo;
  final String mensagem;
  final int? statusCode;
  @override
  String toString() => mensagem;
}

class SyncSnapshot {
  const SyncSnapshot({
    required this.dados,
    required this.clockOffsetMs,
    required this.recebidoEm,
  });
  final MobileSyncDto dados;
  // Positivo: celular atrasado. UTC estimado = relógio local UTC + offset.
  final int clockOffsetMs;
  final DateTime recebidoEm;

  Map<String, dynamic> toJson() => {
    'versao': 1,
    'clock_offset_ms': clockOffsetMs,
    'recebido_em': recebidoEm.toUtc().toIso8601String(),
    'dados': dados.toJson(),
  };

  factory SyncSnapshot.fromJson(Object? value) {
    if (value is! Map ||
        value['versao'] != 1 ||
        value['clock_offset_ms'] is! int) {
      throw const FormatException('Snapshot local inválido.');
    }
    return SyncSnapshot(
      dados: MobileSyncDto.fromJson(value['dados']),
      clockOffsetMs: value['clock_offset_ms'] as int,
      recebidoEm: parseTimestampUtc(value['recebido_em']),
    );
  }
}

/// Módulo portátil, sem dependência dos perfis ou telas do painel Web.
/// Possui seu próprio Dio: o interceptor do painel não substitui o JWT mobile.
class SyncService {
  SyncService({
    required String apiBaseUrl,
    required this.preferences,
    HttpClientAdapter? adapter,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _endpoint = _syncUri(apiBaseUrl),
       _dio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 15),
           sendTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 30),
           responseType: ResponseType.json,
           headers: {'Accept': 'application/json'},
           followRedirects: false,
           validateStatus: (status) => status == 200,
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  final SharedPreferencesAsync preferences;
  final DateTime Function() _now;
  final Uri _endpoint;
  final Dio _dio;

  static Uri _syncUri(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError(
        'Informe a URL HTTP(S) da API, sem credenciais ou parâmetros.',
      );
    }
    return uri.resolve('/api/v1/mobile/sync');
  }

  String _cacheKey(String token, String deviceUuid) {
    // Claims servem somente para separar caches. A assinatura e as permissões
    // são validadas pelo Flask; não verificamos exp usando o relógio impreciso.
    if (token.trim().isEmpty ||
        RegExp(r'\s').hasMatch(token) ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(deviceUuid)) {
      throw const SyncFailure(
        'SESSAO_INVALIDA',
        'Informe JWT e UUID de aparelho válidos.',
      );
    }
    try {
      final parts = token.split('.');
      if (parts.length != 3) throw const FormatException();
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is! Map ||
          claims['sub'] is! String ||
          claims['empresa_id'] is! String ||
          (claims['sub'] as String).isEmpty ||
          (claims['empresa_id'] as String).isEmpty) {
        throw const FormatException();
      }
      final scope = [
        _endpoint.origin,
        claims['empresa_id'] as String,
        claims['sub'] as String,
        deviceUuid.toLowerCase(),
      ];
      return 'ponto_aqui_mobile_sync_${scope.map(Uri.encodeComponent).join('|')}';
    } on FormatException {
      throw const SyncFailure(
        'SESSAO_INVALIDA',
        'JWT sem contexto válido de usuário e empresa.',
      );
    }
  }

  Future<SyncSnapshot> sincronizar({
    required String tokenJwt,
    required String deviceUuid,
  }) async {
    final token = tokenJwt.trim();
    final device = deviceUuid.trim().toLowerCase();
    final key = _cacheKey(token, device);
    Response<Object?> response;
    try {
      response = await _dio.getUri<Object?>(
        _endpoint,
        options: Options(
          headers: {'Authorization': 'Bearer $token', 'X-Device-UUID': device},
        ),
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        try {
          await preferences.remove(key);
        } catch (_) {
          throw SyncFailure(
            'CACHE_INDISPONIVEL',
            'Sessão recusada; não foi possível limpar a carga local.',
            statusCode: status,
          );
        }
      }
      final body = error.response?.data;
      final detail = body is Map ? body['erro'] : null;
      throw SyncFailure(
        detail is Map && detail['codigo'] is String
            ? detail['codigo'] as String
            : 'SYNC_INDISPONIVEL',
        detail is Map && detail['mensagem'] is String
            ? detail['mensagem'] as String
            : 'Não foi possível sincronizar. Verifique a conexão e tente novamente.',
        statusCode: status,
      );
    }
    final recebidoEm = _now().toUtc();
    late final SyncSnapshot snapshot;
    try {
      final dto = MobileSyncDto.fromJson(response.data);
      final headerTime = response.headers.value('X-Server-Timestamp');
      if (headerTime != null &&
          parseTimestampUtc(headerTime) != dto.serverTimestamp) {
        throw const FormatException('Hora do servidor inconsistente.');
      }
      snapshot = SyncSnapshot(
        dados: dto,
        // Amostra no recebimento, conforme o contrato W08. Inclui a latência
        // da resposta; é uma estimativa, não um ajuste físico do relógio.
        clockOffsetMs: dto.serverTimestamp
            .difference(recebidoEm)
            .inMilliseconds,
        recebidoEm: recebidoEm,
      );
    } on FormatException {
      throw const SyncFailure(
        'PAYLOAD_INVALIDO',
        'A API retornou uma carga de sincronização inválida.',
      );
    }
    try {
      // Carga e offset são confirmados juntos em uma única chave. Sem JWT.
      // Falhas de rede/DTO não substituem a última carga válida.
      await preferences.setString(key, jsonEncode(snapshot.toJson()));
    } catch (_) {
      throw const SyncFailure(
        'CACHE_INDISPONIVEL',
        'Não foi possível salvar a sincronização no aparelho.',
      );
    }
    return snapshot;
  }

  Future<SyncSnapshot?> lerUltimaSincronizacao({
    required String tokenJwt,
    required String deviceUuid,
  }) async {
    final key = _cacheKey(tokenJwt.trim(), deviceUuid.trim().toLowerCase());
    try {
      final raw = await preferences.getString(key);
      return raw == null ? null : SyncSnapshot.fromJson(jsonDecode(raw));
    } on FormatException {
      throw const SyncFailure(
        'CACHE_INVALIDO',
        'Carga offline inválida. Sincronize novamente.',
      );
    } catch (_) {
      throw const SyncFailure(
        'CACHE_INDISPONIVEL',
        'Não foi possível acessar a carga offline.',
      );
    }
  }

  Future<int?> lerClockOffsetMs({
    required String tokenJwt,
    required String deviceUuid,
  }) async => (await lerUltimaSincronizacao(
    tokenJwt: tokenJwt,
    deviceUuid: deviceUuid,
  ))?.clockOffsetMs;

  Future<DateTime?> agoraServidorEstimado({
    required String tokenJwt,
    required String deviceUuid,
  }) async {
    final offset = await lerClockOffsetMs(
      tokenJwt: tokenJwt,
      deviceUuid: deviceUuid,
    );
    return offset == null
        ? null
        : _now().toUtc().add(Duration(milliseconds: offset));
  }

  void dispose() => _dio.close(force: true);
}
