class Empresa {
  const Empresa({
    required this.id,
    required this.razaoSocial,
    required this.cnpj,
    required this.adminEmail,
    this.adminNome = '',
    this.ativa = true,
  });

  final String id;
  final String razaoSocial;
  final String cnpj;
  final String adminEmail;
  final String adminNome;
  final bool ativa;

  factory Empresa.fromJson(Map<String, dynamic> json) => Empresa(
    id: json['id'] as String,
    razaoSocial: json['razao_social'] as String,
    cnpj: json['cnpj'] as String,
    adminEmail: json['admin_email'] as String? ?? '',
    adminNome: json['admin_nome'] as String? ?? '',
    ativa: json['ativo'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'razao_social': razaoSocial,
    'cnpj': cnpj,
    'admin_email': adminEmail,
    'admin_nome': adminNome,
    'ativo': ativa,
  };

  String get cnpjFormatado => cnpj.length != 14
      ? cnpj
      : '${cnpj.substring(0, 2)}.${cnpj.substring(2, 5)}.${cnpj.substring(5, 8)}/'
            '${cnpj.substring(8, 12)}-${cnpj.substring(12)}';
}
