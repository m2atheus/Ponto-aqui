import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/management_mock_provider.dart';
import '../../providers/empresas_provider.dart';
import '../../theme/app_theme.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null) return const SizedBox.shrink();
    final List<Widget> cards;
    switch (session.user.role) {
      case UserRole.superadmin:
        cards = [
          _ResumoCard(
            titulo: 'Total de Empresas Cadastradas',
            valor: ref.watch(empresasProvider).asData?.value.length,
            icone: Icons.business_outlined,
            acao: FilledButton.icon(
              onPressed: () => context.go('/empresas/nova'),
              icon: const Icon(Icons.add),
              label: const Text('Cadastrar Empresa'),
            ),
          ),
        ];
      case UserRole.rh:
        const totalFuncionarios = 42;
        const totalSetores = 6;
        final escalasAtivas = ref
            .watch(escalasMockProvider)
            .where((escala) => escala.ativa)
            .length;
        cards = [
          const _ResumoCard(
            titulo: 'Total de Funcionários',
            valor: totalFuncionarios,
            icone: Icons.people_outline,
          ),
          const _ResumoCard(
            titulo: 'Total de Setores',
            valor: totalSetores,
            icone: Icons.location_on_outlined,
          ),
          _ResumoCard(
            titulo: 'Escalas Ativas',
            valor: escalasAtivas,
            icone: Icons.calendar_month_outlined,
          ),
        ];
      case UserRole.gestor:
        const justificativasPendentes = 5;
        cards = [
          const _ResumoCard(
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
        alignment: Alignment.topLeft,
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
                    : 'Dados de demonstração.',
                style: const TextStyle(color: BrandColors.muted, fontSize: 12),
              ),
              if (session.user.role == UserRole.superadmin &&
                  ref.watch(empresasProvider).hasError)
                Text(
                  ref.watch(empresasProvider).error.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = math.min(340.0, constraints.maxWidth);
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: BrandColors.navy,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      color: Color(0xFF77DED4),
                      size: 32,
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Olá, ${session.user.name.split(' ').first}.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Acompanhe sua operação pelo menu ao lado.',
                          style: TextStyle(
                            color: Color(0xFFC5DEE7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
              color: alerta ? BrandColors.warningSurface : BrandColors.mint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icone,
              size: 24,
              color: alerta ? BrandColors.warning : BrandColors.teal,
            ),
          ),
          const SizedBox(height: 16),
          Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            valor == null ? '—' : '$valor',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: alerta ? BrandColors.warning : BrandColors.navy,
            ),
          ),
          if (acao != null) ...[const SizedBox(height: 20), acao!],
        ],
      ),
    ),
  );
}
