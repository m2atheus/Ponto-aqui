/// DTOs portáveis para o contrato W08. Datas civis permanecem strings ISO.
enum ModoOperacao { pessoal, relogio }

Map<String, dynamic> _objeto(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$field deve ser um objeto JSON.');
  }
  return Map<String, dynamic>.from(value);
}

String _texto(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field deve ser texto não vazio.');
  }
  return value;
}

String? _textoOpcional(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$field deve ser texto ou null.');
  return value;
}

String _uuid(Object? value, String field) {
  final text = _texto(value, field);
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(text)) {
    throw FormatException('$field deve ser um UUID.');
  }
  return text.toLowerCase();
}

int _inteiro(Object? value, String field) {
  if (value is! int || value < 0) {
    throw FormatException('$field deve ser inteiro não negativo.');
  }
  return value;
}

bool _booleano(Object? value, String field) {
  if (value is! bool) throw FormatException('$field deve ser booleano.');
  return value;
}

double _numero(Object? value, String field) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$field deve ser número finito.');
  }
  return value.toDouble();
}

String _data(Object? value, String field) {
  final text = _texto(value, field);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    throw FormatException('$field deve usar AAAA-MM-DD.');
  }
  final parsed = DateTime.tryParse('${text}T00:00:00Z');
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != text) {
    throw FormatException('$field contém uma data inválida.');
  }
  return text;
}

String _hora(Object? value, String field) {
  final text = _texto(value, field);
  if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(text)) {
    throw FormatException('$field deve usar HH:MM.');
  }
  return text;
}

DateTime parseTimestampUtc(Object? value) {
  final text = _texto(value, 'timestamp UTC');
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?(?:Z|\+00:00)$',
  ).hasMatch(text)) {
    throw const FormatException('Timestamp deve ser ISO 8601 em UTC.');
  }
  _data(text.substring(0, 10), 'data do timestamp');
  final result = DateTime.tryParse(text);
  if (result == null) throw const FormatException('Timestamp UTC inválido.');
  return result.toUtc();
}

List<T> _lista<T>(Object? value, String field, T Function(Object?) parse) {
  if (value == null) return List<T>.unmodifiable([]);
  if (value is! List) throw FormatException('$field deve ser uma lista.');
  return List<T>.unmodifiable(value.map(parse));
}

T? _opcional<T>(Object? value, T Function(Object?) parse) =>
    value == null ? null : parse(value);

String _opcao(Object? value, String field, Set<String> options) {
  final text = _texto(value, field);
  if (!options.contains(text)) {
    throw FormatException('$field contém valor desconhecido.');
  }
  return text;
}

class PoliticasSetorDto {
  const PoliticasSetorDto({
    required this.exigeSelfie,
    required this.acaoForaPerimetro,
    required this.ignorarLocalizacao,
    required this.limiteDesvioRelogioSegundos,
  });
  final bool exigeSelfie;
  final String acaoForaPerimetro;
  final bool ignorarLocalizacao;
  final int limiteDesvioRelogioSegundos;

  factory PoliticasSetorDto.fromJson(Object? value) {
    final json = _objeto(value, 'PoliticasSetorDto');
    final dto = PoliticasSetorDto(
      exigeSelfie: _booleano(json['exige_selfie'], 'exige_selfie'),
      acaoForaPerimetro: _opcao(
        json['acao_fora_perimetro'],
        'acao_fora_perimetro',
        {'BLOQUEAR', 'PENDENTE'},
      ),
      ignorarLocalizacao: _booleano(
        json['ignorar_localizacao'],
        'ignorar_localizacao',
      ),
      limiteDesvioRelogioSegundos: _inteiro(
        json['limite_desvio_relogio_segundos'],
        'limite_desvio_relogio_segundos',
      ),
    );

    return dto;
  }

  Map<String, dynamic> toJson() => {
    'exige_selfie': exigeSelfie,
    'acao_fora_perimetro': acaoForaPerimetro,
    'ignorar_localizacao': ignorarLocalizacao,
    'limite_desvio_relogio_segundos': limiteDesvioRelogioSegundos,
  };
}

class SetorSyncDto {
  const SetorSyncDto({
    required this.id,
    required this.nome,
    required this.latitude,
    required this.longitude,
    required this.raioMetros,
    required this.politicas,
  });
  final String id;
  final String nome;
  final double latitude;
  final double longitude;
  final double raioMetros;
  final PoliticasSetorDto politicas;

  factory SetorSyncDto.fromJson(Object? value) {
    final json = _objeto(value, 'SetorSyncDto');
    final dto = SetorSyncDto(
      id: _uuid(json['id'], 'setor.id'),
      nome: _texto(json['nome'], 'setor.nome'),
      latitude: _numero(json['latitude'], 'latitude'),
      longitude: _numero(json['longitude'], 'longitude'),
      raioMetros: _numero(json['raio_metros'], 'raio_metros'),
      politicas: PoliticasSetorDto.fromJson(json['politicas']),
    );
    if (dto.latitude.abs() > 90 ||
        dto.longitude.abs() > 180 ||
        dto.raioMetros <= 0) {
      throw const FormatException('Perímetro inválido.');
    }
    return dto;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': nome,
    'latitude': latitude,
    'longitude': longitude,
    'raio_metros': raioMetros,
    'politicas': politicas.toJson(),
  };
}

class TurnoSyncDto {
  const TurnoSyncDto({
    required this.horaInicio,
    required this.horaFim,
    required this.tempoIntervalo,
    required this.fimDiaSeguinte,
    required this.diasSemana,
  });
  final String horaInicio;
  final String horaFim;
  final int tempoIntervalo;
  final bool fimDiaSeguinte;
  final List<int> diasSemana;

  factory TurnoSyncDto.fromJson(Object? value) {
    final json = _objeto(value, 'TurnoSyncDto');
    final dto = TurnoSyncDto(
      horaInicio: _hora(json['hora_inicio'], 'hora_inicio'),
      horaFim: _hora(json['hora_fim'], 'hora_fim'),
      tempoIntervalo: _inteiro(json['tempo_intervalo'], 'tempo_intervalo'),
      fimDiaSeguinte: _booleano(json['fim_dia_seguinte'], 'fim_dia_seguinte'),
      diasSemana: _lista(
        json['dias_semana'],
        'dias_semana',
        (v) => _inteiro(v, 'dia ISO'),
      ),
    );
    if (dto.diasSemana.any((v) => v < 1 || v > 7)) {
      throw const FormatException('Dia ISO inválido.');
    }
    return dto;
  }

  Map<String, dynamic> toJson() => {
    'hora_inicio': horaInicio,
    'hora_fim': horaFim,
    'tempo_intervalo': tempoIntervalo,
    'fim_dia_seguinte': fimDiaSeguinte,
    'dias_semana': diasSemana,
  };
}

class EscalaSyncDto {
  const EscalaSyncDto({
    required this.id,
    required this.nome,
    required this.modelo,
    required this.dataReferencia,
    required this.toleranciaMinutos,
    required this.turnos,
  });
  final String id;
  final String nome;
  final String modelo;
  final String? dataReferencia;
  final int toleranciaMinutos;
  final List<TurnoSyncDto> turnos;

  factory EscalaSyncDto.fromJson(Object? value) {
    final json = _objeto(value, 'EscalaSyncDto');
    final dto = EscalaSyncDto(
      id: _uuid(json['id'], 'escala.id'),
      nome: _texto(json['nome'], 'escala.nome'),
      modelo: _opcao(json['modelo'], 'modelo', {
        '24x72',
        '12x36',
        'Diurno',
        '5x2',
        'Legado',
      }),
      dataReferencia: _opcional(
        json['data_referencia'],
        (v) => _data(v, 'data_referencia'),
      ),
      toleranciaMinutos: _inteiro(
        json['tolerancia_minutos'],
        'tolerancia_minutos',
      ),
      turnos: _lista(json['turnos'], 'turnos', TurnoSyncDto.fromJson),
    );

    return dto;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': nome,
    'modelo': modelo,
    'data_referencia': dataReferencia,
    'tolerancia_minutos': toleranciaMinutos,
    'turnos': turnos.map((v) => v.toJson()).toList(),
  };
}

class FuncionarioSyncDto {
  const FuncionarioSyncDto({
    required this.id,
    required this.usuarioId,
    required this.nome,
    required this.matricula,
    required this.cargo,
  });
  final String id;
  final String? usuarioId;
  final String nome;
  final String matricula;
  final String? cargo;

  factory FuncionarioSyncDto.fromJson(Object? value) {
    final json = _objeto(value, 'FuncionarioSyncDto');
    final dto = FuncionarioSyncDto(
      id: _uuid(json['id'], 'funcionario.id'),
      usuarioId: _opcional(json['usuario_id'], (v) => _uuid(v, 'usuario_id')),
      nome: _texto(json['nome'], 'funcionario.nome'),
      matricula: _texto(json['matricula'], 'matricula'),
      cargo: _textoOpcional(json['cargo'], 'cargo'),
    );

    return dto;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'usuario_id': usuarioId,
    'nome': nome,
    'matricula': matricula,
    'cargo': cargo,
  };
}

class AlocacaoPessoalSyncDto {
  const AlocacaoPessoalSyncDto({
    required this.id,
    required this.dataInicio,
    required this.dataFim,
    required this.setor,
    required this.escala,
  });
  final String id;
  final String dataInicio;
  final String? dataFim;
  final SetorSyncDto setor;
  final EscalaSyncDto? escala;

  factory AlocacaoPessoalSyncDto.fromJson(Object? value) {
    final json = _objeto(value, 'AlocacaoPessoalSyncDto');
    final dto = AlocacaoPessoalSyncDto(
      id: _uuid(json['id'], 'alocacao.id'),
      dataInicio: _data(json['data_inicio'], 'data_inicio'),
      dataFim: _opcional(json['data_fim'], (v) => _data(v, 'data_fim')),
      setor: SetorSyncDto.fromJson(json['setor']),
      escala: _opcional(json['escala'], EscalaSyncDto.fromJson),
    );
    if (dto.dataFim != null && dto.dataFim!.compareTo(dto.dataInicio) < 0) {
      throw const FormatException('Vigência inválida.');
    }
    return dto;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'data_inicio': dataInicio,
    'data_fim': dataFim,
    'setor': setor.toJson(),
    'escala': escala?.toJson(),
  };
}

class AlocacaoRelogioSyncDto {
  const AlocacaoRelogioSyncDto({
    required this.id,
    required this.dataInicio,
    required this.dataFim,
    required this.escalaId,
  });
  final String id;
  final String dataInicio;
  final String? dataFim;
  final String? escalaId;

  factory AlocacaoRelogioSyncDto.fromJson(Object? value) {
    final json = _objeto(value, 'AlocacaoRelogioSyncDto');
    final dto = AlocacaoRelogioSyncDto(
      id: _uuid(json['id'], 'alocacao.id'),
      dataInicio: _data(json['data_inicio'], 'data_inicio'),
      dataFim: _opcional(json['data_fim'], (v) => _data(v, 'data_fim')),
      escalaId: _opcional(json['escala_id'], (v) => _uuid(v, 'escala_id')),
    );
    if (dto.dataFim != null && dto.dataFim!.compareTo(dto.dataInicio) < 0) {
      throw const FormatException('Vigência inválida.');
    }
    return dto;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'data_inicio': dataInicio,
    'data_fim': dataFim,
    'escala_id': escalaId,
  };
}

class MarcacaoRecenteDto {
  const MarcacaoRecenteDto({
    required this.id,
    required this.eventoClienteId,
    required this.tipo,
    required this.situacao,
    required this.ocorridoEm,
    required this.recebidoEm,
    required this.motivos,
  });
  final String id;
  final String eventoClienteId;
  final String tipo;
  final String situacao;
  final DateTime ocorridoEm;
  final DateTime recebidoEm;
  final List<String> motivos;

  factory MarcacaoRecenteDto.fromJson(Object? value) {
    final json = _objeto(value, 'MarcacaoRecenteDto');
    final dto = MarcacaoRecenteDto(
      id: _uuid(json['id'], 'marcacao.id'),
      eventoClienteId: _uuid(json['evento_cliente_id'], 'evento_cliente_id'),
      tipo: _opcao(json['tipo'], 'tipo', {
        'Entrada',
        'InicioIntervalo',
        'FimIntervalo',
        'Saida',
      }),
      situacao: _opcao(json['situacao'], 'situacao', {
        'Aceita',
        'PendenteAnalise',
        'Recusada',
      }),
      ocorridoEm: parseTimestampUtc(json['ocorrido_em']),
      recebidoEm: parseTimestampUtc(json['recebido_em']),
      motivos: _lista(json['motivos'], 'motivos', (v) => _texto(v, 'motivo')),
    );

    return dto;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'evento_cliente_id': eventoClienteId,
    'tipo': tipo,
    'situacao': situacao,
    'ocorrido_em': ocorridoEm.toUtc().toIso8601String(),
    'recebido_em': recebidoEm.toUtc().toIso8601String(),
    'motivos': motivos,
  };
}

class FuncionarioRelogioSyncDto {
  const FuncionarioRelogioSyncDto({
    required this.funcionario,
    required this.alocacoes,
  });
  final FuncionarioSyncDto funcionario;
  final List<AlocacaoRelogioSyncDto> alocacoes;
  factory FuncionarioRelogioSyncDto.fromJson(Object? value) {
    final json = _objeto(value, 'funcionario do relógio');
    return FuncionarioRelogioSyncDto(
      funcionario: FuncionarioSyncDto.fromJson(json),
      alocacoes: _lista(
        json['alocacoes'],
        'alocacoes',
        AlocacaoRelogioSyncDto.fromJson,
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    ...funcionario.toJson(),
    'alocacoes': alocacoes.map((v) => v.toJson()).toList(),
  };
}

class MobileSyncDto {
  const MobileSyncDto({
    required this.serverTimestamp,
    required this.dataReferencia,
    required this.fusoHorario,
    required this.modoOperacao,
    required this.status,
    required this.mensagemStatus,
    required this.funcionario,
    required this.setor,
    required this.escala,
    required this.alocacoes,
    required this.marcacoesRecentes,
    required this.escalas,
    required this.funcionarios,
  });

  final DateTime serverTimestamp;
  final String dataReferencia;
  final String fusoHorario;
  final ModoOperacao modoOperacao;
  final String status;
  final String mensagemStatus;
  final FuncionarioSyncDto? funcionario;
  final SetorSyncDto? setor;
  final EscalaSyncDto? escala;
  final List<AlocacaoPessoalSyncDto> alocacoes;
  final List<MarcacaoRecenteDto> marcacoesRecentes;
  final List<EscalaSyncDto> escalas;
  final List<FuncionarioRelogioSyncDto> funcionarios;

  factory MobileSyncDto.fromJson(Object? value) {
    final json = _objeto(value, 'sync');
    final modo = switch (json['modo_operacao']) {
      'PESSOAL' => ModoOperacao.pessoal,
      'RELOGIO' => ModoOperacao.relogio,
      _ => throw const FormatException('Modo de operação desconhecido.'),
    };
    final dto = MobileSyncDto(
      serverTimestamp: parseTimestampUtc(json['server_timestamp']),
      dataReferencia: _data(json['data_referencia'], 'data_referencia'),
      fusoHorario: _texto(json['fuso_horario'], 'fuso_horario'),
      modoOperacao: modo,
      status: _texto(json['status'], 'status'),
      mensagemStatus: _texto(json['mensagem_status'], 'mensagem_status'),
      funcionario: _opcional(json['funcionario'], FuncionarioSyncDto.fromJson),
      setor: _opcional(json['setor'], SetorSyncDto.fromJson),
      escala: _opcional(json['escala'], EscalaSyncDto.fromJson),
      alocacoes: _lista(
        json['alocacoes'],
        'alocacoes',
        AlocacaoPessoalSyncDto.fromJson,
      ),
      marcacoesRecentes: _lista(
        json['marcacoes_recentes'],
        'marcacoes_recentes',
        MarcacaoRecenteDto.fromJson,
      ),
      escalas: _lista(json['escalas'], 'escalas', EscalaSyncDto.fromJson),
      funcionarios: _lista(
        json['funcionarios'],
        'funcionarios',
        FuncionarioRelogioSyncDto.fromJson,
      ),
    );
    if (modo == ModoOperacao.relogio) {
      if (dto.setor == null) throw const FormatException('Relógio sem setor.');
      final ids = dto.escalas.map((v) => v.id).toSet();
      if (dto.funcionarios
          .expand((v) => v.alocacoes)
          .any((a) => a.escalaId != null && !ids.contains(a.escalaId))) {
        throw const FormatException('Escala referenciada ausente no catálogo.');
      }
    }
    return dto;
  }

  Map<String, dynamic> toJson() => {
    'server_timestamp': serverTimestamp.toUtc().toIso8601String(),
    'data_referencia': dataReferencia,
    'fuso_horario': fusoHorario,
    'modo_operacao': modoOperacao == ModoOperacao.pessoal
        ? 'PESSOAL'
        : 'RELOGIO',
    'status': status,
    'mensagem_status': mensagemStatus,
    'setor': setor?.toJson(),
    if (modoOperacao == ModoOperacao.pessoal) ...{
      'funcionario': funcionario?.toJson(),
      'escala': escala?.toJson(),
      'alocacoes': alocacoes.map((v) => v.toJson()).toList(),
      'marcacoes_recentes': marcacoesRecentes.map((v) => v.toJson()).toList(),
    } else ...{
      'escalas': escalas.map((v) => v.toJson()).toList(),
      'funcionarios': funcionarios.map((v) => v.toJson()).toList(),
    },
  };
}
