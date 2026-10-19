import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/capture.dart';
import '../../../core/clock/clock_service.dart';
import '../domain/mark.dart';
import 'mark_view_model.dart';

class MarkHome extends ConsumerWidget {
  const MarkHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(employeeContextProvider);
    if (employee == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Primeiro acesso requer internet, autenticação e aparelho previamente '
                'cadastrado. Integração W07/W08 ainda pendente.\n\n'
                'Para demonstração em desenvolvimento, use PONTO_AQUI_DEMO=true.',
              ),
            ),
          ),
        ),
      );
    }
    final repository = ref.watch(repositoryProvider);
    final clockService = ref.watch(clockServiceProvider(employee));
    final service = clockService.asData?.value;
    if (clockService.hasError) {
      return const Scaffold(
        body: Center(child: Text('Não foi possível abrir o banco local.')),
      );
    }
    if (service == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    ref.watch(connectivityProvider);
    return repository.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, s) => Scaffold(
        body: Center(child: Text('Não foi possível abrir o banco local: $e')),
      ),
      data: (value) => MarkScreen(
        key: ValueKey((employee, service)),
        repository: value,
        employee: employee,
        clockService: service,
        offline: () {
          final current = ref.read(connectivityProvider).asData?.value;
          return current?.contains(ConnectivityResult.none);
        },
      ),
    );
  }
}

class MarkScreen extends StatefulWidget {
  const MarkScreen({
    super.key,
    required this.repository,
    required this.employee,
    required this.offline,
    this.clock,
    this.clockService,
    this.suspiciousWindow = const Duration(seconds: 30),
  });
  final MarkRepository repository;
  final EmployeeContext employee;
  final bool? Function() offline;
  final Clock? clock;
  final ClockService? clockService;
  final Duration suspiciousWindow;
  @override
  State<MarkScreen> createState() => _MarkScreenState();
}

class _MarkScreenState extends State<MarkScreen> with WidgetsBindingObserver {
  late final MarkViewModel vm;
  Timer? timer;
  Timer? previewTimer;
  bool dialogOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vm = MarkViewModel(
      repository: widget.repository,
      context: widget.employee,
      clock: widget.clockService?.clock ?? widget.clock ?? DeviceClock(),
      clockService: widget.clockService,
      offline: widget.offline,
      suspiciousWindow: widget.suspiciousWindow,
    )..addListener(changed);
    vm.load();
    startPreview();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      startPreview();
      vm.load();
    } else {
      previewTimer?.cancel();
      timer?.cancel();
      vm.clockService.invalidateContinuity();
      vm.refreshTime();
    }
  }

  void startPreview() {
    previewTimer?.cancel();
    previewTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => vm.refreshTime(),
    );
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!vm.busy && vm.confirmation == null) vm.load();
    });
  }

  void changed() {
    if (!mounted) return;
    setState(() {});
    if (vm.confirmation != null && !dialogOpen) {
      dialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final request = vm.confirmation!;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirmar ponto consecutivo'),
            content: Text(
              'Você registrou ${request.previous.type.label.toLowerCase()} há pouco tempo. '
              'Deseja registrar ${request.next.label.toLowerCase()} agora?\n\n'
              'Horário capturado: ${vm.confirmationOccurredIso}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        dialogOpen = false;
        await vm.confirm(accepted == true);
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    previewTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    vm.removeListener(changed);
    vm.clockService.invalidateContinuity('screen_detached');
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = vm.day;
    final date = day == null
        ? '—'
        : '${day.substring(8, 10)}/${day.substring(5, 7)}/${day.substring(0, 4)}';
    return Scaffold(
      appBar: AppBar(title: const Text('Ponto-aqui')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Image.asset(
                  'assets/brand/ponto_aqui_symbol.png',
                  height: 64,
                  semanticLabel: 'Ponto-aqui',
                ),
                const SizedBox(height: 16),
                Text(
                  widget.employee.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (widget.employee.isDemo)
                  const Text('AMBIENTE DE TESTE • dados fictícios • sem envio'),
                const SizedBox(height: 12),
                Text('Jornada de $date • ${widget.employee.zone}'),
                const Text('Horários exibidos como capturados no aparelho.'),
                const SizedBox(height: 24),
                for (final type in MarkType.values)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        vm.marks.any((m) => m.type == type)
                            ? Icons.check_circle
                            : vm.next == type
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(type.label),
                      subtitle: Text(
                        vm.marks
                                .where((m) => m.type == type)
                                .firstOrNull
                                ?.originalTime ??
                            (vm.next == type
                                ? 'Próxima marcação'
                                : 'Aguardando'),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                if (vm.ready && vm.next == null)
                  const Text('Todas as etapas previstas foram concluídas.'),
                Text(
                  'Hora do aparelho: ${explicitIso(vm.preview.wall).substring(11, 19)}',
                  key: const Key('device-time-preview'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Text(
                  'Este é o relógio usado na captura. O horário definitivo é salvo no toque.',
                ),
                if (vm.timeState.estimate != null)
                  Text(
                    'Desvio estimado: ${vm.timeState.estimate!.seconds} s '
                    '(servidor − aparelho; estimativa com latência).',
                  ),
                if (vm.timeState.estimate != null &&
                    widget.employee.clockLimitSeconds == null)
                  const Text(
                    'Limite de desvio da empresa ainda não disponível.',
                  ),
                if (vm.clockWarning != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        vm.clockWarning!,
                        key: const Key('clock-warning'),
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed:
                      !vm.busy &&
                          vm.ready &&
                          vm.next != null &&
                          vm.confirmation == null
                      ? vm.register
                      : null,
                  icon: const Icon(Icons.touch_app),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      vm.busy
                          ? 'Salvando…'
                          : 'Registrar ${vm.next?.label.toLowerCase() ?? "ponto"}',
                    ),
                  ),
                ),
                if (vm.message != null)
                  Semantics(liveRegion: true, child: Text(vm.message!)),
                if (vm.error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      vm.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (!vm.ready && !vm.busy)
                  TextButton(
                    onPressed: vm.load,
                    child: const Text('Tentar novamente'),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Os pontos ficam salvos neste aparelho. Envio ao servidor ainda não implementado.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
