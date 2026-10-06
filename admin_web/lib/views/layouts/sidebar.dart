import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth_session.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, required this.currentPath});
  final String currentPath;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null) return const SizedBox.shrink();
    final role = session.user.role;
    Widget item(String title, String path, IconData icon) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(icon, size: 21),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        selected:
            currentPath == path ||
            (path == '/empresas' && currentPath == '/empresas/nova'),
        onTap: () {
          final scaffold = Scaffold.maybeOf(context);
          if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
          context.go(path);
        },
      ),
    );
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                children: [
                  BrandLogo(),
                  SizedBox(height: 6),
                  Text(
                    'Painel Administrativo',
                    style: TextStyle(
                      color: BrandColors.muted,
                      fontSize: 12,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                key: const PageStorageKey('admin-sidebar'),
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 16, bottom: 12),
                    child: Text(
                      'NAVEGAÇÃO',
                      style: TextStyle(
                        color: BrandColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  item('Dashboard', '/dashboard', Icons.dashboard_outlined),
                  if (role == UserRole.superadmin)
                    item('Empresas', '/empresas', Icons.business_outlined),
                  if (role.canManageCompany) ...[
                    item('Setores', '/setores', Icons.location_on_outlined),
                    item('Escalas', '/escalas', Icons.calendar_month_outlined),
                    item('Funcionários', '/funcionarios', Icons.people_outline),
                    item(
                      'Alocações',
                      '/alocacoes',
                      Icons.assignment_ind_outlined,
                    ),
                    item(
                      'Relatórios',
                      '/relatorios',
                      Icons.assessment_outlined,
                    ),
                  ],
                  if (role == UserRole.rh || role == UserRole.gestor) ...[
                    item('Equipe', '/equipe', Icons.groups_outlined),
                    item(
                      'Justificativas e ajustes',
                      '/justificativas',
                      Icons.fact_check_outlined,
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: BrandColors.mint,
                    child: Text(
                      session.user.name.trim().isEmpty
                          ? '?'
                          : session.user.name
                                .trim()
                                .characters
                                .first
                                .toUpperCase(),
                      style: const TextStyle(
                        color: BrandColors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          role.apiValue,
                          style: const TextStyle(
                            color: BrandColors.muted,
                            fontSize: 11,
                          ),
                        ),
                        if (session.isMock)
                          const Text(
                            'Sessão de teste',
                            style: TextStyle(
                              color: BrandColors.warning,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
