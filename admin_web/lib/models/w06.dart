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
  });
  final String id;
  final String funcionarioId;
  final String setorId;
  final String escalaNome;
  final String inicio;
  final String? fim;
  factory HistoricoAlocacao.fromJson(Object? value) {
    final j = managementObject(value);
    return HistoricoAlocacao(
      id: managementString(j['id'], 'id'),
      funcionarioId: managementString(j['funcionario_id'], 'funcionario_id'),
      setorId: managementString(j['setor_id'], 'setor_id'),
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

class MarcacaoEspelho {
  const MarcacaoEspelho({
    required this.id,
    required this.tipo,
    required this.situacao,
    required this.dataHora,
  });
  final String id;
  final String tipo;
  final String situacao;
  final String dataHora;
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
    return MarcacaoEspelho(
      id: managementString(j['id'], 'id'),
      tipo: managementString(j['tipo'], 'tipo'),
      situacao: managementString(j['situacao'], 'situacao'),
      dataHora: instante,
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
    this.pendencias = const [],
    this.marcacoes = const [],
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
  final List<String> pendencias;
  final List<MarcacaoEspelho> marcacoes;
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
        ])
          'minutos_$campo': minutos(totais['minutos_$campo']),
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
          pendencias: List.unmodifiable(pendencias.cast<String>()),
          marcacoes: List.unmodifiable(marcacoes.map(MarcacaoEspelho.fromJson)),
        );
      }),
    );
  }
}
