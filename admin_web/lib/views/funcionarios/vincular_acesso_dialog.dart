import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth_session.dart';
import '../../models/funcionario.dart';
import '../../providers/auth_provider.dart';
import '../../providers/funcionarios_provider.dart';
import '../../repositories/repository_failure.dart';

/// Retorna true ao criar o acesso; a tela exibe a confirmação após fechar.
class VincularAcessoDialog extends ConsumerStatefulWidget {
  const VincularAcessoDialog({
    super.key,
    required this.funcionario,
    required this.sessionToken,
  });

  final Funcionario funcionario;
  final String sessionToken;

  @override
  ConsumerState<VincularAcessoDialog> createState() =>
      _VincularAcessoDialogState();
}

class _VincularAcessoDialogState extends ConsumerState<VincularAcessoDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _salvando = false;
  bool _ocultarSenha = true;
  String? _erro;

  bool get _sessaoValida {
    final session = ref.read(authProvider).asData?.value;
    return session != null &&
        !session.isMock &&
        session.accessToken == widget.sessionToken &&
        session.user.role == UserRole.rh &&
        session.user.companyId == widget.funcionario.empresaId &&
        session.expiresAt.isAfter(DateTime.now().toUtc());
  }

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || !_form.currentState!.validate()) return;
    if (!_sessaoValida) {
      setState(() => _erro = 'A sessão foi alterada. Entre novamente.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref
          .read(funcionariosProvider.notifier)
          .vincularAcessoApp(
            widget.funcionario.id,
            _email.text.trim(),
            _senha.text,
          );
      if (mounted && _sessaoValida) {
        _senha.clear();
        Navigator.pop(context, true);
      }
    } on RepositoryFailure catch (error) {
      if (mounted && _sessaoValida) {
        setState(() => _erro = error.message);
        final colors = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colors.error,
            content: Text(
              error.message,
              style: TextStyle(color: colors.onError),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_salvando,
    child: AlertDialog(
      title: const Text('Gerar Acesso App'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Crie o acesso de ${widget.funcionario.nome} ao aplicativo.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('acesso-app-email'),
                controller: _email,
                enabled: !_salvando,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                maxLength: 254,
                decoration: const InputDecoration(labelText: 'E-mail'),
                validator: (value) =>
                    value == null ||
                        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(value.trim())
                    ? 'Informe um e-mail válido.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('acesso-app-senha'),
                controller: _senha,
                enabled: !_salvando,
                obscureText: _ocultarSenha,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 1024,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _salvar(),
                decoration: InputDecoration(
                  labelText: 'Senha',
                  helperText: 'Mínimo de 8 caracteres.',
                  suffixIcon: IconButton(
                    key: const Key('acesso-app-ver-senha'),
                    tooltip: _ocultarSenha ? 'Mostrar senha' : 'Ocultar senha',
                    onPressed: _salvando
                        ? null
                        : () => setState(() => _ocultarSenha = !_ocultarSenha),
                    icon: Icon(
                      _ocultarSenha
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.length < 8
                    ? 'A senha deve ter pelo menos 8 caracteres.'
                    : null,
              ),
              if (_erro != null) ...[
                const SizedBox(height: 16),
                Text(
                  _erro!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
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
          key: const Key('criar-acesso-app'),
          onPressed: _salvando ? null : _salvar,
          icon: _salvando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.key_outlined),
          label: Text(_salvando ? 'Criando...' : 'Criar Acesso'),
        ),
      ],
    ),
  );
}
