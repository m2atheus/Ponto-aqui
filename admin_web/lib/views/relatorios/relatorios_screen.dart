import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/w06.dart';
import '../../models/auth_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/w06_provider.dart';
import '../../providers/funcionarios_provider.dart';
import '../../router/access_policy.dart';
import '../../utils/civil_date.dart';
import '../widgets/w06_widgets.dart';
import '../widgets/funcionario_autocomplete.dart';
import 'ponto_ajuste_dialog.dart';
import 'espelho_ponto_view.dart';
import 'detalhe_ponto_dialog.dart';
import 'ponto_invalidacao_dialog.dart';

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
  String? _sessaoDoEspelho;

  Future<void> _verFoto(EspelhoMensal espelho, MarcacaoEspelho ponto) async {
    final sessao = ref.read(authProvider).asData?.value;
    if (_dialogAberto ||
        _carregando ||
        !ponto.temFoto ||
        sessao == null ||
        sessao.isMock ||
        !{UserRole.rh, UserRole.gestor}.contains(sessao.user.role)) {
      return;
    }
    bool mesmaSessao() =>
        mounted &&
        ref.read(authProvider).asData?.value?.accessToken ==
            sessao.accessToken &&
        sessao.expiresAt.isAfter(DateTime.now());
    setState(() => _dialogAberto = true);
    try {
      await mostrarDetalhePontoDialog(
        context: context,
        ponto: ponto,
        funcionarioNome: espelho.funcionario.nome,
        fusoHorario: espelho.fusoHorario,
        repository: ref.read(pontoAdminRepositoryProvider),
        podeReaprovarRh: sessao.user.role == UserRole.rh,
        sessaoValida: mesmaSessao,
        recarregar: () async {
          if (mesmaSessao()) await _gerar(propagarErro: true);
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

  Future<void> _invalidar(
    EspelhoMensal espelho,
    MarcacaoEspelho ponto, {
    bool aprovar = false,
    bool reaprovar = false,
  }) async {
    final sessao = ref.read(authProvider).asData?.value;
    if (_dialogAberto ||
        _carregando ||
        (ponto.invalidado && !reaprovar) ||
        ponto.manual ||
        (aprovar && !reaprovar && !ponto.podeAprovar) ||
        (reaprovar &&
            (!ponto.podeReaprovar || sessao?.user.role != UserRole.rh)) ||
        sessao == null ||
        sessao.isMock ||
        !{UserRole.rh, UserRole.gestor}.contains(sessao.user.role)) {
      return;
    }
    bool mesmaSessao() =>
        mounted &&
        ref.read(authProvider).asData?.value?.accessToken ==
            sessao.accessToken &&
        sessao.expiresAt.isAfter(DateTime.now());
    setState(() => _dialogAberto = true);
    try {
      await mostrarInvalidacaoPontoDialog(
        context: context,
        repository: ref.read(pontoAdminRepositoryProvider),
        registroId: ponto.id,
        aprovar: aprovar,
        reaprovar: reaprovar,
        invalidacaoId: ponto.invalidacaoId,
        motivoInvalidacao: ponto.motivoInvalidacao,
        funcionarioNome: espelho.funcionario.nome,
        sessaoValida: mesmaSessao,
        recarregar: () async {
          if (mesmaSessao()) await _gerar(propagarErro: true);
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

  Future<void> _ajustar(EspelhoMensal espelho, [MarcacaoEspelho? ponto]) async {
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
          if (mesmaSessao()) await _gerar(propagarErro: true);
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

  Future<void> _gerar({bool propagarErro = false}) async {
    if (_carregando) return;
    // Na recarga após uma ação, os filtros já foram validados. O Form pode
    // estar fora da área construída do ListView, pois a tabela fica abaixo.
    if (!propagarErro && !(_form.currentState?.validate() ?? false)) return;
    final sessionToken = ref.read(authProvider).asData?.value?.accessToken;
    final pedido = ++_pedido;
    setState(() {
      _carregando = true;
      if (!propagarErro) _espelho = null;
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
          sessionToken != ref.read(authProvider).asData?.value?.accessToken) {
        return;
      }
      setState(() {
        _espelho = resultado;
        _sessaoDoEspelho = sessionToken;
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
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null ||
        !session.expiresAt.isAfter(DateTime.now()) ||
        !AccessPolicy.allows(session.user.role, '/relatorios')) {
      return const Center(
        child: Text('Seu perfil não tem acesso a esta página.'),
      );
    }
    if (session.isMock) {
      return const Center(
        child: Text(
          'Entre com uma conta real da empresa para consultar o banco.',
        ),
      );
    }
    final espelho = _sessaoDoEspelho == session.accessToken ? _espelho : null;
    return W06PageLayout(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Text('Relatórios', style: Theme.of(context).textTheme.headlineMedium),
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
                    // A ajuda e os erros do funcionário não deslocam os filtros.
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth < 400
                            ? constraints.maxWidth
                            : 320,
                        child: FuncionarioAutocomplete(
                          key: ObjectKey(session),
                          repository: ref.watch(
                            funcionarioBuscaRepositoryProvider,
                          ),
                          enabled: !_carregando && !_dialogAberto,
                          onChanged: (f) =>
                              _alterar(() => _funcionarioId = f?.id),
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
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 60),
                        ),
                        onPressed: _carregando || _dialogAberto
                            ? null
                            : () => _gerar(),
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
                        : () => _ajustar(espelho),
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
                _Total(label: 'Atrasos', minutos: espelho.totalApi('atrasos')),
                _Total(
                  label: 'Horas extras',
                  minutos: espelho.totalApi('extras'),
                  verde: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Horas extras: excedente diário das horas trabalhadas sobre as exigíveis, '
              'somente em dias sem pendências e com jornada encerrada. Não inclui adicionais nem banco de horas.',
            ),
            if (espelho.dias.any(
              (d) => d.pendencias.contains('SEQUENCIA_INCOMPLETA_OU_INVALIDA'),
            ))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Há batidas sem par de entrada/saída. Aprovar uma saída isolada não gera horas; '
                  'o RH deve conferir e inserir ou corrigir a batida faltante com justificativa.',
                ),
              ),
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
            EspelhoPontoView(dias: espelho.dias),
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
              emptyMessage: 'Nenhuma batida ou ajuste aprovado neste mês.',
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
                        DataCell(
                          Text(
                            ponto.horarioEfetivo.substring(11, 16),
                            style: TextStyle(
                              decoration: ponto.invalidado
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(switch (ponto.tipoEfetivo) {
                            'InicioIntervalo' => 'Início do intervalo',
                            'FimIntervalo' => 'Fim do intervalo',
                            'Saida' => 'Saída',
                            _ => ponto.tipoEfetivo,
                          }),
                        ),
                        DataCell(
                          Tooltip(
                            message: [
                              if (ponto.corrigido)
                                'Original: ${ponto.dataHora}',
                              ponto.motivoInvalidacao ??
                                  ponto.motivoCorrecao ??
                                  ponto.motivoAprovacao ??
                                  '',
                              ponto.motivosOriginais,
                              ponto.resumoDecisoes,
                            ].where((s) => s.isNotEmpty).join('\n'),
                            child: Text(
                              ponto.situacaoExibida,
                              style: ponto.invalidado
                                  ? TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (ponto.temFoto)
                                IconButton(
                                  key: ValueKey('selfie-batida-${ponto.id}'),
                                  tooltip: 'Visualizar selfie',
                                  onPressed: _carregando || _dialogAberto
                                      ? null
                                      : () => _verFoto(espelho, ponto),
                                  icon: const Icon(Icons.camera_alt_outlined),
                                ),
                              if (!ponto.manual &&
                                  ref
                                          .read(authProvider)
                                          .asData
                                          ?.value
                                          ?.user
                                          .role ==
                                      UserRole.rh)
                                IconButton(
                                  key: ValueKey('editar-batida-${ponto.id}'),
                                  tooltip: 'Editar Batida',
                                  onPressed:
                                      ponto.invalidado ||
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
                                      : () => _ajustar(espelho, ponto),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              InvalidarPontoButton(
                                key: ValueKey('invalidar-batida-${ponto.id}'),
                                onPressed:
                                    ponto.invalidado ||
                                        ponto.manual ||
                                        _carregando ||
                                        _dialogAberto
                                    ? null
                                    : () => _invalidar(espelho, ponto),
                              ),
                              if (ponto.podeAprovar) ...[
                                const SizedBox(width: 8),
                                AprovarPontoButton(
                                  key: ValueKey('aprovar-batida-${ponto.id}'),
                                  onPressed: _carregando || _dialogAberto
                                      ? null
                                      : () => _invalidar(
                                          espelho,
                                          ponto,
                                          aprovar: true,
                                        ),
                                ),
                              ],
                              if (ponto.podeReaprovar &&
                                  session.user.role == UserRole.rh) ...[
                                const SizedBox(width: 8),
                                AprovarPontoButton(
                                  key: ValueKey('reaprovar-batida-${ponto.id}'),
                                  reaprovar: true,
                                  onPressed: _carregando || _dialogAberto
                                      ? null
                                      : () => _invalidar(
                                          espelho,
                                          ponto,
                                          aprovar: true,
                                          reaprovar: true,
                                        ),
                                ),
                              ],
                            ],
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
  }
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
