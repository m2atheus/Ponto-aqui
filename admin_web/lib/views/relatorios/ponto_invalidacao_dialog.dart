import 'package:flutter/material.dart';

import '../../repositories/ponto_admin_repository.dart';
import '../../repositories/repository_failure.dart';

class InvalidarPontoButton extends StatelessWidget {
  const InvalidarPontoButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFCA5A5)
          : const Color(0xFFB33A3A),
    ),
    onPressed: onPressed,
    icon: const Icon(Icons.cancel_outlined),
    label: const Text('Invalidar Marcação'),
  );
}

class AprovarPontoButton extends StatelessWidget {
  const AprovarPontoButton({
    super.key,
    required this.onPressed,
    this.reaprovar = false,
  });
  final VoidCallback? onPressed;
  final bool reaprovar;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF86D5B2)
          : const Color(0xFF237A48),
    ),
    onPressed: onPressed,
    icon: Icon(reaprovar ? Icons.restore : Icons.check_circle_outline),
    label: Text(reaprovar ? 'Reaprovar Marcação' : 'Aprovar Marcação'),
  );
}

Future<void> mostrarAprovacaoPontoDialog({
  required BuildContext context,
  required PontoAdminRepository repository,
  required String registroId,
  required String funcionarioNome,
  required bool Function() sessaoValida,
  required Future<void> Function() recarregar,
}) => mostrarInvalidacaoPontoDialog(
  context: context,
  repository: repository,
  registroId: registroId,
  funcionarioNome: funcionarioNome,
  sessaoValida: sessaoValida,
  recarregar: recarregar,
  aprovar: true,
);

Future<void> mostrarInvalidacaoPontoDialog({
  required BuildContext context,
  required PontoAdminRepository repository,
  required String registroId,
  required String funcionarioNome,
  required bool Function() sessaoValida,
  required Future<void> Function() recarregar,
  bool aprovar = false,
  bool reaprovar = false,
  String? invalidacaoId,
  String? motivoInvalidacao,
}) async {
  if (!sessaoValida()) return;
  final messenger = ScaffoldMessenger.of(context);
  final salvo = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: false,
    builder: (_) => PontoInvalidacaoDialog(
      repository: repository,
      registroId: registroId,
      funcionarioNome: funcionarioNome,
      sessaoValida: sessaoValida,
      aprovar: aprovar,
      reaprovar: reaprovar,
      invalidacaoId: invalidacaoId,
      motivoInvalidacao: motivoInvalidacao,
    ),
  );
  if (salvo != true || !context.mounted || !sessaoValida()) return;
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: Color(0xFF237A48),
      content: Text(
        reaprovar
            ? 'Marcação reaprovada pelo RH. O histórico foi preservado.'
            : aprovar
            ? 'Marcação aprovada. O registro original foi preservado.'
            : 'Marcação invalidada. O registro original foi preservado.',
        style: TextStyle(color: Colors.white),
      ),
    ),
  );
  // Uma falha de recarga não deve induzir a repetição de um POST já confirmado.
  try {
    await recarregar();
  } catch (_) {
    if (context.mounted && sessaoValida()) {
      final colors = Theme.of(context).colorScheme;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: colors.error,
          content: Text(
            'A decisão foi salva. Consulte o espelho novamente para atualizar a lista.',
            style: TextStyle(color: colors.onError),
          ),
        ),
      );
    }
  }
}

class PontoInvalidacaoDialog extends StatefulWidget {
  const PontoInvalidacaoDialog({
    super.key,
    required this.repository,
    required this.registroId,
    required this.funcionarioNome,
    required this.sessaoValida,
    this.aprovar = false,
    this.reaprovar = false,
    this.invalidacaoId,
    this.motivoInvalidacao,
  });
  final PontoAdminRepository repository;
  final String registroId;
  final String funcionarioNome;
  final bool Function() sessaoValida;
  final bool aprovar;
  final bool reaprovar;
  final String? invalidacaoId, motivoInvalidacao;

  @override
  State<PontoInvalidacaoDialog> createState() => _PontoInvalidacaoDialogState();
}

class _PontoInvalidacaoDialogState extends State<PontoInvalidacaoDialog> {
  final _form = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  bool _salvando = false;
  String get _acao => widget.reaprovar
      ? 'reaprovacao'
      : widget.aprovar
      ? 'aprovacao'
      : 'invalidacao';

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || !_form.currentState!.validate()) return;
    if (!widget.sessaoValida()) {
      _erro('A sessão foi alterada. Entre novamente.');
      return;
    }
    setState(() => _salvando = true);
    try {
      if (widget.reaprovar) {
        await widget.repository.reaprovarMarcacao(
          registroId: widget.registroId,
          invalidacaoId: widget.invalidacaoId ?? '',
          motivoTexto: _motivo.text,
        );
      } else {
        await (widget.aprovar
            ? widget.repository.aprovarMarcacao
            : widget.repository.invalidarMarcacao)(
          registroId: widget.registroId,
          motivoTexto: _motivo.text,
        );
      }
      if (mounted) Navigator.of(context).pop(widget.sessaoValida());
    } catch (error) {
      if (mounted && widget.sessaoValida()) {
        _erro(
          error is RepositoryFailure
              ? error.message
              : 'Não foi possível salvar a decisão. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _erro(String mensagem) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: colors.error,
        content: Text(mensagem, style: TextStyle(color: colors.onError)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_salvando,
    child: AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        widget.reaprovar
            ? 'Reaprovar marcação invalidada'
            : widget.aprovar
            ? 'Aprovar marcação'
            : 'Invalidar marcação',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.funcionarioNome,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.reaprovar
                      ? 'Esta revisão do RH fará a batida voltar à apuração. '
                            'A invalidação anterior será mantida no histórico. Confira a evidência e justifique a reversão.'
                      : widget.aprovar
                      ? 'A batida será considerada na apuração, mantendo o horário original. Confira a foto e os motivos da recusa. Horas exigem pares válidos de entrada e saída; se o horário estiver errado, solicite uma correção ao RH.'
                      : 'A batida será desconsiderada na apuração. O original e o motivo ficarão preservados para auditoria.',
                ),
                if (widget.reaprovar && widget.motivoInvalidacao != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Motivo da invalidação atual: ${widget.motivoInvalidacao}',
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  widget.reaprovar
                      ? 'Motivo da reaprovação'
                      : widget.aprovar
                      ? 'Motivo da aprovação'
                      : 'Motivo da invalidação',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: Key('$_acao-motivo'),
                  controller: _motivo,
                  enabled: !_salvando,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 5000,
                  decoration: InputDecoration(
                    hintText: widget.reaprovar
                        ? 'Explique por que a invalidação deve ser revertida'
                        : widget.aprovar
                        ? 'Explique por que esta batida deve ser considerada'
                        : 'Descreva o motivo da invalidação',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? (widget.reaprovar
                            ? 'Informe o motivo da reaprovação.'
                            : widget.aprovar
                            ? 'Informe o motivo da aprovação.'
                            : 'Informe o motivo da invalidação.')
                      : value.trim().length > 5000
                      ? 'Use até 5000 caracteres.'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          key: Key('$_acao-confirmar'),
          onPressed: _salvando ? null : _salvar,
          icon: _salvando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  widget.reaprovar
                      ? Icons.restore
                      : widget.aprovar
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                ),
          label: Text(
            _salvando
                ? 'Salvando…'
                : widget.reaprovar
                ? 'Confirmar reaprovação'
                : widget.aprovar
                ? 'Confirmar aprovação'
                : 'Confirmar invalidação',
          ),
        ),
      ],
    ),
  );
}
