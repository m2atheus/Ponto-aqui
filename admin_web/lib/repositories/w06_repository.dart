import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/funcionario.dart';
import '../models/management_json.dart';
import '../models/w06.dart';
import 'repository_failure.dart';

class W06Repository {
  W06Repository(this.dio, {required this.empresaId});
  final Dio dio;
  final String empresaId;
  Map<String, dynamic> _tenant(Object? value) {
    final j = managementObject(value);
    if (j['empresa_id'] != empresaId) {
      throw const RepositoryFailure(
        'Resposta incompatível com a empresa da sessão.',
      );
    }
    return j;
  }

  List<Object?> _lista(Object? value, String campo) {
    final items = managementObject(value)[campo];
    if (items is! List) throw FormatException('Lista $campo inválida.');
    return items;
  }

  Future<W06Data> carregar({CancelToken? cancelToken}) =>
      repositoryRequest(() async {
        final respostas = await Future.wait([
          dio.get<Object?>('equipe', cancelToken: cancelToken),
          dio.get<Object?>('feriados', cancelToken: cancelToken),
          dio.get<Object?>('afastamentos', cancelToken: cancelToken),
        ]);
        return W06Data(
          funcionarios: _lista(
            respostas[0].data,
            'funcionarios',
          ).map((j) => Funcionario.fromJson(_tenant(j))),
          setores: _lista(
            respostas[0].data,
            'setores',
          ).map((j) => SetorResumo.fromJson(_tenant(j))),
          historico: _lista(
            respostas[0].data,
            'historico',
          ).map((j) => HistoricoAlocacao.fromJson(_tenant(j))),
          feriados: _lista(
            respostas[1].data,
            'feriados',
          ).map((j) => FeriadoResumo.fromJson(_tenant(j))),
          afastamentos: _lista(
            respostas[2].data,
            'afastamentos',
          ).map((j) => AfastamentoResumo.fromJson(_tenant(j))),
        );
      });

  Future<void> criarFeriado({
    required String data,
    required String descricao,
    String? setorId,
  }) => salvarFeriado(data: data, descricao: descricao, setorId: setorId);
  Future<void> salvarFeriado({
    String? id,
    required String data,
    required String descricao,
    String? setorId,
  }) => repositoryRequest(() async {
    final payload = {
      'data': data,
      'descricao': descricao.trim(),
      'setor_id': setorId,
    };
    final response = id == null
        ? await dio.post<Object?>('feriados', data: payload)
        : await dio.put<Object?>(
            'feriados/${repositoryResourceId(id)}',
            data: payload,
          );
    final saved = FeriadoResumo.fromJson(
      _tenant(managementObject(response.data)['feriado']),
    );
    if (id != null && saved.id != id) {
      throw const FormatException('Feriado não confirmado.');
    }
  });

  Future<void> criarAfastamento({
    required String funcionarioId,
    required TipoAfastamento tipo,
    required String inicio,
    required String fim,
    AnexoLocal? anexo,
  }) => salvarAfastamento(
    funcionarioId: funcionarioId,
    tipo: tipo,
    inicio: inicio,
    fim: fim,
    anexo: anexo,
  );

  Future<void> salvarAfastamento({
    String? id,
    required String funcionarioId,
    required TipoAfastamento tipo,
    required String inicio,
    required String fim,
    AnexoLocal? anexo,
    bool removerAnexo = false,
  }) => repositoryRequest(() async {
    final payload = <String, dynamic>{
      if (id == null) 'funcionario_id': funcionarioId,
      'tipo': tipo.apiValue,
      'data_inicio': inicio,
      'data_fim': fim,
      if (removerAnexo) 'anexo_url': null,
    };
    Object body = payload;
    if (anexo != null) {
      if (anexo.bytes == null ||
          anexo.bytes!.isEmpty ||
          anexo.bytes!.length > 10 * 1024 * 1024) {
        throw const RepositoryFailure(
          'Selecione novamente o arquivo do atestado.',
        );
      }
      payload.remove('anexo_url');
      body = FormData.fromMap({
        ...payload,
        'anexo': MultipartFile.fromBytes(anexo.bytes!, filename: anexo.nome),
      });
    }
    final response = id == null
        ? await dio.post<Object?>('afastamentos', data: body)
        : await dio.put<Object?>(
            'afastamentos/${repositoryResourceId(id)}',
            data: body,
          );
    final saved = AfastamentoResumo.fromJson(
      _tenant(managementObject(response.data)['afastamento']),
    );
    if (saved.funcionarioId != funcionarioId || id != null && saved.id != id) {
      throw const FormatException('Afastamento não confirmado.');
    }
  });

  Future<void> removerFeriado(String id) => _remover('feriados', id);
  Future<void> removerAfastamento(String id) => _remover('afastamentos', id);
  Future<void> _remover(String recurso, String id) =>
      repositoryRequest(() async {
        final response = await dio.delete<Object?>(
          '$recurso/${repositoryResourceId(id)}',
        );
        final j = managementObject(response.data);
        if (j['id'] != id || j['removido'] != true) {
          throw const FormatException('Remoção não confirmada.');
        }
      });

  Future<EspelhoMensal> espelho(String funcionarioId, int ano, int mes) =>
      repositoryRequest(() async {
        final response = await dio.get<Object?>(
          'relatorios/espelho',
          queryParameters: {
            'funcionario_id': funcionarioId,
            'ano': ano,
            'mes': mes,
          },
        );
        final dto = EspelhoMensal.fromJson(
          managementObject(response.data)['espelho'],
          empresaId,
        );
        if (dto.funcionario.id != funcionarioId ||
            dto.ano != ano ||
            dto.mes != mes) {
          throw const FormatException('Espelho de outro período.');
        }
        return dto;
      });

  Future<({Uint8List bytes, String mime, String nome})> baixarAnexo(
    String id,
  ) => repositoryRequest(() async {
    final response = await dio.get<List<int>>(
      'afastamentos/${repositoryResourceId(id)}/anexo',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Anexo vazio.');
    }
    final mime =
        response.headers.value('content-type')?.split(';').first ??
        'application/octet-stream';
    final ext = mime == 'application/pdf'
        ? 'pdf'
        : mime == 'image/png'
        ? 'png'
        : 'jpg';
    return (
      bytes: Uint8List.fromList(bytes),
      mime: mime,
      nome: 'atestado-$id.$ext',
    );
  });
}
