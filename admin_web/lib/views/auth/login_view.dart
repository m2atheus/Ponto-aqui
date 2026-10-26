import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/theme_toggle_button.dart';

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
    final colors = Theme.of(context).colorScheme;
    final form = Card(
      key: const Key('login-form-card'),
      elevation: 20,
      shadowColor: const Color(0xFF031E33).withValues(alpha: 0.22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 34),
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: BrandLogo(width: 210),
                ),
                const SizedBox(height: 28),
                Text(
                  'Bem-vindo de volta',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Entre no painel administrativo.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 28),
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
                  style: FilledButton.styleFrom(
                    elevation: 4,
                    shadowColor: BrandColors.navy.withValues(alpha: 0.3),
                  ),
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
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Entrar'),
                            SizedBox(width: 10),
                            Icon(Icons.login_rounded, size: 17),
                          ],
                        ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Precisa de acesso ou esqueceu sua senha?\nEntre em contato com o RH da sua empresa.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.7,
                    color: colors.onSurfaceVariant,
                  ),
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
      body: BrandBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 48 : 20,
                        vertical: 60,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 120).clamp(
                            0.0,
                            double.infinity,
                          ),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: wide ? 940 : 440,
                            ),
                            child: wide
                                ? Stack(
                                    children: [
                                      Positioned(
                                        left: 380,
                                        right: 0,
                                        top: 36,
                                        bottom: 36,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: colors.surface.withValues(
                                              alpha: 0.82,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              22,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.1,
                                                ),
                                                blurRadius: 40,
                                                offset: const Offset(0, 24),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Both panels contribute their natural height.
                                      // A positioned presentation used only the form's
                                      // height and overflowed with different font metrics.
                                      IntrinsicHeight(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            const SizedBox(
                                              width: 440,
                                              child: _LoginPresentation(),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      0,
                                                      68,
                                                      24,
                                                      68,
                                                    ),
                                                child: Align(
                                                  alignment: Alignment.center,
                                                  child: form,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: BrandColors.navy,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: const Text(
                                          'Sua equipe. Seu tempo. Tudo no lugar.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 18,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      form,
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 10,
                    right: 16,
                    child: ThemeToggleButton(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoginPresentation extends StatelessWidget {
  const _LoginPresentation();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('login-presentation'),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF041C32).withValues(alpha: 0.3),
          blurRadius: 36,
          offset: const Offset(0, 20),
        ),
      ],
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF073251), Color(0xFF0B2A47), Color(0xFF176274)],
      ),
    ),
    child: Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _PanelWaves())),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(36, 28, 36, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(
                child: BrandLogo(width: 180, brightness: Brightness.dark),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Image.asset(
                  'assets/brand/ponto_aqui_symbol.png',
                  width: 30,
                  height: 30,
                  semanticLabel: 'Símbolo Ponto Aqui',
                ),
              ),
              const SizedBox(height: 24),
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
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1.15,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Organize a jornada de trabalho com uma visão clara da sua operação.',
                style: TextStyle(
                  color: Color(0xFFC5DEE7),
                  height: 1.6,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              for (final feature in [
                (Icons.schedule_outlined, 'Ponto e jornada'),
                (Icons.groups_outlined, 'Equipes e escalas'),
                (Icons.business_outlined, 'Gestão por empresa'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(
                        feature.$1,
                        size: 20,
                        color: const Color(0xFF77DED4),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          feature.$2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              const Align(
                alignment: Alignment.centerRight,
                child: SizedBox(height: 100, child: BrandJourneyArt()),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PanelWaves extends CustomPainter {
  const _PanelWaves();

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 4; i++) {
      final y = size.height * (0.38 + i * 0.15);
      final path = Path()
        ..moveTo(0, y)
        ..cubicTo(
          size.width * 0.35,
          y + 70,
          size.width * 0.6,
          y - 100,
          size.width,
          y - 50,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = const Color(0xFF5FC7BA).withValues(alpha: 0.035),
      );
    }
  }

  @override
  bool shouldRepaint(_PanelWaves oldDelegate) => false;
}
