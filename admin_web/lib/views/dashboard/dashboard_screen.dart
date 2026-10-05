import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/management_mock_provider.dart';

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
            valor: ref.watch(empresasMockProvider).length,
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
              const Text(
                'Dados de demonstração.',
                style: TextStyle(color: Colors.grey),
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
  final int valor;
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
          Icon(icone),
          const SizedBox(height: 16),
          Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('$valor', style: Theme.of(context).textTheme.displaySmall),
          if (acao != null) ...[const SizedBox(height: 20), acao!],
        ],
      ),
    ),
  );
}
