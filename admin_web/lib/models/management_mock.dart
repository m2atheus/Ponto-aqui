class EmpresaMock {
  const EmpresaMock({
    required this.id,
    required this.razaoSocial,
    required this.cnpj,
    required this.adminEmail,
    this.ativa = true,
  });
  final String id;
  final String razaoSocial;
  final String cnpj;
  final String adminEmail;
  final bool ativa;
  EmpresaMock copyWith({String? id, bool? ativa}) => EmpresaMock(
    id: id ?? this.id,
    razaoSocial: razaoSocial,
    cnpj: cnpj,
    adminEmail: adminEmail,
    ativa: ativa ?? this.ativa,
  );
  String get cnpjFormatado =>
      '${cnpj.substring(0, 2)}.${cnpj.substring(2, 5)}.${cnpj.substring(5, 8)}/'
      '${cnpj.substring(8, 12)}-${cnpj.substring(12)}';
}

class EscalaMock {
  EscalaMock({
    required this.id,
    required this.empresaId,
    required this.nome,
    required this.entradaMinutos,
    required this.saidaMinutos,
    required Set<int> diasSemana,
    this.ativa = true,
  }) : diasSemana = Set.unmodifiable(diasSemana);
  final String id;
  final String empresaId;
  final String nome;
  final int entradaMinutos;
  final int saidaMinutos;
  final Set<int> diasSemana;
  final bool ativa;
  bool get terminaNoDiaSeguinte => saidaMinutos < entradaMinutos;
  EscalaMock withId(String value) => EscalaMock(
    id: value,
    empresaId: empresaId,
    nome: nome,
    entradaMinutos: entradaMinutos,
    saidaMinutos: saidaMinutos,
    diasSemana: diasSemana,
    ativa: ativa,
  );
  static const dias = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  String get diasFormatados =>
      (diasSemana.toList()..sort()).map((dia) => dias[dia - 1]).join(', ');
  static String formatarHorario(int minutos) =>
      '${(minutos ~/ 60).toString().padLeft(2, '0')}:${(minutos % 60).toString().padLeft(2, '0')}';
  static int? lerHorario(String texto) {
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(texto.trim())) {
      return null;
    }
    final partes = texto.trim().split(':');
    return int.parse(partes[0]) * 60 + int.parse(partes[1]);
  }
}
