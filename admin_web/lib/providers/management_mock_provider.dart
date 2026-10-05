import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/management_mock.dart';
import 'auth_provider.dart';

final escalasMockProvider =
    NotifierProvider<EscalasMockController, List<EscalaMock>>(
      EscalasMockController.new,
    );

class EscalasMockController extends Notifier<List<EscalaMock>> {
  int _nextId = 3;
  @override
  List<EscalaMock> build() {
    final user = ref.watch(authProvider).asData?.value?.user;
    _nextId = 3;
    if (user?.role != UserRole.rh || user?.companyId == null) return const [];
    final empresaId = user!.companyId!;
    return List.unmodifiable([
      EscalaMock(
        id: 'escala-1',
        empresaId: empresaId,
        nome: 'Comercial',
        entradaMinutos: 480,
        saidaMinutos: 1020,
        diasSemana: {1, 2, 3, 4, 5},
      ),
      EscalaMock(
        id: 'escala-2',
        empresaId: empresaId,
        nome: 'Sábado',
        entradaMinutos: 480,
        saidaMinutos: 720,
        diasSemana: {6},
      ),
    ]);
  }

  void _verificarEmpresa(String empresaId) {
    final user = ref.read(authProvider).asData?.value?.user;
    if (user?.role != UserRole.rh || user?.companyId != empresaId) {
      throw StateError('Escala fora do contexto da empresa autenticada.');
    }
  }

  void salvar(EscalaMock escala) {
    _verificarEmpresa(escala.empresaId);
    if (state.any(
      (item) =>
          item.id != escala.id &&
          item.nome.toLowerCase() == escala.nome.toLowerCase(),
    )) {
      throw StateError('Nome de escala já cadastrado.');
    }
    if (escala.id.isEmpty) {
      state = List.unmodifiable([
        ...state,
        escala.withId('escala-${_nextId++}'),
      ]);
    } else {
      state = List.unmodifiable([
        for (final item in state)
          if (item.id == escala.id) escala else item,
      ]);
    }
  }

  void remover(EscalaMock escala) {
    _verificarEmpresa(escala.empresaId);
    state = List.unmodifiable(state.where((item) => item.id != escala.id));
  }
}
