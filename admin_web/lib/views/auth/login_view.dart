import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});
  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (ref.read(authProvider).isLoading ||
        !_formKey.currentState!.validate()) {
      return;
    }
    ref.read(authProvider.notifier).login(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final mockEnabled = ref.watch(mockAuthEnabledProvider);
    final form = Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: BrandLogo(width: 280),
                ),
                const SizedBox(height: 24),
                Text(
                  'Bem-vindo de volta',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text('Entre no painel administrativo.'),
                const SizedBox(height: 32),
                TextFormField(
                  key: const Key('login-email'),
                  controller: _email,
                  enabled: !auth.isLoading,
                  autofillHints: const [AutofillHints.username],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (value) =>
                      value == null ||
                          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(value.trim())
                      ? 'Informe um e-mail válido.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('login-password'),
                  controller: _password,
                  enabled: !auth.isLoading,
                  obscureText: _hidePassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _hidePassword
                          ? 'Mostrar senha'
                          : 'Ocultar senha',
                      onPressed: () =>
                          setState(() => _hidePassword = !_hidePassword),
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Informe a senha.'
                      : null,
                ),
                if (auth.hasError) ...[
                  const SizedBox(height: 16),
                  Text(
                    auth.error is AuthFailure
                        ? (auth.error as AuthFailure).message
                        : 'Não foi possível iniciar a sessão.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: auth.isLoading ? null : _submit,
                  child: auth.isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : const Text('Entrar'),
                ),
                if (mockEnabled) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Acessos de teste: admin@teste.com, rh@teste.com ou gestor@teste.com\nSenha: admin',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 48 : 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 1100 : 480),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Expanded(child: _LoginPresentation()),
                          const SizedBox(width: 64),
                          SizedBox(width: 440, child: form),
                        ],
                      )
                    : form,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoginPresentation extends StatelessWidget {
  const _LoginPresentation();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(40),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [BrandColors.navy, Color(0xFF144B67)],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Image.asset(
            'assets/brand/ponto_aqui_symbol.png',
            width: 64,
            height: 64,
            semanticLabel: 'Símbolo Ponto Aqui',
          ),
        ),
        const SizedBox(height: 40),
        const Text(
          'CONTROLE DE PONTO',
          style: TextStyle(
            color: Color(0xFF77DED4),
            letterSpacing: 2,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Sua equipe.\nSeu tempo.\nTudo no lugar.',
          style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(color: Colors.white, fontSize: 40, height: 1.2),
        ),
        const SizedBox(height: 20),
        const Text(
          'Organize a jornada de trabalho com uma visão clara da sua operação.',
          style: TextStyle(color: Color(0xFFC5DEE7), height: 1.6, fontSize: 15),
        ),
        const SizedBox(height: 32),
        for (final feature in [
          (Icons.schedule_outlined, 'Ponto e jornada'),
          (Icons.groups_outlined, 'Equipes e escalas'),
          (Icons.business_outlined, 'Gestão por empresa'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Icon(feature.$1, size: 20, color: const Color(0xFF77DED4)),
                const SizedBox(width: 12),
                Text(
                  feature.$2,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
