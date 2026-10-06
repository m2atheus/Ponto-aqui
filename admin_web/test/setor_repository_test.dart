import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/models/setor.dart';
import 'package:ponto_aqui_admin/repositories/repository_failure.dart';
import 'package:ponto_aqui_admin/repositories/setor_repository.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';

import 'support/auth_fakes.dart';
import 'support/management_api_fake.dart';

void main() {
  late ManagementApiFake api;
  late Dio dio;
  late SetorRepository repository;
  setUp(() {
    api = ManagementApiFake();
    final storage = MemoryTokenStorage()
      ..session = sessionFor(UserRole.rh).toJson();
    dio = createDioClient(
      baseUrl: 'https://api.example.com/api/web/',
      tokenStorage: storage,
    )..httpClientAdapter = api;
    repository = SetorRepository(dio, empresaId: 'empresa-1');
  });
  tearDown(() => dio.close(force: true));

  test('DTO preserva políticas e lê decimais PostgreSQL e centros legados', () {
    final json = {
      ...setorJson(),
      'latitude': '-8.0476000',
      'longitude': '-34.8770000',
      'raio_metros': '250.50',
      'exige_selfie': true,
      'ignorar_localizacao': true,
      'acao_fora_perimetro': 'PENDENTE',
      'endereco': null,
    };
    final dto = Setor.fromJson(json);
    expect(dto.raioMetros, 250.5);
    expect(dto.endereco, isNull);
    expect(dto.exigeSelfie, isTrue);
    expect(dto.ignorarLocalizacao, isTrue);
    expect(Setor.fromJson(dto.toJson()).toJson(), dto.toJson());
    final legacy = {...json}
      ..remove('latitude')
      ..remove('longitude')
      ..['latitude_centro'] = '-8.0476'
      ..['longitude_centro'] = '-34.877';
    expect(Setor.fromJson(legacy).latitude, dto.latitude);
  });

  test('resumo antigo é legível, mas não pode ser usado para sobrescrever', () {
    final dto = Setor.fromJson({
      'id': 'setor-1',
      'nome': 'Sede',
      'empresa_id': 'empresa-1',
      'ativo': true,
    });
    expect(dto.possuiPerimetro, isFalse);
    expect(dto.latitude, isNull);
    expect(dto.toRequestJson, throwsFormatException);
  });

  test(
    'DTO rejeita geografia inválida, raio não positivo e políticas falsas',
    () {
      for (final override in <Map<String, Object?>>[
        {'latitude': 91},
        {'longitude': -181},
        {'latitude': null},
        {'latitude': 'NaN'},
        {'longitude': true},
        {'raio_metros': 0},
        {'raio_metros': -1},
        {'raio_metros': 'Infinity'},
        {'acao_fora_perimetro': 'ACEITAR'},
        {'exige_selfie': 'true'},
        {'ignorar_localizacao': null},
      ]) {
        expect(
          () => Setor.fromJson({...setorJson(), ...override}),
          throwsFormatException,
          reason: '$override',
        );
      }
    },
  );

  test('GET POST PUT DELETE usam JWT e não enviam empresa ou status', () async {
    expect((await repository.listar()).single.nome, 'Sede');
    final saved = await repository.criar(
      Setor.fromJson({...setorJson(), 'nome': 'Filial'}),
    );
    expect(saved.id, 'setor-2');
    final edited = await repository.atualizar(
      Setor.fromJson({
        ...saved.toJson(),
        'raio_metros': 350,
        'acao_fora_perimetro': 'PENDENTE',
      }),
    );
    expect(edited.raioMetros, 350);
    await repository.remover(edited);
    expect(api.setores, hasLength(1));
    for (final request in api.requests) {
      expect(request.headers['Authorization'], startsWith('Bearer '));
      expect(request.uri.path, startsWith('/api/web/setores'));
      if (request.data is Map) {
        expect((request.data as Map).keys, isNot(contains('empresa_id')));
        expect((request.data as Map).keys, isNot(contains('id')));
        expect((request.data as Map).keys, isNot(contains('ativo')));
      }
    }
  });

  for (final status in [400, 409]) {
    test(
      'exclusão $status propaga motivo claro de alocações sem remover',
      () async {
        api.nextStatus = status;
        api.nextBody = {
          'erro': {
            'codigo': 'SETOR_ALOCADO',
            'mensagem':
                'Não é possível remover um setor com funcionários alocados.',
          },
        };
        await expectLater(
          repository.remover(Setor.fromJson(setorJson())),
          throwsA(
            isA<RepositoryFailure>()
                .having((e) => e.statusCode, 'status', status)
                .having(
                  (e) => e.message,
                  'mensagem',
                  contains('funcionários alocados'),
                ),
          ),
        );
        expect(api.setores, hasLength(1));
      },
    );
  }

  test(
    'exclusão não aceita sucesso aparente com resposta incompatível',
    () async {
      api.nextStatus = 200;
      api.nextBody = {'removido': false, 'id': 'setor-1'};
      await expectLater(
        repository.remover(Setor.fromJson(setorJson())),
        throwsA(isA<RepositoryFailure>()),
      );
      api.nextStatus = 200;
      api.nextBody = {'removido': true, 'id': 'setor-1'};
      await repository.remover(Setor.fromJson(setorJson()));
    },
  );

  test('bloqueia escrita de outra empresa antes de chamar a API', () async {
    final dto = Setor.fromJson({...setorJson(), 'empresa_id': 'empresa-2'});
    await expectLater(repository.criar(dto), throwsA(isA<RepositoryFailure>()));
    await expectLater(
      repository.atualizar(dto),
      throwsA(isA<RepositoryFailure>()),
    );
    await expectLater(
      repository.remover(dto),
      throwsA(isA<RepositoryFailure>()),
    );
    expect(api.requests, isEmpty);
  });

  test(
    'respostas CRUD incompletas ou de outra empresa não confirmam gravação',
    () async {
      api.nextStatus = 201;
      api.nextBody = {
        'setor': {...setorJson(), 'empresa_id': 'empresa-2'},
      };
      await expectLater(
        repository.criar(Setor.fromJson(setorJson())),
        throwsA(isA<RepositoryFailure>()),
      );
      api.nextStatus = 201;
      api.nextBody = {
        'setor': {
          'id': 'setor-1',
          'nome': 'Sede',
          'empresa_id': 'empresa-1',
          'ativo': true,
        },
      };
      await expectLater(
        repository.criar(Setor.fromJson(setorJson())),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );
}
