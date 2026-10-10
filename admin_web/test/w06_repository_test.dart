import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/models/escala.dart';
import 'package:ponto_aqui_admin/models/w06.dart';
import 'package:ponto_aqui_admin/repositories/repository_failure.dart';
import 'package:ponto_aqui_admin/repositories/escala_repository.dart';
import 'package:ponto_aqui_admin/repositories/w06_repository.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';

import 'support/auth_fakes.dart';
import 'support/management_api_fake.dart';
import 'support/w06_api_fake.dart';

void main() {
  late W06ApiFake api;
  late Dio dio;
  late W06Repository repo;
  setUp(() {
    api = W06ApiFake();
    final storage = MemoryTokenStorage()
      ..session = sessionFor(UserRole.rh).toJson();
    dio = createDioClient(
      baseUrl: 'https://api.example.com/api/web/',
      tokenStorage: storage,
    )..httpClientAdapter = api;
    repo = W06Repository(dio, empresaId: 'empresa-1');
  });
  tearDown(() => dio.close(force: true));
  test(
    'carga retorna funcionários e histórico do servidor; toda chamada leva JWT',
    () async {
      final data = await repo.carregar();
      expect(data.funcionarios, hasLength(2));
      expect(data.historico, hasLength(3));
      expect(api.requests, hasLength(3));
      expect(
        api.requests.every(
          (r) => r.headers['Authorization'].toString().startsWith('Bearer '),
        ),
        isTrue,
      );
    },
  );
  test('resposta de outra empresa é rejeitada', () async {
    api.feriados.first['empresa_id'] = 'empresa-2';
    await expectLater(repo.carregar(), throwsA(isA<RepositoryFailure>()));
  });
  test(
    'salvar e remover consultam servidor e nova instância vê dados persistidos',
    () async {
      await repo.criarFeriado(data: '2026-10-22', descricao: 'Feriado novo');
      final outra = W06Repository(dio, empresaId: 'empresa-1');
      expect((await outra.carregar()).feriados, hasLength(2));
      await outra.removerFeriado('feriado-3');
      expect((await repo.carregar()).feriados, hasLength(1));
    },
  );
  test('erro HTTP não produz sucesso nem cadastro local', () async {
    api.nextStatus = 400;
    api.nextBody = {
      'erro': {'mensagem': 'Período sobreposto.'},
    };
    await expectLater(
      repo.criarAfastamento(
        funcionarioId: 'funcionario-1',
        tipo: TipoAfastamento.atestado,
        inicio: '2026-10-03',
        fim: '2026-10-05',
      ),
      throwsA(
        isA<RepositoryFailure>()
            .having((e) => e.message, 'mensagem', 'Período sobreposto.')
            .having((e) => e.statusCode, 'status', 400),
      ),
    );
    expect(api.afastamentos, hasLength(1));
  });
  test(
    'exclusão exige confirmação de ID e indicador removido na resposta',
    () async {
      api.handler = (r) => jsonResponse({'id': 'outro', 'removido': true});
      await expectLater(
        repo.removerFeriado('feriado-1'),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );
  test(
    'upload envia o arquivo e edição sem upload não substitui anexo',
    () async {
      await repo.criarAfastamento(
        funcionarioId: 'funcionario-1',
        tipo: TipoAfastamento.atestado,
        inicio: '2026-10-15',
        fim: '2026-10-16',
        anexo: AnexoLocal(
          'arquivo.pdf',
          4,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      );
      expect(api.requests.single.data, isA<FormData>());
      expect(api.afastamentos.last['anexo_url'], isNotNull);
      await repo.salvarAfastamento(
        id: 'afastamento-3',
        funcionarioId: 'funcionario-1',
        tipo: TipoAfastamento.atestado,
        inicio: '2026-10-15',
        fim: '2026-10-17',
      );
      expect((api.requests.last.data as Map).containsKey('anexo_url'), isFalse);
      await repo.salvarAfastamento(
        id: 'afastamento-3',
        funcionarioId: 'funcionario-1',
        tipo: TipoAfastamento.atestado,
        inicio: '2026-10-15',
        fim: '2026-10-17',
        removerAnexo: true,
      );
      expect(api.afastamentos.last['anexo_url'], isNull);
    },
  );
  test('download usa endpoint autenticado e bytes, sem URL pública', () async {
    api.handler = (r) => ResponseBody.fromBytes(
      [37, 80, 68, 70],
      200,
      headers: {
        'content-type': ['application/pdf'],
      },
    );
    final file = await repo.baixarAnexo('afastamento-1');
    expect(file.bytes, [37, 80, 68, 70]);
    expect(file.nome, endsWith('.pdf'));
    expect(
      api.requests.single.uri.path,
      endsWith('/afastamentos/afastamento-1/anexo'),
    );
    expect(api.requests.single.headers['Authorization'], startsWith('Bearer '));
  });
  test(
    'espelho preserva frações, abonos e totais fornecidos pelo backend',
    () async {
      final raw = api.report('funcionario-1', 2026, 10);
      raw['totais'] = <String, dynamic>{
        ...(raw['totais'] as Map).cast<String, dynamic>(),
        'minutos_previstos': 12.5,
      };
      (raw['dias'] as List).first['minutos_abonados'] = 0.5;
      api.reportOverride = raw;
      final report = await repo.espelho('funcionario-1', 2026, 10);
      expect(report.totalApi('previstos'), 12.5);
      expect(report.dias.first.abonados, 0.5);
      expect(report.dias.first.justificado, isTrue);
    },
  );
  test('espelho de outro mês não passa pela validação do contrato', () async {
    api.reportOverride = api.report('funcionario-1', 2026, 9);
    await expectLater(
      repo.espelho('funcionario-1', 2026, 10),
      throwsA(isA<RepositoryFailure>()),
    );
  });
  test(
    'escala POST/PUT/DELETE usa empresa da sessão e rejeita DTO externo',
    () async {
      final scales = EscalaRepository(dio, empresaId: 'empresa-1');
      final dto = Escala(
        id: '',
        empresaId: 'empresa-1',
        nome: 'Diurna',
        modelo: 'Diurno',
        turnos: [TurnoEscala(inicio: 480, fim: 1020, intervalo: 60)],
      );
      final saved = await scales.salvar(dto);
      expect(saved.id, isNotEmpty);
      expect((await scales.listar()), hasLength(2));
      await scales.remover(saved.id);
      expect(await scales.listar(), hasLength(1));
      await expectLater(
        scales.salvar(
          Escala(
            id: '',
            empresaId: 'empresa-2',
            nome: 'Invasão',
            modelo: 'Diurno',
            turnos: [],
          ),
        ),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );
}
