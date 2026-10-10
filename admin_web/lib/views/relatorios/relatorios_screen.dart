import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/w06.dart';
import '../../models/auth_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/w06_provider.dart';
import '../../utils/civil_date.dart';
import '../widgets/w06_widgets.dart';
import 'ponto_ajuste_dialog.dart';

const _meses = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

class RelatoriosScreen extends ConsumerStatefulWidget {
  const RelatoriosScreen({super.key});
  @override
  ConsumerState<RelatoriosScreen> createState() => _RelatoriosScreenState();
}

class _RelatoriosScreenState extends ConsumerState<RelatoriosScreen> {
  final _form = GlobalKey<FormState>();
  late final _anoController = TextEditingController(
    text: '${DateTime.now().year}',
  );
  int _mes = DateTime.now().month;
  String? _funcionarioId;
  bool _carregando = false;
  bool _dialogAberto = false;
  int _pedido = 0;
  String? _erro;
  EspelhoMensal? _espelho;
  W06Data? _dadosDoEspelho;

  Future<void> _ajustar(
    W06Data data,
    EspelhoMensal espelho, [
    MarcacaoEspelho? ponto,
  ]) async {
    final sessao = ref.read(authProvider).asData?.value;
    if (_dialogAberto ||
        _carregando ||
        sessao == null ||
        sessao.isMock ||
        sessao.user.role != UserRole.rh ||
        (ponto == null && espelho.usuarioId == null)) {
      return;
    }
    bool mesmaSessao() =>
        mounted &&
        ref.read(authProvider).asData?.value?.accessToken ==
            sessao.accessToken &&
        sessao.expiresAt.isAfter(DateTime.now());
    setState(() => _dialogAberto = true);
    try {
      await mostrarAjustePontoDialog(
        context: context,
        repository: ref.read(pontoAdminRepositoryProvider),
        funcionarioNome: espelho.funcionario.nome,
        fusoHorario: espelho.fusoHorario,
        sessaoValida: mesmaSessao,
        usuarioId: espelho.usuarioId,
        registroOriginalId: ponto?.id,
        dataHoraInicial: ponto == null
            ? DateTime.utc(espelho.ano, espelho.mes, 1, 12)
            : DateTime.parse(ponto.dataHora),
        recarregar: () async {
          if (mesmaSessao()) await _gerar(data, propagarErro: true);
        },
      );
    } catch (error) {
      if (mounted && mesmaSessao()) {
        w06Message(context, w06Error(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _dialogAberto = false);
    }
  }

  @override
  void dispose() {
    _pedido++;
    _anoController.dispose();
    super.dispose();
  }

  void _alterar(VoidCallback change) => setState(() {
    change();
    _pedido++;
    _espelho = null;
    _erro = null;
    _carregando = false;
  });

  Future<void> _gerar(W06Data data, {bool propagarErro = false}) async {
    if (_carregando || !_form.currentState!.validate()) return;
    final sessionToken = ref.read(authProvider).asData?.value?.accessToken;
    final pedido = ++_pedido;
    setState(() {
      _carregando = true;
      _espelho = null;
      _erro = null;
    });
    try {
      final resultado = await ref
          .read(w06RepositoryProvider)
          .espelho(
            _funcionarioId!,
            int.parse(_anoController.text.trim()),
            _mes,
          );
      if (!mounted ||
          pedido != _pedido ||
          sessionToken != ref.read(authProvider).asData?.value?.accessToken ||
          !identical(ref.read(w06Provider).asData?.value, data)) {
        return;
      }
      setState(() {
        _espelho = resultado;
        _dadosDoEspelho = data;
      });
    } catch (error) {
      if (mounted &&
          pedido == _pedido &&
          sessionToken == ref.read(authProvider).asData?.value?.accessToken) {
        setState(() => _erro = w06Error(error));
        w06Message(context, _erro!, error: true);
      }
      if (propagarErro) rethrow;
    } finally {
      if (mounted && pedido == _pedido) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) => W06Content(
    path: '/relatorios',
    builder: (data) {
      final espelho = identical(_dadosDoEspelho, data) ? _espelho : null;
      return W06PageLayout(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Text(
              'Relatórios',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Consulte o espelho mensal considerando a escala vigente em cada período.',
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _form,
                  child: LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth < 400
                              ? constraints.maxWidth
                              : 320,
                          child: DropdownButtonFormField<String>(
                            key: const Key('relatorio-funcionario'),
                            initialValue: _funcionarioId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Funcionário',
                            ),
                            items: [
                              for (final f in data.funcionarios)
                                DropdownMenuItem(
                                  value: f.id,
                                  child: Text(
                                    '${f.nome} · ${f.matricula}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _carregando || _dialogAberto
                                ? null
                                : (v) => _alterar(() => _funcionarioId = v),
                            validator: (v) =>
                                v == null ? 'Selecione um funcionário.' : null,
                          ),
                        ),
                        SizedBox(
                          width: constraints.maxWidth < 200
                              ? constraints.maxWidth
                              : 190,
                          child: DropdownButtonFormField<int>(
                            key: const Key('relatorio-mes'),
                            initialValue: _mes,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Mês'),
                            items: [
                              for (var i = 0; i < 12; i++)
                                DropdownMenuItem(
                                  value: i + 1,
                                  child: Text(_meses[i]),
                                ),
                            ],
                            onChanged: _carregando || _dialogAberto
                                ? null
                                : (v) => _alterar(() => _mes = v!),
                          ),
                        ),
                        SizedBox(
                          width: constraints.maxWidth < 130
                              ? constraints.maxWidth
                              : 120,
                          child: TextFormField(
                            key: const Key('relatorio-ano'),
                            controller: _anoController,
                            enabled: !_carregando && !_dialogAberto,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Ano',
                              hintText: 'AAAA',
                            ),
                            onChanged: (_) => _alterar(() {}),
                            validator: (value) {
                              final ano = int.tryParse(value?.trim() ?? '');
                              return ano == null || ano < 1900 || ano > 2100
                                  ? '1900 a 2100.'
                                  : null;
                            },
                          ),
                        ),
                        FilledButton.icon(
                          key: const Key('gerar-espelho'),
                          onPressed:
                              _carregando ||
                                  _dialogAberto ||
                                  data.funcionarios.isEmpty
                              ? null
                              : () => _gerar(data),
                          icon: const Icon(Icons.summarize_outlined),
                          label: Text(
                            _carregando ? 'Consultando…' : 'Consultar espelho',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _erro!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (espelho == null && !_carregando && _erro == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Selecione o funcionário e o mês para consultar o espelho.',
                ),
              ),
            if (espelho != null) ...[
              const SizedBox(height: 20),
              Text(
                '${espelho.funcionario.nome} · ${_meses[espelho.mes - 1]} / ${espelho.ano}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (ref.watch(authProvider).asData?.value?.user.role ==
                  UserRole.rh) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Tooltip(
                    message: espelho.usuarioId == null
                        ? 'Vincule uma conta de usuário ao funcionário para inserir ajustes.'
                        : 'Adicionar uma batida aprovada pelo RH',
                    child: FilledButton.icon(
                      key: const Key('inserir-ponto-manual'),
                      onPressed:
                          _carregando ||
                              _dialogAberto ||
                              espelho.usuarioId == null
                          ? null
                          : () => _ajustar(data, espelho),
                      icon: const Icon(Icons.add_alarm),
                      label: const Text('Inserir Ponto Manual'),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Feriados e afastamentos em verde abonam a jornada; o histórico define o setor de cada dia.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Total(
                    label: 'Previstas',
                    minutos: espelho.totalApi('previstos'),
                  ),
                  _Total(
                    label: 'Trabalhadas',
                    minutos: espelho.totalApi('trabalhados'),
                  ),
                  _Total(
                    label: 'Abonadas',
                    minutos: espelho.totalApi('abonados'),
                    verde: true,
                  ),
                  _Total(label: 'Faltas', minutos: espelho.totalApi('faltas')),
                  _Total(
                    label: 'Atrasos',
                    minutos: espelho.totalApi('atrasos'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!espelho.apuracaoDefinitiva)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Apuração preliminar · Fuso: ${espelho.fusoHorario}. '
                      '${espelho.temPendencias ? 'Há marcações ou ajustes que exigem análise.' : 'Confira os dados antes do fechamento.'}',
                    ),
                  ),
                ),
              W06Table(
                columns: const [
                  DataColumn(label: Text('Data')),
                  DataColumn(label: Text('Setor / Escala histórica')),
                  DataColumn(label: Text('Situação')),
                  DataColumn(label: Text('Previstas')),
                  DataColumn(label: Text('Trabalhadas')),
                  DataColumn(label: Text('Abonadas')),
                  DataColumn(label: Text('Falta / Atraso')),
                  DataColumn(label: Text('Motivo')),
                ],
                rows: [
                  for (final dia in espelho.dias)
                    DataRow(
                      key: ValueKey('espelho-${dia.data}'),
                      color: dia.justificado
                          ? WidgetStatePropertyAll(
                              Colors.green.withValues(alpha: .07),
                            )
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
                        DataCell(Text(w06Hours(dia.abonados))),
                        DataCell(
                          Text(
                            '${w06Hours(dia.faltas)} / ${w06Hours(dia.atrasos)}',
                          ),
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
              ),
              const SizedBox(height: 20),
              Text(
                'Batidas do funcionário',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'As batidas originais são preservadas. Correções são salvas separadamente como ajustes.',
              ),
              const SizedBox(height: 12),
              W06Table(
                emptyMessage: 'Nenhuma batida original neste mês.',
                columns: const [
                  DataColumn(label: Text('Data')),
                  DataColumn(label: Text('Hora')),
                  DataColumn(label: Text('Tipo')),
                  DataColumn(label: Text('Situação')),
                  DataColumn(label: Text('Ações')),
                ],
                rows: [
                  for (final dia in espelho.dias)
                    for (final ponto in dia.marcacoes)
                      DataRow(
                        key: ValueKey('batida-${ponto.id}'),
                        cells: [
                          DataCell(Text(civilDateDisplay(dia.data))),
                          DataCell(Text(ponto.dataHora.substring(11, 16))),
                          DataCell(
                            Text(switch (ponto.tipo) {
                              'InicioIntervalo' => 'Início do intervalo',
                              'FimIntervalo' => 'Fim do intervalo',
                              'Saida' => 'Saída',
                              _ => ponto.tipo,
                            }),
                          ),
                          DataCell(
                            Text(switch (ponto.situacao) {
                              'PendenteAnalise' => 'Pendente de análise',
                              _ => ponto.situacao,
                            }),
                          ),
                          DataCell(
                            IconButton(
                              key: ValueKey('editar-batida-${ponto.id}'),
                              tooltip: 'Editar Batida',
                              onPressed:
                                  _carregando ||
                                      _dialogAberto ||
                                      ref
                                              .read(authProvider)
                                              .asData
                                              ?.value
                                              ?.user
                                              .role !=
                                          UserRole.rh
                                  ? null
                                  : () => _ajustar(data, espelho, ponto),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ),
                        ],
                      ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.minutos,
    this.verde = false,
  });
  final String label;
  final num minutos;
  final bool verde;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 165,
    child: Card(
      color: verde ? Colors.green.withValues(alpha: .08) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            Text(
              w06Hours(minutos),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    ),
  );
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
