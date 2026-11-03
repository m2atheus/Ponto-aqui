import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../models/w06.dart';
import '../../repositories/ponto_admin_repository.dart';
import '../../repositories/repository_failure.dart';
import '../../utils/civil_date.dart';
import 'ponto_invalidacao_dialog.dart';

Future<void> mostrarDetalhePontoDialog({
  required BuildContext context,
  required MarcacaoEspelho ponto,
  required String funcionarioNome,
  required String fusoHorario,
  required PontoAdminRepository repository,
  required bool Function() sessaoValida,
  required Future<void> Function() recarregar,
  bool podeReaprovarRh = false,
}) async {
  if (!ponto.temFoto || !sessaoValida()) return;
  var alterou = false;
  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: false,
    builder: (_) => DetalhePontoDialog(
      ponto: ponto,
      funcionarioNome: funcionarioNome,
      fusoHorario: fusoHorario,
      repository: repository,
      sessaoValida: sessaoValida,
      onInvalidada: () => alterou = true,
      podeReaprovarRh: podeReaprovarRh,
    ),
  );
  // Também recarrega quando o modal foi fechado pelo teclado/navegador.
  if (alterou && context.mounted && sessaoValida()) await recarregar();
}

class DetalhePontoDialog extends StatefulWidget {
  const DetalhePontoDialog({
    super.key,
    required this.ponto,
    required this.funcionarioNome,
    required this.fusoHorario,
    required this.repository,
    required this.sessaoValida,
    required this.onInvalidada,
    this.podeReaprovarRh = false,
  });
  final MarcacaoEspelho ponto;
  final String funcionarioNome;
  final String fusoHorario;
  final PontoAdminRepository repository;
  final bool Function() sessaoValida;
  final VoidCallback onInvalidada;
  final bool podeReaprovarRh;

  @override
  State<DetalhePontoDialog> createState() => _DetalhePontoDialogState();
}

class _DetalhePontoDialogState extends State<DetalhePontoDialog> {
  CancelToken? _cancel;
  ImageProvider? _imagem;
  String? _erro;
  bool _carregando = true;
  bool _invalidando = false;
  late bool _invalidado = widget.ponto.invalidado;
  late bool _aprovado = widget.ponto.aprovadoGestor;
  late bool _reaprovado = widget.ponto.reaprovadoRh;
  bool _decisaoAlterada = false;

  @override
  void initState() {
    super.initState();
    _carregarFoto();
  }

  @override
  void dispose() {
    _cancel?.cancel('Visualização encerrada.');
    _imagem?.evict();
    super.dispose();
  }

  Future<void> _carregarFoto() async {
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      if (!widget.sessaoValida()) {
        throw const RepositoryFailure('Sessão expirada. Entre novamente.');
      }
      final bytes = await widget.repository.baixarSelfie(
        widget.ponto.id,
        cancelToken: cancel,
      );
      if (!mounted || cancel.isCancelled || !widget.sessaoValida()) return;
      _imagem?.evict();
      setState(
        () => _imagem = ResizeImage(
          MemoryImage(bytes),
          width: 1200,
          allowUpscaling: false,
        ),
      );
    } catch (error) {
      if (mounted && !cancel.isCancelled) {
        setState(
          () => _erro = error is RepositoryFailure
              ? error.message
              : 'Não foi possível carregar a foto.',
        );
      }
    } finally {
      if (mounted && !cancel.isCancelled) setState(() => _carregando = false);
    }
  }

  Future<void> _invalidar({
    bool aprovar = false,
    bool reaprovar = false,
  }) async {
    if (_invalidando ||
        (_invalidado && !reaprovar) ||
        (aprovar && !reaprovar && (_aprovado || !widget.ponto.podeAprovar)) ||
        (reaprovar &&
            (!widget.podeReaprovarRh ||
                !widget.ponto.podeReaprovar ||
                _decisaoAlterada)) ||
        !widget.sessaoValida()) {
      return;
    }
    setState(() => _invalidando = true);
    try {
      // O formulário existente valida o motivo e realiza o POST com Dio.
      final salvo = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => PontoInvalidacaoDialog(
          repository: widget.repository,
          registroId: widget.ponto.id,
          funcionarioNome: widget.funcionarioNome,
          sessaoValida: widget.sessaoValida,
          aprovar: aprovar,
          reaprovar: reaprovar,
          invalidacaoId: widget.ponto.invalidacaoId,
          motivoInvalidacao: widget.ponto.motivoInvalidacao,
        ),
      );
      if (salvo == true && mounted && widget.sessaoValida()) {
        setState(() {
          _decisaoAlterada = true;
          if (aprovar) {
            _aprovado = true;
            _invalidado = false;
            _reaprovado = reaprovar;
          } else {
            _invalidado = true;
          }
        });
        widget.onInvalidada();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Color(0xFF237A48),
            content: Text(
              reaprovar
                  ? 'Marcação reaprovada pelo RH. O histórico foi preservado.'
                  : aprovar
                  ? 'Marcação aprovada. O original foi preservado.'
                  : 'Marcação invalidada. O original foi preservado.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _invalidando = false);
    }
  }

  String _horario(String valor) =>
      '${civilDateDisplay(valor.substring(0, 10))} às ${valor.substring(11, 19)}';

  Widget _falhaFoto(String mensagem) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mensagem, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _invalidando ? null : _carregarFoto,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final geo = widget.ponto.geofence;
    final situacao = _invalidado
        ? 'Invalidado'
        : _reaprovado
        ? 'Reaprovada pelo RH'
        : _aprovado
        ? 'Aprovada pelo Gestor/RH'
        : widget.ponto.situacaoExibida;
    return PopScope(
      canPop: !_invalidando,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text('Selfie · ${widget.funcionarioNome}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _invalidado
                        ? colors.errorContainer
                        : colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    situacao,
                    key: const Key('detalhe-situacao'),
                    style: TextStyle(
                      color: _invalidado
                          ? colors.onErrorContainer
                          : colors.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.ponto.motivos.isNotEmpty)
                  Text('Motivos originais: ${widget.ponto.motivosOriginais}'),
                if (widget.ponto.motivoAprovacao case final motivo?)
                  Text('Motivo da aprovação: $motivo'),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: (MediaQuery.sizeOf(context).height * .42).clamp(
                      180.0,
                      420.0,
                    ),
                    width: double.infinity,
                    child: ColoredBox(
                      color: colors.surfaceContainerLow,
                      child: _carregando
                          ? const Center(child: CircularProgressIndicator())
                          : _erro != null
                          ? _falhaFoto(_erro!)
                          : _imagem == null
                          ? _falhaFoto('Foto indisponível.')
                          : InteractiveViewer(
                              minScale: 1,
                              maxScale: 4,
                              child: Image(
                                image: _imagem!,
                                fit: BoxFit.contain,
                                semanticLabel:
                                    'Selfie de ${widget.funcionarioNome}',
                                frameBuilder: (_, child, frame, synchronous) =>
                                    frame != null || synchronous
                                    ? child
                                    : const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                errorBuilder: (_, error, stack) => _falhaFoto(
                                  'Não foi possível exibir esta imagem.',
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Horário da marcação: ${_horario(widget.ponto.dataHora)}',
                  style: TextStyle(
                    decoration: _invalidado ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.ponto.fotoRecebidaEm case final recebido?)
                  Text('Selfie recebida: ${_horario(recebido)}'),
                Text(
                  'Fuso da empresa: ${widget.fusoHorario}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (geo != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Perímetro validado na batida',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 20,
                    runSpacing: 8,
                    children: [
                      Text('Raio: ${geo.raioMetros.toStringAsFixed(0)} m'),
                      if (geo.distanciaMetros case final distancia?)
                        Text('Distância: ${distancia.toStringAsFixed(1)} m'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    geo.politica == 'Ignorar'
                        ? 'Localização dispensada pela política do setor.'
                        : geo.dentroPerimetro == null
                        ? 'Sem posição registrada.'
                        : geo.dentroPerimetro!
                        ? 'Dentro do perímetro.'
                        : 'Fora do perímetro.',
                  ),
                ],
                if (widget.ponto.motivoInvalidacao case final motivo?) ...[
                  const SizedBox(height: 16),
                  Text('Motivo da invalidação: $motivo'),
                ],
                if (widget.ponto.historicoDecisoes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Histórico de decisões'),
                    children: [
                      for (final d in widget.ponto.historicoDecisoes)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${d.sequencia}. ${d.descricao}'),
                          subtitle: Text(
                            '${d.motivo}\n${d.dataHora}\nResponsável: ${d.autorId}',
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _invalidando ? null : () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          InvalidarPontoButton(
            onPressed: _invalidando || _invalidado ? null : () => _invalidar(),
          ),
          if (widget.ponto.podeAprovar && !_aprovado)
            AprovarPontoButton(
              onPressed: _invalidando || _invalidado
                  ? null
                  : () => _invalidar(aprovar: true),
            ),
          if (widget.podeReaprovarRh &&
              widget.ponto.podeReaprovar &&
              _invalidado &&
              !_decisaoAlterada)
            AprovarPontoButton(
              reaprovar: true,
              onPressed: _invalidando
                  ? null
                  : () => _invalidar(aprovar: true, reaprovar: true),
            ),
        ],
      ),
    );
  }
}
