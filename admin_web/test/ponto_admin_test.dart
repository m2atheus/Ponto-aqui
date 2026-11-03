import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ponto_aqui_admin/repositories/ponto_admin_repository.dart';
import 'package:ponto_aqui_admin/repositories/repository_failure.dart';
import 'package:ponto_aqui_admin/services/api/dio_client.dart';
import 'package:ponto_aqui_admin/models/auth_session.dart';
import 'package:ponto_aqui_admin/views/relatorios/ponto_ajuste_dialog.dart';
import 'package:ponto_aqui_admin/views/relatorios/ponto_invalidacao_dialog.dart';
import 'package:ponto_aqui_admin/views/relatorios/relatorios_screen.dart';

import 'support/auth_fakes.dart';
import 'support/w06_api_fake.dart';
import 'support/management_api_fake.dart' show jsonResponse;
import 'w06_screens_test.dart' as w06;

class PontoApi extends W06ApiFake {
  PontoApi({super.role});
  final ajustes = <Map<String, dynamic>>[];
  Map<String, dynamic>? ajusteOverride;
  bool usuarioVinculado = true;
  String situacaoOriginal = 'Aceita';
  List<Map<String, dynamic>> get decisoes =>
      ajustes.where((a) => a['tipo_ocorrencia'] != 'AJUSTE').toList();
  void invalidarInicialmente() => ajustes.add({
    'id': 'ajuste-1',
    'empresa_id': 'empresa-1',
    'registro_original_id': 'batida-1',
    'tipo_ocorrencia': 'INVALIDACAO_GESTOR',
    'status_analise': 'APROVADO',
    'motivo_texto': 'Foto inicialmente não reconhecida',
    'gestor_aprovador_id': 'usuario-gestor',
    'decidido_em': '2026-10-05T20:00:00Z',
    'sequencia_decisao': 1,
  });
  @override
  Map<String, dynamic> report(String fid, int year, int month) {
    final json = super.report(fid, year, month);
    json['funcionario'] = {
      ...json['funcionario'] as Map,
      'usuario_id': usuarioVinculado ? 'funcionario-usuario-1' : null,
    };
    final atual = decisoes.lastOrNull;
    final invalidado = atual?['tipo_ocorrencia'] == 'INVALIDACAO_GESTOR';
    final aprovado = atual != null && !invalidado;
    for (final dia in json['dias'] as List) {
      dia['marcacoes'] = dia['data'] == '2026-10-05'
          ? [
              {
                'id': 'batida-1',
                'tipo': 'Entrada',
                'situacao': situacaoOriginal,
                'aprovado_gestor': aprovado,
                'aprovacao': aprovado ? atual : null,
                'reaprovado_rh': atual?['tipo_ocorrencia'] == 'REAPROVACAO_RH',
                'historico_decisoes': decisoes,
                'ocorrido_em': '2026-10-05T08:00:00-03:00',
                'invalidado': invalidado,
                'invalidacao': invalidado ? atual : null,
              },
            ]
          : [];
    }
    final extras = aprovado ? 120 : 0;
    (json['totais'] as Map)['minutos_extras'] = extras;
    for (final dia in json['dias'] as List) {
      dia['minutos_extras'] = dia['data'] == '2026-10-05' ? extras : 0;
    }
    return json;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final invalidar = options.uri.path.endsWith('/invalidar');
    final aprovar = options.uri.path.endsWith('/aprovar');
    final reaprovar = options.uri.path.endsWith('/reaprovar');
    if (!options.uri.path.contains('/api/v1/admin/ponto-') &&
        !invalidar &&
        !aprovar &&
        !reaprovar) {
      return super.fetch(options, stream, cancel);
    }
    requests.add(options);
    await writeGate?.future;
    if (nextStatus != null) {
      final status = nextStatus!;
      nextStatus = null;
      return jsonResponse(nextBody, status);
    }
    final body = options.data as Map;
    final dto =
        ajusteOverride ??
        {
          'id': 'ajuste-${ajustes.length + 1}',
          'empresa_id': 'empresa-1',
          'usuario_id': body['usuario_id'] ?? 'funcionario-usuario-1',
          'registro_original_id': invalidar || aprovar || reaprovar
              ? options.uri.pathSegments[options.uri.pathSegments.length - 2]
              : body['registro_original_id'],
          'tipo_ocorrencia': invalidar
              ? 'INVALIDACAO_GESTOR'
              : reaprovar
              ? 'REAPROVACAO_RH'
              : aprovar
              ? 'APROVACAO_GESTOR'
              : 'AJUSTE',
          'nova_data_hora': body['nova_data_hora'],
          'motivo_texto': body['motivo_texto'],
          'tipo': body['tipo'] ?? 'ENTRADA',
          'status_analise': 'APROVADO',
          'gestor_aprovador_id': 'usuario-1',
          'decidido_em': '2026-10-05T20:00:00Z',
          'sequencia_decisao': invalidar || aprovar || reaprovar
              ? decisoes.length + 1
              : null,
        };
    ajustes.add(dto);
    return jsonResponse({'ajuste': dto}, 201);
  }
}

Future<void> modal(
  WidgetTester tester,
  PontoAdminRepository repo, {
  String? original,
  bool Function()? sessaoValida,
  Future<void> Function()? recarregar,
  Size size = const Size(1000, 900),
  String fuso = 'America/Sao_Paulo',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => mostrarAjustePontoDialog(
              context: context,
              repository: repo,
              funcionarioNome: 'Ana Silva',
              fusoHorario: fuso,
              usuarioId: 'funcionario-usuario-1',
              registroOriginalId: original,
              dataHoraInicial: DateTime.utc(2026, 10, 5, 11),
              sessaoValida: sessaoValida ?? () => true,
              recarregar: recarregar ?? () async {},
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

Future<void> salvar(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('ponto-salvar')));
  await tester.tap(find.byKey(const Key('ponto-salvar')));
}

void main() {
  late PontoApi api;
  late Dio dio;
  late PontoAdminRepository repo;
  setUp(() {
    api = PontoApi();
    final storage = MemoryTokenStorage()
      ..session = sessionFor(UserRole.rh).toJson();
    dio = createDioClient(
      baseUrl: 'https://api.example.com/api/web/',
      tokenStorage: storage,
    )..httpClientAdapter = api;
    repo = PontoAdminRepository(dio, empresaId: 'empresa-1');
  });
  tearDown(() => dio.close(force: true));

  test(
    'aprovação usa a rota administrativa, valida tenant e repassa conflito',
    () async {
      dio.options.baseUrl = 'https://api.example.com/painel/api/web/';
      await repo.aprovarMarcacao(
        registroId: 'batida-1',
        motivoTexto: '  Jornada conferida  ',
      );
      expect(
        api.requests.single.uri.path,
        '/painel/api/v1/admin/pontos/batida-1/aprovar',
      );
      expect(api.requests.single.data, {'motivo_texto': 'Jornada conferida'});
      expect(
        api.requests.single.headers['Authorization'],
        startsWith('Bearer '),
      );
      api.nextStatus = 409;
      api.nextBody = {
        'erro': {
          'codigo': 'PONTO_JA_APROVADO',
          'mensagem': 'Esta marcação já possui aprovação.',
        },
      };
      await expectLater(
        repo.aprovarMarcacao(registroId: 'batida-1', motivoTexto: 'Repetição'),
        throwsA(
          isA<RepositoryFailure>().having((e) => e.statusCode, 'status', 409),
        ),
      );
      api.ajusteOverride = {
        ...api.ajustes.first,
        'empresa_id': 'outra-empresa',
      };
      await expectLater(
        repo.aprovarMarcacao(registroId: 'batida-1', motivoTexto: 'Teste'),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );

  for (final role in [UserRole.rh, UserRole.gestor]) {
    testWidgets(
      '$role aprova com motivo e recarrega situação e extras da API',
      (tester) async {
        final fake = PontoApi(role: role)..situacaoOriginal = 'Recusada';
        await w06.mount(tester, '/relatorios', api: fake, role: role);
        await w06.consultar(tester);
        final botao = find.byKey(const ValueKey('aprovar-batida-batida-1'));
        await tester.scrollUntilVisible(
          botao,
          450,
          scrollable: find
              .descendant(
                of: find.byType(RelatoriosScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(botao);
        await tester.pumpAndSettle();
        await tester.tap(botao);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('aprovacao-confirmar')));
        await tester.pumpAndSettle();
        expect(find.text('Informe o motivo da aprovação.'), findsOneWidget);
        expect(fake.ajustes, isEmpty);
        await tester.enterText(
          find.byKey(const Key('aprovacao-motivo')),
          'Jornada conferida com o funcionário',
        );
        fake.writeGate = Completer<void>();
        await tester.tap(find.byKey(const Key('aprovacao-confirmar')));
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('aprovacao-confirmar')),
              )
              .onPressed,
          isNull,
        );
        fake.writeGate!.complete();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Aprovada pelo Gestor/RH'),
          450,
          scrollable: find
              .descendant(
                of: find.byType(RelatoriosScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Aprovada pelo Gestor/RH'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('aprovar-batida-batida-1')),
          findsNothing,
        );
        expect(
          fake.requests.where((r) => r.uri.path.endsWith('/aprovar')),
          hasLength(1),
        );
        expect(
          fake.report('funcionario-1', 2026, 10)['totais']['minutos_extras'],
          120,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'invalidação envia somente motivo, preserva JWT e prefixo do proxy',
    () async {
      dio.options.baseUrl = 'https://api.example.com/painel/api/web/';
      await repo.invalidarMarcacao(
        registroId: 'batida-1',
        motivoTexto: '  Foto incorreta  ',
      );
      expect(
        api.requests.single.uri.path,
        '/painel/api/v1/admin/pontos/batida-1/invalidar',
      );
      expect(api.requests.single.data, {'motivo_texto': 'Foto incorreta'});
      expect(
        api.requests.single.headers['Authorization'],
        startsWith('Bearer '),
      );
      expect(api.ajustes.single['tipo_ocorrencia'], 'INVALIDACAO_GESTOR');
    },
  );

  test('invalidação trata conflito retornado pela API', () async {
    api.nextStatus = 409;
    api.nextBody = {
      'erro': {
        'codigo': 'PONTO_JA_INVALIDADO',
        'mensagem': 'Esta marcação já foi invalidada.',
      },
    };
    await expectLater(
      repo.invalidarMarcacao(
        registroId: 'batida-1',
        motivoTexto: 'Foto incorreta',
      ),
      throwsA(
        isA<RepositoryFailure>().having(
          (e) => e.message,
          'mensagem',
          'Esta marcação já foi invalidada.',
        ),
      ),
    );
  });

  testWidgets(
    'invalidação exige motivo, impede envio duplo e recarrega após sucesso',
    (tester) async {
      var consultas = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => InvalidarPontoButton(
                onPressed: () => mostrarInvalidacaoPontoDialog(
                  context: context,
                  repository: repo,
                  registroId: 'batida-1',
                  funcionarioNome: 'Ana Silva',
                  sessaoValida: () => true,
                  recarregar: () async {
                    consultas++;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(InvalidarPontoButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('invalidacao-confirmar')));
      await tester.pumpAndSettle();
      expect(find.text('Informe o motivo da invalidação.'), findsOneWidget);
      expect(api.requests, isEmpty);
      await tester.enterText(
        find.byKey(const Key('invalidacao-motivo')),
        'Foto incorreta',
      );
      api.writeGate = Completer<void>();
      await tester.tap(find.byKey(const Key('invalidacao-confirmar')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('invalidacao-confirmar')),
            )
            .onPressed,
        isNull,
      );
      api.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(api.ajustes, hasLength(1));
      expect(consultas, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in [UserRole.rh, UserRole.gestor]) {
    testWidgets('$role invalida no espelho e visualiza sobreposição auditada', (
      tester,
    ) async {
      final fake = PontoApi(role: role);
      await w06.mount(tester, '/relatorios', api: fake, role: role);
      await w06.consultar(tester);
      final botao = find.byKey(const ValueKey('invalidar-batida-batida-1'));
      await tester.scrollUntilVisible(
        botao,
        500,
        scrollable: find
            .descendant(
              of: find.byType(RelatoriosScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(botao);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invalidacao-motivo')),
        'Foto incorreta',
      );
      await tester.tap(find.byKey(const Key('invalidacao-confirmar')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Invalidado pelo Gestor/RH'),
        500,
        scrollable: find
            .descendant(
              of: find.byType(RelatoriosScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Invalidado pelo Gestor/RH'), findsOneWidget);
      expect(tester.widget<InvalidarPontoButton>(botao).onPressed, isNull);
      if (role == UserRole.gestor) {
        expect(
          find.byKey(const ValueKey('editar-batida-batida-1')),
          findsNothing,
        );
        expect(find.byKey(const Key('inserir-ponto-manual')), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final prefix in ['', '/painel']) {
    test(
      'rotas administrativas recebem JWT e preservam prefixo $prefix',
      () async {
        dio.options.baseUrl = 'https://api.example.com$prefix/api/web/';
        await repo.inserirPontoManual(
          usuarioId: 'funcionario-usuario-1',
          novaDataHora: DateTime.utc(2026, 10, 5, 11),
          motivoTexto: '  Sem celular  ',
          tipo: TipoBatida.saida,
        );
        await repo.corrigirPontoExistente(
          registroOriginalId: 'batida-1',
          novaDataHora: DateTime.utc(2026, 10, 5, 12),
          motivoTexto: 'Horário incorreto',
        );
        expect(api.requests[0].uri.path, '$prefix/api/v1/admin/ponto-manual');
        expect(api.requests[1].uri.path, '$prefix/api/v1/admin/ponto-correcao');
        expect(
          api.requests.every(
            (r) => r.headers['Authorization'].toString().startsWith('Bearer '),
          ),
          isTrue,
        );
        expect(api.requests[0].data, {
          'usuario_id': 'funcionario-usuario-1',
          'nova_data_hora': '2026-10-05T11:00:00.000Z',
          'motivo_texto': 'Sem celular',
          'tipo': 'SAIDA',
        });
        expect(
          (api.requests[1].data as Map).keys,
          unorderedEquals([
            'registro_original_id',
            'nova_data_hora',
            'motivo_texto',
          ]),
        );
      },
    );
  }

  for (final status in [400, 409, 401, 403, 503]) {
    test('erros HTTP $status são tratados sem detalhes internos', () async {
      api.nextStatus = status;
      api.nextBody = {
        'erro': {
          'codigo': 'AJUSTE_INVALIDO',
          'mensagem': 'Informe o motivo correto.',
        },
      };
      await expectLater(
        repo.corrigirPontoExistente(
          registroOriginalId: 'batida-1',
          novaDataHora: DateTime.utc(2026),
          motivoTexto: 'Justificativa',
        ),
        throwsA(
          isA<RepositoryFailure>()
              .having((e) => e.statusCode, 'status', status)
              .having(
                (e) => e.message,
                'mensagem',
                status == 400 || status == 409
                    ? 'Informe o motivo correto.'
                    : isNot(contains('Informe o motivo correto.')),
              ),
        ),
      );
    });
  }

  test('resposta de outra empresa não é confirmada', () async {
    api.ajusteOverride = {
      'id': 'ajuste-1',
      'gestor_aprovador_id': 'usuario-1',
      'empresa_id': 'empresa-2',
      'status_analise': 'APROVADO',
    };
    await expectLater(
      repo.corrigirPontoExistente(
        registroOriginalId: 'batida-1',
        novaDataHora: DateTime.utc(2026),
        motivoTexto: 'Motivo',
      ),
      throwsA(isA<RepositoryFailure>()),
    );
  });

  test(
    'conversão usa o fuso da empresa e detecta hora inexistente/repetida',
    () {
      expect(
        instantesDaBatida(
          'America/Sao_Paulo',
          DateTime(2026, 10, 5),
          const TimeOfDay(hour: 8, minute: 0),
        ),
        [DateTime.utc(2026, 10, 5, 11)],
      );
      expect(
        instantesDaBatida(
          'America/Manaus',
          DateTime(2026, 10, 5),
          const TimeOfDay(hour: 8, minute: 0),
        ),
        [DateTime.utc(2026, 10, 5, 12)],
      );
      expect(
        instantesDaBatida(
          'America/New_York',
          DateTime(2026, 3, 8),
          const TimeOfDay(hour: 2, minute: 30),
        ),
        isEmpty,
      );
      expect(
        instantesDaBatida(
          'America/New_York',
          DateTime(2026, 11, 1),
          const TimeOfDay(hour: 1, minute: 30),
        ),
        [DateTime.utc(2026, 11, 1, 5, 30), DateTime.utc(2026, 11, 1, 6, 30)],
      );
    },
  );

  testWidgets('motivo obrigatório, loading e envio único antes da recarga', (
    tester,
  ) async {
    var consultas = 0;
    await modal(
      tester,
      repo,
      recarregar: () async {
        consultas++;
      },
    );
    await salvar(tester);
    await tester.pumpAndSettle();
    expect(find.text('Informe a justificativa do ajuste.'), findsOneWidget);
    expect(api.requests, isEmpty);
    await tester.enterText(
      find.byKey(const Key('ponto-motivo')),
      'Sem celular',
    );
    api.writeGate = Completer<void>();
    await salvar(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ponto-salvar')))
          .onPressed,
      isNull,
    );
    await salvar(tester);
    expect(api.requests, hasLength(1));
    api.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Ajuste aprovado e salvo com sucesso.'), findsOneWidget);
    expect(consultas, 1);
    expect(
      (api.requests.single.data as Map)['nova_data_hora'],
      '2026-10-05T11:00:00.000Z',
    );
  });

  testWidgets('correção mantém tipo original e data/hora no fuso da empresa', (
    tester,
  ) async {
    await modal(tester, repo, original: 'batida-1');
    expect(find.byKey(const Key('ponto-tipo')), findsNothing);
    expect(find.byKey(const ValueKey('ponto-data-2026-10-05')), findsOneWidget);
    expect(find.byKey(const ValueKey('ponto-hora-8-0')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('ponto-motivo')),
      'Ajustar horário',
    );
    await salvar(tester);
    await tester.pumpAndSettle();
    expect(
      (api.requests.single.data as Map)['registro_original_id'],
      'batida-1',
    );
    expect((api.requests.single.data as Map).containsKey('tipo'), isFalse);
  });

  testWidgets('erro da API mantém o formulário e permite corrigir os dados', (
    tester,
  ) async {
    await modal(tester, repo);
    await tester.enterText(
      find.byKey(const Key('ponto-motivo')),
      'Motivo informado',
    );
    api.nextStatus = 400;
    api.nextBody = {
      'erro': {'mensagem': 'Funcionário sem usuário vinculado.'},
    };
    await salvar(tester);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Funcionário sem usuário vinculado.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('ponto-motivo')))
          .controller!
          .text,
      'Motivo informado',
    );
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
      Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.error,
    );
  });

  testWidgets('pickers de data e hora abrem e cancelam sem modificar valores', (
    tester,
  ) async {
    await modal(tester, repo);
    await tester.tap(find.byKey(const ValueKey('ponto-data-2026-10-05')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancelar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ponto-hora-8-0')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancelar').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ponto-hora-8-0')), findsOneWidget);
    expect(api.requests, isEmpty);
  });

  testWidgets('falha da recarga após salvar não repete o POST confirmado', (
    tester,
  ) async {
    await modal(
      tester,
      repo,
      recarregar: () async => throw StateError('consulta falhou'),
    );
    await tester.enterText(find.byKey(const Key('ponto-motivo')), 'Sem sinal');
    await salvar(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(1));
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.textContaining('O ajuste foi salvo, mas a lista'),
      findsOneWidget,
    );
  });

  testWidgets('sessão alterada durante envio não atualiza a próxima sessão', (
    tester,
  ) async {
    var valida = true;
    var consultas = 0;
    await modal(
      tester,
      repo,
      sessaoValida: () => valida,
      recarregar: () async {
        consultas++;
      },
    );
    await tester.enterText(
      find.byKey(const Key('ponto-motivo')),
      'Sem celular',
    );
    api.writeGate = Completer<void>();
    await salvar(tester);
    await tester.pump();
    valida = false;
    api.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(consultas, 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('modal funciona em 320 pixels e pode ser fechado sem enviar', (
    tester,
  ) async {
    await modal(tester, repo, size: const Size(320, 760));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.requests, isEmpty);
  });

  testWidgets('relatórios acopla inclusão, lápis e GET após salvar', (
    tester,
  ) async {
    await w06.mount(tester, '/relatorios', api: api);
    await w06.consultar(tester);
    final consultas = api.requests
        .where((r) => r.uri.path.endsWith('/relatorios/espelho'))
        .length;
    await tester.ensureVisible(find.byKey(const Key('inserir-ponto-manual')));
    await tester.tap(find.byKey(const Key('inserir-ponto-manual')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ponto-motivo')),
      'Sistema fora do ar',
    );
    await salvar(tester);
    await tester.pumpAndSettle();
    expect(
      api.requests
          .where((r) => r.uri.path.endsWith('/relatorios/espelho'))
          .length,
      consultas + 1,
    );
    final edit = find.byKey(const ValueKey('editar-batida-batida-1'));
    await tester.scrollUntilVisible(
      edit,
      500,
      scrollable: find
          .descendant(
            of: find.byType(RelatoriosScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ponto-motivo')),
      'Horário errado',
    );
    await salvar(tester);
    await tester.pumpAndSettle();
    expect(api.ajustes, hasLength(2));
    expect(api.ajustes.last['registro_original_id'], 'batida-1');
    expect(
      api.requests.any((r) => {'PUT', 'DELETE', 'PATCH'}.contains(r.method)),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('funcionário sem conta não habilita inclusão manual', (
    tester,
  ) async {
    api.usuarioVinculado = false;
    await w06.mount(tester, '/relatorios', api: api);
    await w06.consultar(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('inserir-ponto-manual')))
          .onPressed,
      isNull,
    );
  });
}
