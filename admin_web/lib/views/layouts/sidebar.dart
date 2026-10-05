import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth_session.dart';
import '../../providers/auth_provider.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, required this.currentPath});
  final String currentPath;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null) return const SizedBox.shrink();
    final role = session.user.role;
    Widget item(String title, String path, IconData icon) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      selected: currentPath == path,
      onTap: () {
        final scaffold = Scaffold.maybeOf(context);
        if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
        context.go(path);
      },
    );
    return SafeArea(
      child: ListView(
        key: const PageStorageKey('admin-sidebar'),
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Painel Administrativo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Text(session.user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(role.apiValue, style: Theme.of(context).textTheme.labelSmall),
          if (session.isMock) const Text('Sessão de teste'),
          const SizedBox(height: 16),
          item('Dashboard', '/dashboard', Icons.dashboard_outlined),
          if (role == UserRole.superadmin)
            item(
              'Cadastrar Empresa',
              '/empresas/nova',
              Icons.business_outlined,
            ),
          if (role.canManageCompany) ...[
            item('Setores', '/setores', Icons.location_on_outlined),
            item('Escalas', '/escalas', Icons.calendar_month_outlined),
            item('Funcionários', '/funcionarios', Icons.people_outline),
            item('Alocações', '/alocacoes', Icons.assignment_ind_outlined),
            item('Relatórios', '/relatorios', Icons.assessment_outlined),
          ],
          // Todos os perfis aceitos no painel podem acompanhar a equipe.
          if (role == UserRole.superadmin ||
              role == UserRole.rh ||
              role == UserRole.gestor) ...[
            item('Equipe', '/equipe', Icons.groups_outlined),
            item(
              'Justificativas e ajustes',
              '/justificativas',
              Icons.fact_check_outlined,
            ),
          ],
        ],
      ),
    );
  }
}
