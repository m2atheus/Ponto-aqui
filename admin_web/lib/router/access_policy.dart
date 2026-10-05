import '../models/auth_session.dart';

class AccessPolicy {
  static const modules = <String, String>{
    '/empresas/nova': 'Cadastrar Empresa',
    '/setores': 'Setores',
    '/escalas': 'Escalas',
    '/funcionarios': 'Funcionários',
    '/alocacoes': 'Alocações',
    '/relatorios': 'Relatórios',
    '/equipe': 'Equipe',
    '/justificativas': 'Justificativas e ajustes',
  };
  static bool allows(UserRole role, String path) {
    if (path == '/empresas/nova') return role == UserRole.superadmin;
    if ({
      '/setores',
      '/escalas',
      '/funcionarios',
      '/alocacoes',
      '/relatorios',
    }.contains(path)) {
      return role.canManageCompany;
    }
    return true;
  }

  static String loginDestination(String? from) {
    final uri = from == null ? null : Uri.tryParse(from);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        !(uri.path == '/dashboard' || modules.containsKey(uri.path))) {
      return '/dashboard';
    }
    return uri.toString();
  }
}
