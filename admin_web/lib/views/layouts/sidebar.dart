import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth_session.dart';
import '../../providers/auth_provider.dart';
import '../widgets/brand_logo.dart';
import '../widgets/theme_toggle_button.dart';

enum _UserMenuAction { profile, settings, logout }

class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({
    super.key,
    required this.currentPath,
    this.collapsible = true,
  });
  final String currentPath;
  final bool collapsible;

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  bool _isExpanded = true;
  final _userMenuController = MenuController();
  final _userMenuFocus = FocusNode(debugLabel: 'Opções do usuário');
  bool _userMenuOpen = false;

  @override
  void dispose() {
    _userMenuFocus.dispose();
    super.dispose();
  }

  void _navigate(String path) {
    _userMenuController.close();
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
    context.go(path);
  }

  Future<void> _userAction(_UserMenuAction action) async {
    final session = ref.read(authProvider).asData?.value;
    if (session == null) return;
    final scaffold = Scaffold.maybeOf(context);
    final pageContext = scaffold?.context ?? context;
    if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
    if (action == _UserMenuAction.logout) {
      await ref.read(authProvider.notifier).logout();
      return;
    }
    await showDialog<void>(
      context: pageContext,
      useRootNavigator: false,
      builder: (context) {
        final theme = Theme.of(context);
        final profile = action == _UserMenuAction.profile;
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          title: Text(profile ? 'Meu Perfil' : 'Configurações'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: profile
                    ? [
                        _ProfileDetail(label: 'Nome', value: session.user.name),
                        const SizedBox(height: 20),
                        _ProfileDetail(
                          label: 'E-mail',
                          value: session.user.email,
                        ),
                        const SizedBox(height: 20),
                        _ProfileDetail(
                          label: 'Perfil de acesso',
                          value: session.user.role.apiValue,
                        ),
                      ]
                    : [
                        Text('Aparência', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Tema do painel'),
                          subtitle: Text(
                            theme.brightness == Brightness.dark
                                ? 'Escuro'
                                : 'Claro',
                          ),
                          trailing: const ThemeToggleButton(),
                        ),
                      ],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null) return const SizedBox.shrink();
    final role = session.user.role;
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      key: const Key('sidebar-width'),
      width: !widget.collapsible || _isExpanded ? 280 : 76,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: colors.surface),
      child: Material(
        color: colors.surface,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Só monta os textos quando há espaço durante a expansão.
              final showLabels =
                  !widget.collapsible ||
                  (_isExpanded && constraints.maxWidth >= 240);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(showLabels),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      key: const PageStorageKey('admin-sidebar'),
                      padding: EdgeInsets.fromLTRB(
                        showLabels ? 16 : 10,
                        20,
                        showLabels ? 16 : 10,
                        16,
                      ),
                      children: [
                        if (showLabels)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 16,
                              bottom: 12,
                            ),
                            child: Text(
                              'NAVEGAÇÃO',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ),
                        _item(
                          'Dashboard',
                          '/dashboard',
                          Icons.dashboard_outlined,
                          showLabels,
                        ),
                        if (role == UserRole.superadmin)
                          _item(
                            'Empresas',
                            '/empresas',
                            Icons.business_outlined,
                            showLabels,
                          ),
                        if (role.canManageCompany) ...[
                          _item(
                            'Setores',
                            '/setores',
                            Icons.location_on_outlined,
                            showLabels,
                          ),
                          _item(
                            'Escalas',
                            '/escalas',
                            Icons.calendar_month_outlined,
                            showLabels,
                          ),
                          _item(
                            'Funcionários',
                            '/funcionarios',
                            Icons.people_outline,
                            showLabels,
                          ),
                          _item(
                            'Alocações',
                            '/alocacoes',
                            Icons.assignment_ind_outlined,
                            showLabels,
                          ),
                          _item(
                            'Relatórios',
                            '/relatorios',
                            Icons.assessment_outlined,
                            showLabels,
                          ),
                        ],
                        if (role == UserRole.rh || role == UserRole.gestor) ...[
                          _item(
                            'Equipe',
                            '/equipe',
                            Icons.groups_outlined,
                            showLabels,
                          ),
                          _item(
                            'Justificativas e ajustes',
                            '/justificativas',
                            Icons.fact_check_outlined,
                            showLabels,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  _userMenu(session, showLabels, constraints.maxWidth),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(bool showLabels) {
    final colors = Theme.of(context).colorScheme;
    final toggle = IconButton(
      key: const Key('sidebar-toggle'),
      tooltip: _isExpanded ? 'Recolher menu' : 'Expandir menu',
      onPressed: () {
        _userMenuController.close();
        setState(() => _isExpanded = !_isExpanded);
      },
      icon: Icon(_isExpanded ? Icons.chevron_left : Icons.chevron_right),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: showLabels ? 16 : 8,
        vertical: 20,
      ),
      child: Column(
        children: [
          if (showLabels) ...[
            Row(
              children: [
                const Expanded(child: BrandLogo(width: 184)),
                if (widget.collapsible) ...[const SizedBox(width: 8), toggle],
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Painel Administrativo',
                style: TextStyle(
                  color: colors.secondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .6,
                ),
              ),
            ),
          ] else ...[
            toggle,
            const SizedBox(height: 12),
            Image.asset(
              'assets/brand/ponto_aqui_symbol.png',
              width: 34,
              height: 40,
              fit: BoxFit.contain,
              semanticLabel: 'Ponto Aqui',
            ),
          ],
        ],
      ),
    );
  }

  Widget _item(String title, String path, IconData icon, bool showLabels) {
    final colors = Theme.of(context).colorScheme;
    final selected =
        widget.currentPath == path ||
        (path == '/empresas' && widget.currentPath == '/empresas/nova');
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        key: ValueKey('sidebar-item-$path'),
        color: selected ? colors.secondaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? colors.secondary.withValues(alpha: .18)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: showLabels
            ? ListTile(
                leading: Icon(icon, size: 21),
                title: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                selected: selected,
                selectedColor: colors.onSecondaryContainer,
                iconColor: colors.onSurfaceVariant,
                onTap: () => _navigate(path),
              )
            : Tooltip(
                message: title,
                child: Semantics(
                  label: title,
                  button: true,
                  selected: selected,
                  child: InkWell(
                    onTap: () => _navigate(path),
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: Icon(icon, size: 22, color: foreground),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _userMenu(AuthSession session, bool showLabels, double width) {
    final colors = Theme.of(context).colorScheme;
    final padding = showLabels ? 16.0 : 8.0;
    final menuWidth = (showLabels ? width - padding * 2 : 240.0).clamp(
      0.0,
      MediaQuery.sizeOf(context).width - 32,
    );
    final name = session.user.name.trim();
    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: colors.secondaryContainer,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: colors.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.all(padding),
      child: MenuAnchor(
        controller: _userMenuController,
        childFocusNode: _userMenuFocus,
        crossAxisUnconstrained: false,
        useRootOverlay: true,
        consumeOutsideTap: true,
        animated: true,
        alignmentOffset: const Offset(0, 8),
        onOpen: () => setState(() => _userMenuOpen = true),
        onClose: () {
          if (mounted) setState(() => _userMenuOpen = false);
        },
        style: MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          backgroundColor: WidgetStatePropertyAll(colors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(
            colors.shadow.withValues(alpha: .16),
          ),
          elevation: const WidgetStatePropertyAll(8),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          minimumSize: WidgetStatePropertyAll(Size(menuWidth, 0)),
          maximumSize: WidgetStatePropertyAll(Size(menuWidth, double.infinity)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.outlineVariant),
            ),
          ),
        ),
        menuChildren: [
          _userMenuItem(
            'Meu Perfil',
            Icons.person_outline,
            _UserMenuAction.profile,
          ),
          _userMenuItem(
            'Configurações',
            Icons.settings_outlined,
            _UserMenuAction.settings,
          ),
          Padding(
            key: const Key('sidebar-user-menu-divider'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Divider(height: 1, color: colors.outlineVariant),
          ),
          _userMenuItem(
            'Sair do Sistema',
            Icons.logout,
            _UserMenuAction.logout,
            destructive: true,
          ),
        ],
        builder: (context, controller, child) => Tooltip(
          message: 'Opções do usuário',
          child: Material(
            color: _userMenuOpen
                ? colors.secondaryContainer
                : colors.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: _userMenuOpen
                    ? colors.secondary.withValues(alpha: .3)
                    : Colors.transparent,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('sidebar-user-menu'),
              focusNode: _userMenuFocus,
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              child: Padding(
                padding: EdgeInsets.all(showLabels ? 12 : 10),
                child: showLabels
                    ? Row(
                        children: [
                          avatar,
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
                                  session.user.role.apiValue,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                                if (session.isMock)
                                  Text(
                                    'Sessão de teste',
                                    style: TextStyle(
                                      color: colors.tertiary,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedRotation(
                            turns: _userMenuOpen ? .5 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: Icon(
                              Icons.keyboard_arrow_up,
                              size: 20,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    : Center(child: avatar),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _userMenuItem(
    String title,
    IconData icon,
    _UserMenuAction action, {
    bool destructive = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive ? colors.error : colors.onSurface;
    return MenuItemButton(
      onPressed: () => _userAction(action),
      leadingIcon: Icon(icon, size: 18),
      style: MenuItemButton.styleFrom(
        foregroundColor: color,
        iconColor: destructive ? color : colors.onSurfaceVariant,
        overlayColor: destructive
            ? colors.error.withValues(alpha: .08)
            : colors.secondary.withValues(alpha: .08),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(title),
    );
  }
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 6),
      SelectableText(value),
    ],
  );
}
