import 'package:flutter/material.dart';

import '../../models/w06.dart';
import '../../utils/civil_date.dart';
import '../widgets/w06_widgets.dart';

/// Filtra somente a apresentação; os totais do mês continuam vindo da API.
class EspelhoPontoView extends StatelessWidget {
  const EspelhoPontoView({super.key, required this.dias});

  final List<DiaEspelho> dias;

  static List<DiaEspelho> filtrarDias(Iterable<DiaEspelho> dias) => dias
      .where((dia) {
        final temBatida = dia.trabalhados > 0 || dia.marcacoes.isNotEmpty;
        // A API só apura faltas após o fim do turno, no fuso da empresa.
        // Não compara datas com o relógio/fuso do navegador.
        final temFaltaApurada =
            dia.previstos > 0 &&
            (dia.faltas > 0 || dia.status == 'FALTA') &&
            !dia.temAfastamento &&
            !dia.justificado;

        return temBatida ||
            dia.temFeriado ||
            dia.temAfastamento ||
            dia.justificado ||
            temFaltaApurada;
      })
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final diasVisiveis = filtrarDias(dias);
    if (diasVisiveis.isEmpty) {
      final colors = Theme.of(context).colorScheme;
      return Card(
        key: const Key('espelho-vazio'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_note_outlined,
                size: 40,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'Nenhum registro ou feriado encontrado para este período.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return W06Table(
      columns: const [
        DataColumn(label: Text('Data')),
        DataColumn(label: Text('Setor / Escala histórica')),
        DataColumn(label: Text('Situação')),
        DataColumn(label: Text('Previstas')),
        DataColumn(label: Text('Trabalhadas')),
        DataColumn(label: Text('Extras')),
        DataColumn(label: Text('Abonadas')),
        DataColumn(label: Text('Falta / Atraso')),
        DataColumn(label: Text('Motivo')),
      ],
      rows: [
        for (final dia in diasVisiveis)
          DataRow(
            key: ValueKey('espelho-${dia.data}'),
            color: dia.justificado
                ? WidgetStatePropertyAll(Colors.green.withValues(alpha: .07))
                : null,
            cells: [
              DataCell(Text(civilDateDisplay(dia.data))),
              DataCell(
                SizedBox(
                  width: 200,
                  child: Text(
                    '${dia.setor ?? '—'}\n${dia.escala ?? 'Sem escala'}',
                  ),
                ),
              ),
              DataCell(_Situacao(dia: dia)),
              DataCell(Text(w06Hours(dia.previstos))),
              DataCell(Text(w06Hours(dia.trabalhados))),
              DataCell(Text(w06Hours(dia.extras))),
              DataCell(Text(w06Hours(dia.abonados))),
              DataCell(
                Text('${w06Hours(dia.faltas)} / ${w06Hours(dia.atrasos)}'),
              ),
              DataCell(
                SizedBox(
                  width: 220,
                  child: Text(
                    dia.descricao,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Situacao extends StatelessWidget {
  const _Situacao({required this.dia});
  final DiaEspelho dia;
  @override
  Widget build(BuildContext context) {
    final label = switch (dia.status) {
      'ABONADO_JUSTIFICADO' => 'Abonado / Justificado',
      'ABONO_PARCIAL' => 'Abono parcial',
      'ATRASO' => 'Atraso',
      'JORNADA_INCOMPLETA' => 'Jornada incompleta',
      'APURACAO_PENDENTE' => 'Aguardando análise',
      'TRABALHADO' => 'Trabalhado',
      'FOLGA' => 'Folga',
      'FALTA' => 'Falta',
      'PREVISTO' => 'Previsto',
      'EM_ANDAMENTO' => 'Em andamento',
      _ => 'Sem alocação',
    };
    final color = dia.justificado
        ? (Theme.of(context).brightness == Brightness.dark
              ? Colors.green.shade300
              : Colors.green.shade800)
        : dia.status == 'FALTA'
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          dia.justificado
              ? Icons.verified_outlined
              : dia.status == 'FALTA'
              ? Icons.error_outline
              : Icons.schedule,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}
