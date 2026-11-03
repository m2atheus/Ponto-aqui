import 'package:dio/dio.dart';

import '../models/alocacao.dart';
import '../models/funcionario.dart';
import '../models/setor.dart';
import '../models/management_json.dart';
import 'repository_failure.dart';

class AlocacoesResumo {
  const AlocacoesResumo(this.alocacoes, this.funcionarios, this.setores);
  final List<Alocacao> alocacoes;
  final List<Funcionario> funcionarios;
  final List<Setor> setores;
}

class OpcaoMudancaAlocacao {
  const OpcaoMudancaAlocacao(this.id, this.nome);
  final String id, nome;
}

class AlocacaoRepository {
  AlocacaoRepository(this._dio, {required this.empresaId});
  final Dio _dio;
  final String empresaId;

  Alocacao _parse(Object? value) {
    final dto = Alocacao.fromJson(value);
    _validate(dto);
    return dto;
  }

  void _validate(Alocacao dto) {
    if (dto.empresaId != null && dto.empresaId != empresaId) {
      throw const RepositoryFailure(
        'A alocação não pertence à empresa da sessão.',
      );
    }
    managementString(dto.funcionarioId, 'funcionario_id');
    managementString(dto.setorId, 'setor_id');
    final inicio = managementDate(dto.dataInicio, 'data_inicio');
    if (dto.dataFim != null &&
        managementDate(dto.dataFim, 'data_fim').compareTo(inicio) < 0) {
      throw const RepositoryFailure(
        'A data final não pode ser anterior à inicial.',
      );
    }
  }

  Future<List<Alocacao>> listar({
    String? funcionarioId,
    CancelToken? cancelToken,
  }) => repositoryRequest(() async {
    final response = await _dio.get<Object?>(
      'alocacoes',
      queryParameters: {'funcionario_id': ?funcionarioId},
      cancelToken: cancelToken,
    );
    final raw = response.data;
    final items = raw is List ? raw : managementObject(raw)['alocacoes'];
    if (items is! List) {
      throw const FormatException('Lista de alocações inválida.');
    }
    return List<Alocacao>.unmodifiable(items.map(_parse));
  });

  Alocacao _single(Object? raw) {
    final json = managementObject(raw);
    return _parse(json.containsKey('alocacao') ? json['alocacao'] : json);
  }

  Future<AlocacoesResumo> listarComReferencias({CancelToken? cancelToken}) =>
      repositoryRequest(() async {
        final response = await _dio.get<Object?>(
          'alocacoes',
          cancelToken: cancelToken,
        );
        final j = managementObject(response.data);
        if (j['alocacoes'] is! List ||
            j['funcionarios'] is! List ||
            j['setores'] is! List) {
          throw const FormatException('Resposta de alocações inválida.');
        }
        final pessoas = (j['funcionarios'] as List)
            .map(Funcionario.fromJson)
            .toList();
        final setores = (j['setores'] as List).map(Setor.fromJson).toList();
        if (pessoas.any((f) => f.empresaId != empresaId) ||
            setores.any((s) => s.empresaId != empresaId)) {
          throw const FormatException(
            'Referências incompatíveis com a empresa.',
          );
        }
        return AlocacoesResumo(
          (j['alocacoes'] as List).map(_parse).toList(),
          pessoas,
          setores,
        );
      });

  Future<Alocacao> criar(Alocacao dto) => repositoryRequest(() async {
    _validate(dto);
    // Sobreposição é validada pela API, inclusive entre chamadas concorrentes.
    final response = await _dio.post<Object?>(
      'alocacoes',
      data: dto.toRequestJson(),
    );
    return _single(response.data);
  });

  Future<List<OpcaoMudancaAlocacao>> opcoesMudanca(
    String tipo,
    String busca, {
    CancelToken? cancelToken,
  }) => repositoryRequest(() async {
    final response = await _dio.get<Object?>(
      'alocacoes/opcoes-mudanca',
      queryParameters: {'tipo': tipo, 'q': busca.trim()},
      cancelToken: cancelToken,
    );
    final raw = managementObject(response.data)['opcoes'];
    if (raw is! List || raw.length > 20) {
      throw const FormatException('Opções de mudança inválidas.');
    }
    return raw
        .map((item) {
          final j = managementObject(item);
          if (j['empresa_id'] != empresaId) {
            throw const FormatException('Empresa incompatível.');
          }
          return OpcaoMudancaAlocacao(
            managementString(j['id'], 'id'),
            managementString(j['nome'], 'nome'),
          );
        })
        .toList(growable: false);
  });

  Future<({Alocacao anterior, Alocacao nova})> mudarAlocacao({
    required Alocacao atual,
    required String novoSetorId,
    required String? novaEscalaId,
    required String dataTransicao,
    String? dataEncerramento,
  }) => repositoryRequest(() async {
    _validate(atual);
    final transicao = managementDate(dataTransicao, 'data_transicao');
    final encerramento = dataEncerramento == null
        ? null
        : managementDate(dataEncerramento, 'data_encerramento');
    if (transicao.compareTo(atual.dataInicio) <= 0 ||
        (encerramento != null &&
            (encerramento.compareTo(atual.dataInicio) < 0 ||
                encerramento.compareTo(transicao) >= 0)) ||
        (atual.dataFim != null &&
            (encerramento ?? transicao).compareTo(atual.dataFim!) > 0)) {
      throw const RepositoryFailure(
        'A data da mudança deve estar dentro da vigência, após o início atual.',
      );
    }
    final response = await _dio.post<Object?>(
      'funcionarios/${repositoryResourceId(atual.funcionarioId)}/mudar-alocacao',
      data: {
        'alocacao_id': repositoryResourceId(atual.id),
        'novo_setor_id': repositoryResourceId(novoSetorId),
        'nova_escala_id': novaEscalaId == null
            ? null
            : repositoryResourceId(novaEscalaId),
        'data_transicao': transicao,
        'data_encerramento': ?encerramento,
      },
    );
    final j = managementObject(response.data);
    final anterior = _parse(j['alocacao_anterior']),
        nova = _parse(j['alocacao']);
    final data = DateTime.parse(transicao);
    final fimEsperado = DateTime.utc(
      data.year,
      data.month,
      data.day,
    ).subtract(const Duration(days: 1));
    final fimIso =
        encerramento ??
        '${fimEsperado.year.toString().padLeft(4, '0')}-${fimEsperado.month.toString().padLeft(2, '0')}-${fimEsperado.day.toString().padLeft(2, '0')}';
    if (response.statusCode != 201 ||
        anterior.id != atual.id ||
        anterior.funcionarioId != atual.funcionarioId ||
        anterior.setorId != atual.setorId ||
        anterior.escalaId != atual.escalaId ||
        anterior.dataInicio != atual.dataInicio ||
        anterior.dataFim != fimIso ||
        nova.id == anterior.id ||
        nova.funcionarioId != atual.funcionarioId ||
        nova.setorId != novoSetorId ||
        nova.escalaId != novaEscalaId ||
        nova.dataInicio != transicao ||
        nova.dataFim != null) {
      throw const FormatException(
        'Mudança não confirmada ou histórico incompatível.',
      );
    }
    return (anterior: anterior, nova: nova);
  });

  Future<Alocacao> encerrarAlocacao(
    Alocacao atual, {
    required String dataFim,
  }) => atualizar(
    Alocacao(
      id: atual.id,
      funcionarioId: atual.funcionarioId,
      setorId: atual.setorId,
      escalaId: atual.escalaId,
      empresaId: atual.empresaId,
      dataInicio: atual.dataInicio,
      dataFim: dataFim,
    ),
  );

  Future<Alocacao> atualizar(Alocacao dto) => repositoryRequest(() async {
    _validate(dto);
    final id = repositoryResourceId(dto.id);
    if (dto.dataFim == null) {
      throw const RepositoryFailure(
        'Informe a data de encerramento da alocação.',
      );
    }
    // PUT encerra o vínculo. Uma troca de setor/escala exige NOVA alocação.
    final response = await _dio.put<Object?>(
      'alocacoes/$id',
      data: {'data_fim': dto.dataFim},
    );
    final saved = _single(response.data);
    if (saved.id != dto.id ||
        saved.funcionarioId != dto.funcionarioId ||
        saved.setorId != dto.setorId ||
        saved.dataInicio != dto.dataInicio ||
        saved.dataFim != dto.dataFim ||
        saved.escalaId != dto.escalaId) {
      throw const FormatException(
        'Histórico da alocação alterado ou encerramento não confirmado.',
      );
    }
    return saved;
  });
}
