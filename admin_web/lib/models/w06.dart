import 'dart:typed_data';

import 'funcionario.dart';
import 'management_json.dart';

// DTOs dos endpoints W06. Anexos locais ficam separados de URLs persistidas.
class SetorResumo {
  const SetorResumo(this.id, this.nome, {this.ativo = true});
  final String id;
  final String nome;
  final bool ativo;
  factory SetorResumo.fromJson(Object? value) {
    final j = managementObject(value);
    return SetorResumo(
      managementString(j['id'], 'id'),
      managementString(j['nome'], 'nome'),
      ativo: j['ativo'] != false,
    );
  }
}

class FeriadoResumo {
  const FeriadoResumo({
    required this.id,
    required this.data,
    required this.descricao,
    this.setorId,
  });
  final String id;
  final String data;
  final String descricao;
  final String? setorId;
  factory FeriadoResumo.fromJson(Object? value) {
    final j = managementObject(value);
    return FeriadoResumo(
      id: managementString(j['id'], 'id'),
      data: managementDate(j['data'], 'data'),
      descricao: managementString(j['descricao'], 'descricao'),
      setorId: managementOptionalString(j['setor_id'], 'setor_id'),
    );
  }
}

class AnexoLocal {
  const AnexoLocal(this.nome, this.tamanho, {this.bytes});
  final String nome;
  final int tamanho;
  final Uint8List? bytes;
}

enum TipoAfastamento {
  ferias('FERIAS', 'Férias'),
  atestado('ATESTADO', 'Atestado'),
  licenca('LICENCA', 'Licença'),
  outros('OUTROS', 'Outros');

  const TipoAfastamento(this.apiValue, this.label);
  final String apiValue;
  final String label;
  static TipoAfastamento fromApi(Object? value) =>
      TipoAfastamento.values.firstWhere(
        (t) => t.apiValue == value,
        orElse: () =>
            throw const FormatException('Tipo de afastamento inválido.'),
      );
}

class AfastamentoResumo {
  const AfastamentoResumo({
    required this.id,
    required this.funcionarioId,
    required this.tipo,
    required this.inicio,
    required this.fim,
    this.anexoLocal,
    this.anexoUrl,
  });
  final String id;
  final String funcionarioId;
  final TipoAfastamento tipo;
  final String inicio;
  final String fim;
  final AnexoLocal? anexoLocal;
  final String? anexoUrl;
  factory AfastamentoResumo.fromJson(Object? value) {
    final j = managementObject(value);
    return AfastamentoResumo(
      id: managementString(j['id'], 'id'),
      funcionarioId: managementString(j['funcionario_id'], 'funcionario_id'),
      tipo: TipoAfastamento.fromApi(j['tipo']),
      inicio: managementDate(j['data_inicio'], 'data_inicio'),
      fim: managementDate(j['data_fim'], 'data_fim'),
      anexoUrl: managementOptionalString(j['anexo_url'], 'anexo_url'),
    );
  }
}

class HistoricoAlocacao {
  const HistoricoAlocacao({
    required this.id,
    required this.funcionarioId,
    required this.setorId,
    required this.escalaNome,
    required this.inicio,
    this.fim,
    this.escalaId,
  });
  final String id;
  final String funcionarioId;
  final String setorId;
  final String escalaNome;
  final String inicio;
  final String? fim;
  final String? escalaId;
  factory HistoricoAlocacao.fromJson(Object? value) {
    final j = managementObject(value);
    return HistoricoAlocacao(
      id: managementString(j['id'], 'id'),
      funcionarioId: managementString(j['funcionario_id'], 'funcionario_id'),
      setorId: managementString(j['setor_id'], 'setor_id'),
      escalaId: managementOptionalString(j['escala_id'], 'escala_id'),
      escalaNome:
          managementOptionalString(j['escala_nome'], 'escala_nome') ??
          'Sem escala',
      inicio: managementDate(j['data_inicio'], 'data_inicio'),
      fim: j['data_fim'] == null
          ? null
          : managementDate(j['data_fim'], 'data_fim'),
    );
  }
}

class W06Data {
  W06Data({
    required Iterable<Funcionario> funcionarios,
    required Iterable<SetorResumo> setores,
    required Iterable<HistoricoAlocacao> historico,
    required Iterable<FeriadoResumo> feriados,
    required Iterable<AfastamentoResumo> afastamentos,
  }) : funcionarios = List.unmodifiable(funcionarios),
       setores = List.unmodifiable(setores),
       historico = List.unmodifiable(historico),
       feriados = List.unmodifiable(feriados),
       afastamentos = List.unmodifiable(afastamentos);
  final List<Funcionario> funcionarios;
  final List<SetorResumo> setores;
  final List<HistoricoAlocacao> historico;
  final List<FeriadoResumo> feriados;
  final List<AfastamentoResumo> afastamentos;

  String setorNome(String? id) => id == null
      ? 'Empresa inteira'
      : setores.where((s) => s.id == id).firstOrNull?.nome ??
            'Setor indisponível';
  String funcionarioNome(String id) =>
      funcionarios.where((f) => f.id == id).firstOrNull?.nome ??
      'Funcionário indisponível';
}

class GeofencePonto {
  const GeofencePonto({
    required this.raioMetros,
    required this.politica,
    this.distanciaMetros,
  });
  final double raioMetros;
  final double? distanciaMetros;
  final String politica;
  bool? get dentroPerimetro =>
      distanciaMetros == null ? null : distanciaMetros! <= raioMetros;

  factory GeofencePonto.fromJson(Object? value) {
    final j = managementObject(value);
    final raio = j['raio_metros'];
    final distancia = j['distancia_metros'];
    if (raio is! num ||
        !raio.isFinite ||
        raio <= 0 ||
        (distancia != null &&
            (distancia is! num || !distancia.isFinite || distancia < 0))) {
      throw const FormatException('Perímetro inválido.');
    }
    return GeofencePonto(
      raioMetros: raio.toDouble(),
      distanciaMetros: (distancia as num?)?.toDouble(),
      politica: managementString(j['politica'], 'politica'),
    );
  }
}

class DecisaoPonto {
  const DecisaoPonto({
    required this.id,
    required this.tipo,
    required this.motivo,
    required this.autorId,
    required this.dataHora,
    required this.sequencia,
  });
  final String id, tipo, motivo, autorId, dataHora;
  final int sequencia;
  String get descricao => switch (tipo) {
    'INVALIDACAO_GESTOR' => 'Invalidada pelo Gestor/RH',
    'REAPROVACAO_RH' => 'Reaprovada pelo RH',
    _ => 'Aprovada pelo Gestor/RH',
  };
  factory DecisaoPonto.fromJson(Object? value) {
    final j = managementObject(value);
    final tipo = managementString(j['tipo_ocorrencia'], 'tipo_ocorrencia');
    final data = managementString(j['decidido_em'], 'decidido_em');
    if (!{
          'INVALIDACAO_GESTOR',
          'APROVACAO_GESTOR',
          'REAPROVACAO_RH',
        }.contains(tipo) ||
        j['sequencia_decisao'] is! int ||
        (j['sequencia_decisao'] as int) <= 0 ||
        DateTime.tryParse(data)?.isUtc != true) {
      throw const FormatException('Histórico de decisões inválido.');
    }
    return DecisaoPonto(
      id: managementString(j['id'], 'id'),
      tipo: tipo,
      motivo: managementString(j['motivo_texto'], 'motivo_texto'),
      autorId: managementString(
        j['gestor_aprovador_id'],
        'gestor_aprovador_id',
      ),
      dataHora: data,
      sequencia: j['sequencia_decisao'] as int,
    );
  }
}

class MarcacaoEspelho {
  const MarcacaoEspelho({
    required this.id,
    required this.tipo,
    required this.situacao,
    required this.dataHora,
    this.invalidado = false,
    this.motivoInvalidacao,
    this.fotoUrl,
    this.fotoRecebidaEm,
    this.geofence,
    this.aprovadoGestor = false,
    this.motivoAprovacao,
    this.origem = 'REGISTRO',
    this.dataHoraCorrigida,
    this.tipoCorrigido,
    this.motivoCorrecao,
    this.motivos = const [],
    this.invalidacaoId,
    this.reaprovadoRh = false,
    this.historicoDecisoes = const [],
  });
  final String id;
  final String tipo;
  final String situacao;
  final String dataHora;
  final bool invalidado;
  final String? motivoInvalidacao;
  final String? fotoUrl;
  final String? fotoRecebidaEm;
  final GeofencePonto? geofence;
  final bool aprovadoGestor;
  final String? motivoAprovacao;
  final String origem;
  final String? dataHoraCorrigida;
  final String? tipoCorrigido;
  final String? motivoCorrecao;
  final List<String> motivos;
  final String? invalidacaoId;
  final bool reaprovadoRh;
  final List<DecisaoPonto> historicoDecisoes;
  bool get podeReaprovar => !manual && invalidado && invalidacaoId != null;
  String get resumoDecisoes => historicoDecisoes
      .map((d) => '${d.sequencia}. ${d.descricao} · ${d.dataHora}\n${d.motivo}')
      .join('\n\n');
  bool get manual => origem == 'MANUAL_RH';
  bool get corrigido => motivoCorrecao != null;
  bool get podeAprovar =>
      !manual &&
      !invalidado &&
      !aprovadoGestor &&
      !corrigido &&
      {'Recusada', 'PendenteAnalise'}.contains(situacao);
  String get horarioEfetivo => dataHoraCorrigida ?? dataHora;
  String get tipoEfetivo => tipoCorrigido ?? tipo;
  String get situacaoExibida => invalidado
      ? 'Invalidado pelo Gestor/RH'
      : manual
      ? 'Manual · RH'
      : reaprovadoRh
      ? 'Reaprovada pelo RH'
      : corrigido
      ? 'Corrigida pelo RH'
      : aprovadoGestor
      ? 'Aprovada pelo Gestor/RH'
      : situacao == 'PendenteAnalise'
      ? 'Pendente de análise'
      : situacao;
  bool get temFoto => fotoUrl?.trim().isNotEmpty ?? false;
  String get motivosOriginais => motivos
      .map(
        (m) => switch (m) {
          'FORA_DO_PERIMETRO' => 'Fora do perímetro do setor',
          'LOCALIZACAO_AUSENTE' => 'Localização não informada',
          'DESVIO_RELOGIO_ACIMA_DO_LIMITE' =>
            'Desvio do relógio acima do limite',
          'APARELHO_NAO_REGISTRADO' => 'Aparelho sem autorização na recepção',
          _ => m,
        },
      )
      .join(' · ');
  factory MarcacaoEspelho.fromJson(Object? value) {
    final j = managementObject(value);
    final instante = managementString(j['ocorrido_em'], 'ocorrido_em');
    if (DateTime.tryParse(instante)?.isUtc != true ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
        ).hasMatch(instante)) {
      throw const FormatException('Marcação exige horário com fuso.');
    }
    managementDate(instante.substring(0, 10), 'data');
    if (j['invalidado'] != null && j['invalidado'] is! bool) {
      throw const FormatException('invalidado deve ser booleano.');
    }
    final invalidado = j['invalidado'] as bool? ?? false;
    final invalidacao = j['invalidacao'] == null
        ? null
        : managementObject(j['invalidacao']);
    if (invalidado && invalidacao == null) {
      throw const FormatException('Invalidação sem auditoria.');
    }
    if (j['aprovado_gestor'] != null && j['aprovado_gestor'] is! bool) {
      throw const FormatException('Aprovação inválida.');
    }
    final aprovado = j['aprovado_gestor'] as bool? ?? false;
    final aprovacao = j['aprovacao'] == null
        ? null
        : managementObject(j['aprovacao']);
    if (aprovado && aprovacao == null) {
      throw const FormatException('Aprovação sem auditoria.');
    }
    final correcao = j['correcao'] == null
        ? null
        : managementObject(j['correcao']);
    final efetivo = managementOptionalString(
      j['ocorrido_em_efetivo'],
      'ocorrido_em_efetivo',
    );
    if (efetivo != null &&
        (DateTime.tryParse(efetivo)?.isUtc != true ||
            !RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(efetivo))) {
      throw const FormatException('Horário efetivo inválido.');
    }
    final motivos = j['motivos'] ?? const [];
    if (motivos is! List || motivos.any((m) => m is! String)) {
      throw const FormatException('Motivos inválidos.');
    }
    final fotoRecebida = managementOptionalString(
      j['foto_recebida_em'],
      'foto_recebida_em',
    );
    if (j['reaprovado_rh'] != null && j['reaprovado_rh'] is! bool) {
      throw const FormatException('Reaprovação inválida.');
    }
    final reaprovado = j['reaprovado_rh'] as bool? ?? false;
    if (reaprovado && (!aprovado || invalidado)) {
      throw const FormatException('Estado de reaprovação inconsistente.');
    }
    final rawHistorico = j['historico_decisoes'] ?? const [];
    if (rawHistorico is! List) {
      throw const FormatException('Histórico inválido.');
    }
    final historico = rawHistorico
        .map(DecisaoPonto.fromJson)
        .toList(growable: false);
    if (historico.map((d) => d.sequencia).toSet().length != historico.length) {
      throw const FormatException('Decisão duplicada no histórico.');
    }
    if (fotoRecebida != null &&
        (DateTime.tryParse(fotoRecebida)?.isUtc != true ||
            !RegExp(
              r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
            ).hasMatch(fotoRecebida))) {
      throw const FormatException(
        'Recebimento da selfie exige horário com fuso.',
      );
    }
    return MarcacaoEspelho(
      id: managementString(j['id'], 'id'),
      tipo: managementString(j['tipo'], 'tipo'),
      situacao: managementString(j['situacao'], 'situacao'),
      dataHora: instante,
      fotoUrl: managementOptionalString(j['foto_url'], 'foto_url')?.trim(),
      fotoRecebidaEm: fotoRecebida,
      geofence: j['geofence'] == null
          ? null
          : GeofencePonto.fromJson(j['geofence']),
      invalidado: invalidado,
      invalidacaoId: invalidacao == null
          ? null
          : managementOptionalString(invalidacao['id'], 'invalidacao.id'),
      reaprovadoRh: reaprovado,
      historicoDecisoes: List.unmodifiable(historico),
      origem: managementOptionalString(j['origem'], 'origem') ?? 'REGISTRO',
      aprovadoGestor: aprovado,
      motivoAprovacao: aprovacao == null
          ? null
          : managementString(aprovacao['motivo_texto'], 'motivo_texto'),
      dataHoraCorrigida: correcao == null ? null : efetivo,
      tipoCorrigido: correcao == null
          ? null
          : managementString(j['tipo_efetivo'], 'tipo_efetivo'),
      motivoCorrecao: correcao == null
          ? null
          : managementString(correcao['motivo_texto'], 'motivo_texto'),
      motivos: List.unmodifiable(motivos.cast<String>()),
      motivoInvalidacao: invalidacao == null
          ? null
          : managementString(invalidacao['motivo_texto'], 'motivo_texto'),
    );
  }
}

class DiaEspelho {
  const DiaEspelho({
    required this.data,
    required this.status,
    required this.descricao,
    this.setor,
    this.escala,
    this.previstos = 0,
    this.trabalhados = 0,
    this.abonados = 0,
    this.faltas = 0,
    this.atrasos = 0,
    this.extras = 0,
    this.pendencias = const [],
    this.marcacoes = const [],
    this.temFeriado = false,
    this.temAfastamento = false,
  });
  final String data;
  final String status;
  final String descricao;
  final String? setor;
  final String? escala;
  final num previstos;
  final num trabalhados;
  final num abonados;
  final num faltas;
  final num atrasos;
  final num extras;
  final List<String> pendencias;
  final List<MarcacaoEspelho> marcacoes;
  final bool temFeriado;
  final bool temAfastamento;
  bool get justificado =>
      status == 'ABONADO_JUSTIFICADO' || status == 'ABONO_PARCIAL';
}

class EspelhoMensal {
  EspelhoMensal({
    required this.funcionario,
    required this.ano,
    required this.mes,
    required Iterable<DiaEspelho> dias,
    this.totais = const {},
    this.fusoHorario = 'America/Sao_Paulo',
    this.temPendencias = false,
    this.apuracaoDefinitiva = false,
    this.usuarioId,
  }) : dias = List.unmodifiable(dias);
  final Funcionario funcionario;
  final int ano;
  final int mes;
  final List<DiaEspelho> dias;
  final Map<String, num> totais;
  final String fusoHorario;
  final bool temPendencias;
  final bool apuracaoDefinitiva;
  final String? usuarioId;
  num total(num Function(DiaEspelho) field) =>
      dias.fold(0, (sum, day) => sum + field(day));
  num totalApi(String campo) => totais['minutos_$campo'] ?? 0;

  factory EspelhoMensal.fromJson(Object? value, String empresaId) {
    final j = managementObject(value);
    if (j['empresa_id'] != empresaId) {
      throw const FormatException('Empresa incompatível.');
    }
    num minutos(Object? value) {
      if (value is! num || !value.isFinite || value < 0) {
        throw const FormatException('Horas inválidas.');
      }
      return value;
    }

    final totais = managementObject(j['totais']);
    final historico = j['alocacoes_historicas'];
    final rawDias = j['dias'];
    if (rawDias is! List ||
        historico is! List ||
        j['ano'] is! int ||
        j['mes'] is! int ||
        j['tem_pendencias'] is! bool ||
        j['apuracao_definitiva'] is! bool) {
      throw const FormatException('Espelho inválido.');
    }
    final funcionario = managementObject(j['funcionario']);
    return EspelhoMensal(
      usuarioId: managementOptionalString(
        funcionario['usuario_id'],
        'usuario_id',
      ),
      funcionario: Funcionario.fromJson({
        ...funcionario,
        'empresa_id': empresaId,
      }),
      ano: j['ano'] as int,
      mes: j['mes'] as int,
      fusoHorario: managementString(j['fuso_horario'], 'fuso_horario'),
      temPendencias: j['tem_pendencias'] as bool,
      apuracaoDefinitiva: j['apuracao_definitiva'] as bool,
      totais: Map.unmodifiable({
        for (final campo in [
          'previstos',
          'trabalhados',
          'abonados',
          'faltas',
          'atrasos',
          'exigiveis',
          'extras',
        ])
          'minutos_$campo': minutos(
            totais['minutos_$campo'] ?? (campo == 'extras' ? 0 : null),
          ),
      }),
      dias: rawDias.map((raw) {
        final d = managementObject(raw);
        final iso = managementDate(d['data'], 'data');
        final intervalos = d['intervalos_previstos'];
        final feriados = d['feriados'];
        final afastamentos = d['afastamentos'];
        final pendencias = d['pendencias'];
        final marcacoes = d['marcacoes'] ?? const [];
        if (intervalos is! List ||
            feriados is! List ||
            afastamentos is! List ||
            pendencias is! List ||
            marcacoes is! List ||
            pendencias.any((p) => p is! String)) {
          throw const FormatException('Dia inválido.');
        }
        final nomesSetores = <String>{}, nomesEscalas = <String>{};
        for (final raw in intervalos) {
          final i = managementObject(raw);
          nomesSetores.add(managementString(i['setor_nome'], 'setor_nome'));
          nomesEscalas.add(managementString(i['escala_nome'], 'escala_nome'));
        }
        if (intervalos.isEmpty) {
          for (final raw in historico) {
            final a = managementObject(raw);
            if (managementDate(
                      a['data_inicio'],
                      'data_inicio',
                    ).compareTo(iso) <=
                    0 &&
                (a['data_fim'] == null ||
                    managementDate(a['data_fim'], 'data_fim').compareTo(iso) >=
                        0)) {
              nomesSetores.add(
                managementString(managementObject(a['setor'])['nome'], 'nome'),
              );
              if (a['escala'] != null) {
                nomesEscalas.add(
                  managementString(
                    managementObject(a['escala'])['nome'],
                    'nome',
                  ),
                );
              }
            }
          }
        }
        final motivos = [
          for (final f in feriados)
            managementString(managementObject(f)['descricao'], 'descricao'),
          for (final a in afastamentos)
            TipoAfastamento.fromApi(managementObject(a)['tipo']).label,
        ];
        return DiaEspelho(
          data: iso,
          status: managementString(d['status'], 'status'),
          descricao: motivos.isEmpty ? '—' : motivos.join(' · '),
          setor: nomesSetores.isEmpty ? null : nomesSetores.join(' / '),
          escala: nomesEscalas.isEmpty ? null : nomesEscalas.join(' / '),
          previstos: minutos(d['minutos_previstos']),
          trabalhados: minutos(d['minutos_trabalhados']),
          abonados: minutos(d['minutos_abonados']),
          faltas: minutos(d['minutos_faltas']),
          atrasos: minutos(d['minutos_atrasos']),
          extras: minutos(d['minutos_extras'] ?? 0),
          pendencias: List.unmodifiable(pendencias.cast<String>()),
          marcacoes: List.unmodifiable(marcacoes.map(MarcacaoEspelho.fromJson)),
          temFeriado: feriados.isNotEmpty,
          temAfastamento: afastamentos.isNotEmpty,
        );
      }),
    );
  }
}
