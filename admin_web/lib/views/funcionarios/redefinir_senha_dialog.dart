import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth_session.dart';
import '../../models/funcionario.dart';
import '../../providers/auth_provider.dart';
import '../../providers/funcionarios_provider.dart';
import '../../repositories/repository_failure.dart';

class RedefinirSenhaDialog extends ConsumerStatefulWidget {
  const RedefinirSenhaDialog({
    super.key,
    required this.funcionario,
    required this.sessionToken,
  });
  final Funcionario funcionario;
  final String sessionToken;
  @override
  ConsumerState<RedefinirSenhaDialog> createState() =>
      _RedefinirSenhaDialogState();
}

class _RedefinirSenhaDialogState extends ConsumerState<RedefinirSenhaDialog> {
  final _form = GlobalKey<FormState>();
  final _senha = TextEditingController(),
      _confirmacao = TextEditingController();
  bool _salvando = false, _ocultarSenha = true, _ocultarConfirmacao = true;
  String? _erro;

  bool get _sessaoValida {
    final sessao = ref.read(authProvider).asData?.value;
    return mounted &&
        sessao != null &&
        !sessao.isMock &&
        sessao.user.role == UserRole.rh &&
        sessao.accessToken == widget.sessionToken &&
        sessao.user.companyId == widget.funcionario.empresaId &&
        sessao.expiresAt.isAfter(DateTime.now());
  }

  @override
  void dispose() {
    _senha.dispose();
    _confirmacao.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || !_sessaoValida || !_form.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref
          .read(funcionarioRepositoryProvider)
          .resetarSenha(widget.funcionario.id, _senha.text);
      if (mounted && _sessaoValida) {
        _senha.clear();
        _confirmacao.clear();
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted || !_sessaoValida) return;
      final mensagem = error is RepositoryFailure
          ? error.message
          : 'Não foi possível redefinir a senha.';
      setState(() => _erro = mensagem);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider);
    final enabled = !_salvando && _sessaoValida;
    return PopScope(
      canPop: !_salvando,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Redefinir Senha'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Defina uma nova senha de acesso ao aplicativo para ${widget.funcionario.nome}.',
                ),
                const SizedBox(height: 20),
                Text(
                  'Nova senha',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('reset-senha-nova'),
                  controller: _senha,
                  enabled: enabled,
                  obscureText: _ocultarSenha,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 1024,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'Digite a nova senha',
                    helperText: 'Mínimo de 8 caracteres.',
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: _ocultarSenha
                          ? 'Mostrar nova senha'
                          : 'Ocultar nova senha',
                      onPressed: enabled
                          ? () => setState(() => _ocultarSenha = !_ocultarSenha)
                          : null,
                      icon: Icon(
                        _ocultarSenha
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) =>
                      value == null ||
                          value.length < 8 ||
                          value.length > 1024 ||
                          value.trim().isEmpty
                      ? 'Informe uma senha de 8 a 1024 caracteres.'
                      : null,
                ),
                const SizedBox(height: 20),
                Text(
                  'Confirmar nova senha',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('reset-senha-confirmacao'),
                  controller: _confirmacao,
                  enabled: enabled,
                  obscureText: _ocultarConfirmacao,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 1024,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _salvar(),
                  decoration: InputDecoration(
                    hintText: 'Repita a nova senha',
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: _ocultarConfirmacao
                          ? 'Mostrar confirmação'
                          : 'Ocultar confirmação',
                      onPressed: enabled
                          ? () => setState(
                              () => _ocultarConfirmacao = !_ocultarConfirmacao,
                            )
                          : null,
                      icon: Icon(
                        _ocultarConfirmacao
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Confirme a nova senha.'
                      : value != _senha.text
                      ? 'As senhas não conferem.'
                      : null,
                ),
                if (_erro != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _erro!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _salvando ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const Key('reset-senha-salvar'),
            onPressed: enabled ? _salvar : null,
            icon: _salvando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_reset),
            label: Text(_salvando ? 'Salvando…' : 'Redefinir Senha'),
          ),
        ],
      ),
    );
  }
}
