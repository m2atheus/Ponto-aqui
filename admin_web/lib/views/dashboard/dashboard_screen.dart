import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/smart_polling.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver, SmartPolling<DashboardScreen> {
  @override
  Future<void> refreshForPolling(CancelToken cancelToken) =>
      ref.read(dashboardProvider.notifier).refreshSilently(cancelToken);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null) return const SizedBox.shrink();
    final dados = ref.watch(dashboardProvider);
    final indicadores = dados.asData?.value;
    final List<Widget> cards;
    switch (session.user.role) {
      case UserRole.superadmin:
        cards = [
          _ResumoCard(
            titulo: 'Total de Empresas Cadastradas',
            valor: indicadores?['empresas'],
            icone: Icons.business_outlined,
            acao: FilledButton.icon(
              onPressed: () => context.go('/empresas/nova'),
              icon: const Icon(Icons.add),
              label: const Text('Cadastrar Empresa'),
            ),
          ),
        ];
      case UserRole.rh:
        cards = [
          _ResumoCard(
            titulo: 'Total de Funcionários',
            valor: indicadores?['funcionarios'],
            icone: Icons.people_outline,
          ),
          _ResumoCard(
            titulo: 'Total de Setores',
            valor: indicadores?['setores'],
            icone: Icons.location_on_outlined,
          ),
          _ResumoCard(
            titulo: 'Escalas Ativas',
            valor: indicadores?['escalas_ativas'],
            icone: Icons.calendar_month_outlined,
          ),
        ];
      case UserRole.gestor:
        final justificativasPendentes =
            indicadores?['justificativas_pendentes'];
        cards = [
          _ResumoCard(
            titulo: 'Justificativas Pendentes de Aprovação',
            valor: justificativasPendentes,
            icone: Icons.pending_actions,
            alerta: true,
          ),
        ];
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Visão geral de ponto e jornada.'),
              const SizedBox(height: 8),
              Text(
                session.user.role == UserRole.superadmin
                    ? 'Total de empresas consultado no banco.'
                    : 'Indicadores consultados no banco.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (dados.hasError && !dados.hasValue)
                Text(
                  dados.error.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 24),
              _DashboardWelcome(name: session.user.name),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  final columns = availableWidth < 600
                      ? 1
                      : availableWidth < 1000
                      ? 2
                      : 3;
                  final width = (availableWidth - (columns - 1) * 16) / columns;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final card in cards)
                        SizedBox(width: width, child: card),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              Text(
                'Acesso rápido',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (session.user.role == UserRole.superadmin)
                    OutlinedButton.icon(
                      onPressed: () => context.go('/empresas'),
                      icon: const Icon(Icons.business_outlined, size: 18),
                      label: const Text('Gerenciar empresas'),
                    ),
                  if (session.user.role.canManageCompany) ...[
                    OutlinedButton.icon(
                      onPressed: () => context.go('/funcionarios'),
                      icon: const Icon(Icons.people_outline, size: 18),
                      label: const Text('Gerenciar funcionários'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/relatorios'),
                      icon: const Icon(Icons.assessment_outlined, size: 18),
                      label: const Text('Consultar relatórios'),
                    ),
                  ],
                  if (session.user.role == UserRole.rh ||
                      session.user.role == UserRole.gestor)
                    OutlinedButton.icon(
                      onPressed: () => context.go('/equipe'),
                      icon: const Icon(Icons.groups_outlined, size: 18),
                      label: const Text('Acompanhar equipe'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardWelcome extends StatelessWidget {
  const _DashboardWelcome({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [BrandColors.navy, Color(0xFF124A63), Color(0xFF176E73)],
        ),
      ),
      padding: const EdgeInsets.all(28),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SUA OPERAÇÃO, EM SINTONIA',
                  style: TextStyle(
                    color: Color(0xFF8FE2D6),
                    fontSize: 10,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Olá, ${name.trim().split(' ').first}.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sua equipe. Seu tempo. Tudo no lugar.',
                  style: TextStyle(
                    color: Color(0xFFD1E8EB),
                    height: 1.6,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (constraints.maxWidth >= 650) ...[
            const SizedBox(width: 28),
            const BrandJourneyArt(),
          ],
        ],
      ),
    ),
  );
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
    required this.titulo,
    required this.valor,
    required this.icone,
    this.acao,
    this.alerta = false,
  });
  final String titulo;
  final int? valor;
  final IconData icone;
  final Widget? acao;
  final bool alerta;
  @override
  Widget build(BuildContext context) => Card(
    color: alerta ? Theme.of(context).colorScheme.tertiaryContainer : null,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: alerta
                  ? Theme.of(context).colorScheme.tertiaryContainer
                  : Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icone,
              size: 24,
              color: alerta
                  ? Theme.of(context).colorScheme.onTertiaryContainer
                  : Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            titulo,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            valor == null ? '—' : '$valor',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: alerta
                  ? Theme.of(context).colorScheme.onTertiaryContainer
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          if (acao != null) ...[const SizedBox(height: 20), acao!],
        ],
      ),
    ),
  );
}
