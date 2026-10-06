import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/alocacao.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/models/funcionario.dart';
import 'package:ponto_aqui_admin/repositories/alocacao_repository.dart';
import 'package:ponto_aqui_admin/repositories/funcionario_repository.dart';
import 'package:ponto_aqui_admin/repositories/repository_failure.dart';
import 'package:ponto_aqui_admin/repositories/setor_repository.dart';
import 'package:ponto_aqui_admin/utils/civil_date.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';

import 'support/auth_fakes.dart';
import 'support/management_api_fake.dart';

void main() {
  late ManagementApiFake adapter;
  late Dio dio;
  late FuncionarioRepository funcionarios;
  late AlocacaoRepository alocacoes;
  late MemoryTokenStorage storage;

  setUp(() {
    adapter = ManagementApiFake();
    storage = MemoryTokenStorage()..session = sessionFor(UserRole.rh).toJson();
    dio = createDioClient(
      baseUrl: 'https://api.example.com/api/web/',
      tokenStorage: storage,
    )..httpClientAdapter = adapter;
    funcionarios = FuncionarioRepository(dio, empresaId: 'empresa-1');
    alocacoes = AlocacaoRepository(dio, empresaId: 'empresa-1');
  });
  tearDown(() => dio.close(force: true));

  test(
    'setores de outra empresa e formato inválido não entram nos Dropdowns',
    () async {
      final repository = SetorRepository(dio, empresaId: 'empresa-1');
      expect((await repository.listar()).single.nome, 'Sede');
      adapter.setores.single['empresa_id'] = 'empresa-2';
      await expectLater(repository.listar(), throwsA(isA<RepositoryFailure>()));
      adapter.setores.single['empresa_id'] = 'empresa-1';
      adapter.setores.single['ativo'] = null;
      await expectLater(repository.listar(), throwsA(isA<RepositoryFailure>()));
    },
  );

  test('datas brasileiras válidas viram datas civis ISO sem fuso', () {
    expect(civilDateFromInput('29/02/2024'), '2024-02-29');
    expect(civilDateDisplay('2026-10-01'), '01/10/2026');
    for (final value in [
      '29/02/2026',
      '31/04/2026',
      '01/01/0000',
      '2026-10-01',
    ]) {
      expect(() => civilDateFromInput(value), throwsFormatException);
    }
  });

  test(
    'vínculo desativado após carregar os Dropdowns retorna mensagem da API',
    () async {
      adapter.nextStatus = 404;
      adapter.nextBody = {
        'erro': {
          'codigo': 'VINCULO_NAO_ENCONTRADO',
          'mensagem': 'Funcionário ou setor não está ativo nesta empresa.',
        },
      };
      await expectLater(
        alocacoes.criar(Alocacao.fromJson(alocacaoJson())),
        throwsA(
          isA<RepositoryFailure>().having(
            (e) => e.message,
            'vínculo inativo',
            'Funcionário ou setor não está ativo nesta empresa.',
          ),
        ),
      );
    },
  );

  test('DTOs preservam campos nulos, status e datas civis', () {
    final funcionario = Funcionario.fromJson(funcionarioJson());
    expect(funcionario.toJson(), funcionarioJson());
    expect(funcionario.cargo, isNull);
    expect(
      Funcionario.fromJson({...funcionarioJson(), 'ativo': false}).ativo,
      isFalse,
    );
    final alocacao = Alocacao.fromJson(alocacaoJson());
    expect(alocacao.toJson(), alocacaoJson());
    expect(alocacao.dataFim, isNull);
    expect(alocacao.dataInicio, '2026-10-01');
  });

  test('DTOs rejeitam JSON inválido e datas normalizadas ou invertidas', () {
    expect(() => Funcionario.fromJson({'nome': 'Ana'}), throwsFormatException);
    expect(
      () => Funcionario.fromJson({...funcionarioJson(), 'ativo': null}),
      throwsFormatException,
    );
    for (final data in ['2026-02-30', '2026-10-01T00:00:00Z', '2026-9-01']) {
      expect(
        () => Alocacao.fromJson({...alocacaoJson(), 'data_inicio': data}),
        throwsFormatException,
      );
    }
    expect(
      () => Alocacao.fromJson({...alocacaoJson(), 'data_fim': '2026-09-30'}),
      throwsFormatException,
    );
  });

  test('GET, POST e PUT usam o Dio com JWT e sem empresa no corpo', () async {
    final rows = await funcionarios.listar();
    final novo = Funcionario(
      id: '',
      nome: 'Beto',
      matricula: '002',
      cargo: 'Motorista',
      empresaId: 'empresa-1',
    );
    final saved = await funcionarios.criar(novo);
    await funcionarios.atualizar(
      Funcionario(
        id: saved.id,
        nome: 'Beto Souza',
        matricula: saved.matricula,
        cargo: null,
        empresaId: saved.empresaId,
      ),
    );
    expect(rows.single.nome, 'Ana Silva');
    expect(adapter.requests.map((r) => r.method), ['GET', 'POST', 'PUT']);
    expect(adapter.requests.first.uri.path, '/api/web/funcionarios');
    for (final request in adapter.requests) {
      expect(
        request.headers['Authorization'],
        'Bearer ${await storage.readAccessToken()}',
      );
      if (request.data is Map) {
        expect((request.data as Map).containsKey('empresa_id'), isFalse);
        expect((request.data as Map).containsKey('id'), isFalse);
      }
    }
    expect(adapter.funcionarios.last['nome'], 'Beto Souza');
  });

  test(
    'desativar usa PUT e só confirma o status devolvido pelo servidor',
    () async {
      final dto = Funcionario.fromJson(funcionarioJson());
      expect((await funcionarios.desativar(dto)).ativo, isFalse);
      expect(adapter.requests.single.method, 'PUT');
      expect(adapter.requests.single.data, {'ativo': false});
      adapter.handler = (_) => jsonResponse({'funcionario': funcionarioJson()});
      await expectLater(
        funcionarios.desativar(dto),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );

  test('nenhum dado de outra empresa é exibido ou enviado', () async {
    final foreign = Funcionario.fromJson(
      funcionarioJson(empresaId: 'empresa-2'),
    );
    await expectLater(
      funcionarios.criar(foreign),
      throwsA(isA<RepositoryFailure>()),
    );
    expect(adapter.requests, isEmpty);
    adapter.handler = (_) => jsonResponse({
      'funcionarios': [foreign.toJson()],
    });
    await expectLater(funcionarios.listar(), throwsA(isA<RepositoryFailure>()));
  });

  for (final status in [400, 409]) {
    test('erro $status de matrícula é limpo e mantém código da API', () async {
      adapter.nextStatus = status;
      adapter.nextBody = {
        'erro': {
          'codigo': 'matricula_duplicada',
          'mensagem': 'Esta matrícula já está cadastrada na empresa.',
        },
      };
      await expectLater(
        funcionarios.criar(Funcionario.fromJson(funcionarioJson())),
        throwsA(
          isA<RepositoryFailure>()
              .having((e) => e.statusCode, 'status', status)
              .having((e) => e.code, 'código', 'matricula_duplicada')
              .having(
                (e) => e.message,
                'mensagem',
                'Esta matrícula já está cadastrada na empresa.',
              ),
        ),
      );
    });
  }

  test('HTML, SQL e erros internos não vazam para a UI', () async {
    for (final failure in [
      (
        400,
        {
          'erro': {'mensagem': 'SQLAlchemy IntegrityError SELECT segredo'},
        },
      ),
      (
        409,
        {
          'erro': {'mensagem': '<html>Senha privada</html>'},
        },
      ),
      (
        500,
        {
          'erro': {'mensagem': 'Traceback: senha privada'},
        },
      ),
    ]) {
      adapter.nextStatus = failure.$1;
      adapter.nextBody = failure.$2;
      await expectLater(
        funcionarios.listar(),
        throwsA(
          isA<RepositoryFailure>()
              .having(
                (e) => e.message,
                'mensagem segura',
                isNot(contains('privada')),
              )
              .having(
                (e) => e.message,
                'SQL oculto',
                isNot(contains('SQLAlchemy')),
              ),
        ),
      );
    }
  });

  test(
    'rede indisponível e resposta malformada viram RepositoryFailure',
    () async {
      adapter.handler = (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
      await expectLater(
        funcionarios.listar(),
        throwsA(
          isA<RepositoryFailure>().having(
            (e) => e.message,
            'rede',
            contains('conectar'),
          ),
        ),
      );
      adapter.handler = (_) => jsonResponse({'funcionarios': null});
      await expectLater(
        funcionarios.listar(),
        throwsA(
          isA<RepositoryFailure>().having(
            (e) => e.message,
            'contrato',
            contains('dados inválidos'),
          ),
        ),
      );
    },
  );

  test(
    'alocação lista e cria com erro de sobreposição entregue à UI',
    () async {
      expect(
        (await alocacoes.listar(funcionarioId: 'funcionario-1')).single.dataFim,
        isNull,
      );
      expect(adapter.requests.last.queryParameters, {
        'funcionario_id': 'funcionario-1',
      });
      await alocacoes.criar(Alocacao.fromJson(alocacaoJson()));
      expect(
        (adapter.requests.last.data as Map).containsKey('empresa_id'),
        isFalse,
      );
      adapter.nextStatus = 409;
      adapter.nextBody = {
        'erro': {
          'codigo': 'alocacao_sobreposta',
          'mensagem':
              'Este funcionário já possui alocação nesse setor no período.',
        },
      };
      await expectLater(
        alocacoes.criar(Alocacao.fromJson(alocacaoJson())),
        throwsA(
          isA<RepositoryFailure>().having(
            (e) => e.message,
            'sobreposição',
            contains('nesse setor'),
          ),
        ),
      );
    },
  );

  test(
    'PUT encerra alocação sem reescrever vínculos ou data inicial',
    () async {
      final dto = Alocacao.fromJson({
        ...alocacaoJson(),
        'data_fim': '2026-10-31',
      });
      final saved = await alocacoes.atualizar(dto);
      expect(saved.dataFim, dto.dataFim);
      expect(adapter.requests.single.method, 'PUT');
      expect(adapter.requests.single.data, {'data_fim': '2026-10-31'});
      adapter.handler = (_) => jsonResponse({
        'alocacao': {...dto.toJson(), 'setor_id': 'outro-setor'},
      });
      await expectLater(
        alocacoes.atualizar(dto),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );
}
