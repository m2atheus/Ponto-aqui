import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/responsive_table_container.dart';

import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/auth_session.dart';
import '../../models/setor.dart';
import '../../providers/auth_provider.dart';
import '../../providers/setores_provider.dart';
import '../../repositories/repository_failure.dart';
import '../modules/module_placeholder_view.dart';

class SetoresScreen extends ConsumerStatefulWidget {
  const SetoresScreen({super.key});
  @override
  ConsumerState<SetoresScreen> createState() => _SetoresScreenState();
}

class _SetoresScreenState extends ConsumerState<SetoresScreen> {
  final _scroll = ScrollController();
  bool _ocupado = false;
  String? _removendo;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _formulario([Setor? setor]) async {
    final session = ref.read(authProvider).asData?.value;
    if (_ocupado ||
        session == null ||
        session.isMock ||
        session.user.role != UserRole.rh) {
      return;
    }
    setState(() => _ocupado = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => _SetorDialog(
          setor: setor,
          empresaId: session.user.companyId!,
          sessionToken: session.accessToken,
        ),
      );
      if (mounted &&
          saved == true &&
          ref.read(authProvider).asData?.value?.accessToken ==
              session.accessToken) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Setor salvo com sucesso.')),
        );
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _remover(Setor setor) async {
    final session = ref.read(authProvider).asData?.value;
    if (_ocupado || session == null || session.isMock) return;
    setState(() => _ocupado = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('Remover setor?'),
          content: Text(
            'Deseja remover ${setor.nome}? Setores com alocações não podem ser removidos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remover'),
            ),
          ],
        ),
      );
      if (!mounted ||
          confirmed != true ||
          ref.read(authProvider).asData?.value?.accessToken !=
              session.accessToken) {
        return;
      }
      setState(() => _removendo = setor.id);
      await ref.read(setoresProvider.notifier).remover(setor);
      if (mounted &&
          ref.read(authProvider).asData?.value?.accessToken ==
              session.accessToken) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Setor removido.')));
      }
    } on RepositoryFailure catch (error) {
      if (mounted &&
          ref.read(authProvider).asData?.value?.accessToken ==
              session.accessToken) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(
              error.message,
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _removendo = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider).asData?.value;
    if (session?.user.role != UserRole.rh || session?.user.companyId == null) {
      return const ModulePlaceholderView(
        title: 'Acesso negado',
        message: 'Esta área é exclusiva do RH da empresa.',
      );
    }
    final dados = ref.watch(setoresProvider);
    final enabled =
        !session!.isMock && !dados.isLoading && !dados.hasError && !_ocupado;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Setores',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              FilledButton.icon(
                key: const Key('novo-setor'),
                onPressed: enabled ? _formulario : null,
                icon: const Icon(Icons.add),
                label: const Text('Novo Setor'),
              ),
              IconButton(
                tooltip: 'Atualizar setores',
                onPressed: !session.isMock && !dados.isLoading && !_ocupado
                    ? () => ref.invalidate(setoresProvider)
                    : null,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Defina os locais de trabalho, o perímetro e as políticas de ponto.',
          ),
          const SizedBox(height: 24),
          if (dados.isLoading || _removendo != null)
            const LinearProgressIndicator(),
          if (dados.hasError)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dados.error is RepositoryFailure
                          ? (dados.error as RepositoryFailure).message
                          : 'Não foi possível carregar os setores.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: !session.isMock && !_ocupado
                          ? () => ref.invalidate(setoresProvider)
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          if (dados.asData?.value case final rows?) ...[
            if (rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhum setor cadastrado.'),
                ),
              )
            else
              Card(
                child: ResponsiveTableContainer(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DataTable(
                    dataRowMinHeight: 72,
                    dataRowMaxHeight: 120,
                    columns: const [
                      DataColumn(label: Text('Nome')),
                      DataColumn(label: Text('Endereço')),
                      DataColumn(label: Text('Raio')),
                      DataColumn(label: Text('Políticas')),
                      DataColumn(label: Text('Ações')),
                    ],
                    rows: [
                      for (final setor in rows)
                        DataRow(
                          key: ValueKey(setor.id),
                          cells: [
                            DataCell(Text(setor.nome)),
                            DataCell(
                              SizedBox(
                                width: 240,
                                child: Text(
                                  setor.endereco?.isNotEmpty == true
                                      ? setor.endereco!
                                      : '—',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                setor.raioMetros == null
                                    ? '—'
                                    : '${setor.raioMetros!.toStringAsFixed(2)} m',
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 250,
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (setor.exigeSelfie)
                                      const Chip(label: Text('Selfie')),
                                    Chip(
                                      label: Text(
                                        setor.ignorarLocalizacao
                                            ? 'Localização dispensada'
                                            : setor.acaoForaPerimetro ==
                                                  'PENDENTE'
                                            ? 'Fora: pendente'
                                            : 'Fora: bloquear',
                                      ),
                                    ),
                                    if (!setor.ativo)
                                      const Chip(label: Text('Inativo')),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: Key('editar-setor-${setor.id}'),
                                    tooltip: setor.possuiPerimetro
                                        ? 'Editar setor'
                                        : 'Detalhes indisponíveis',
                                    onPressed: enabled && setor.possuiPerimetro
                                        ? () => _formulario(setor)
                                        : null,
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    key: Key('remover-setor-${setor.id}'),
                                    tooltip: 'Remover setor',
                                    onPressed: enabled
                                        ? () => _remover(setor)
                                        : null,
                                    icon: _removendo == setor.id
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SetorDialog extends ConsumerStatefulWidget {
  const _SetorDialog({
    this.setor,
    required this.empresaId,
    required this.sessionToken,
  });
  final Setor? setor;
  final String empresaId;
  final String sessionToken;
  @override
  ConsumerState<_SetorDialog> createState() => _SetorDialogState();
}

class _SetorDialogState extends ConsumerState<_SetorDialog> {
  final _form = GlobalKey<FormState>();
  final _map = MapController();
  late final TileProvider _tiles;
  late final TextEditingController _nome,
      _endereco,
      _latitude,
      _longitude,
      _raioInput;
  LatLng? _ponto;
  late double _raio;
  late bool _selfie, _ignorar;
  late String _acao;
  bool _salvando = false, _mapReady = false, _tilesFalharam = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final setor = widget.setor;
    _nome = TextEditingController(text: setor?.nome ?? '');
    _endereco = TextEditingController(text: setor?.endereco ?? '');
    _latitude = TextEditingController(
      text: setor?.latitude?.toStringAsFixed(7) ?? '',
    );
    _longitude = TextEditingController(
      text: setor?.longitude?.toStringAsFixed(7) ?? '',
    );
    _raio = setor?.raioMetros ?? 100;
    _raioInput = TextEditingController(text: _raio.toStringAsFixed(2));
    if (setor?.possuiPerimetro == true) {
      _ponto = LatLng(setor!.latitude!, setor.longitude!);
    }
    _selfie = setor?.exigeSelfie ?? false;
    _ignorar = setor?.ignorarLocalizacao ?? false;
    _acao = setor?.acaoForaPerimetro ?? 'BLOQUEAR';
    _tiles = ref.read(setorTileProviderFactoryProvider)();
  }

  @override
  void dispose() {
    for (final controller in [
      _nome,
      _endereco,
      _latitude,
      _longitude,
      _raioInput,
    ]) {
      controller.dispose();
    }
    _map.dispose();
    super.dispose();
  }

  double? _numero(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  void _selecionar(LatLng point) {
    if (_salvando) return;
    setState(() {
      // Mantém mapa, coordenadas e JSON com a mesma precisão do banco.
      _latitude.text = point.latitude.toStringAsFixed(7);
      _longitude.text = point.longitude.toStringAsFixed(7);
      _ponto = LatLng(
        double.parse(_latitude.text),
        double.parse(_longitude.text),
      );
      _erro = null;
    });
    if (_mapReady && _map.camera.zoom < 12) _map.move(_ponto!, 15);
  }

  void _coordenadasDigitadas(String _) {
    final lat = _numero(_latitude.text), lon = _numero(_longitude.text);
    final valido =
        lat != null &&
        lon != null &&
        lat.isFinite &&
        lon.isFinite &&
        lat.abs() <= 90 &&
        lon.abs() <= 180;
    setState(() => _ponto = valido ? LatLng(lat, lon) : null);
    if (valido && _mapReady) _map.move(_ponto!, math.max(_map.camera.zoom, 15));
  }

  void _raioDigitado(String value) {
    final number = _numero(value);
    if (number != null && number.isFinite && number > 0) {
      setState(() => _raio = number);
    }
  }

  String? _validarNumero(String? value, double limite) {
    final number = _numero(value ?? '');
    return number == null || !number.isFinite || number.abs() > limite
        ? 'Informe um valor entre -$limite e $limite.'
        : null;
  }

  Future<void> _salvar() async {
    if (_salvando || !_form.currentState!.validate()) return;
    final session = ref.read(authProvider).asData?.value;
    if (session?.accessToken != widget.sessionToken ||
        session?.user.companyId != widget.empresaId) {
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref
          .read(setoresProvider.notifier)
          .salvar(
            Setor(
              id: widget.setor?.id ?? '',
              nome: _nome.text.trim(),
              empresaId: widget.empresaId,
              ativo: widget.setor?.ativo ?? true,
              endereco: _endereco.text.trim().isEmpty
                  ? null
                  : _endereco.text.trim(),
              latitude: _numero(_latitude.text),
              longitude: _numero(_longitude.text),
              raioMetros: _numero(_raioInput.text),
              exigeSelfie: _selfie,
              acaoForaPerimetro: _acao,
              ignorarLocalizacao: _ignorar,
            ),
          );
      if (mounted &&
          ref.read(authProvider).asData?.value?.accessToken ==
              widget.sessionToken) {
        Navigator.pop(context, true);
      }
    } on RepositoryFailure catch (error) {
      if (mounted &&
          ref.read(authProvider).asData?.value?.accessToken ==
              widget.sessionToken) {
        setState(() => _erro = error.message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(
              error.message,
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _campos() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        key: const Key('setor-nome'),
        controller: _nome,
        enabled: !_salvando,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Nome'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Informe o nome.' : null,
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const Key('setor-endereco'),
        controller: _endereco,
        enabled: !_salvando,
        maxLength: 255,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Endereço (opcional)'),
      ),
      const SizedBox(height: 12),
      SwitchListTile.adaptive(
        key: const Key('setor-selfie'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Exigir selfie'),
        value: _selfie,
        onChanged: _salvando
            ? null
            : (value) => setState(() => _selfie = value),
      ),
      SwitchListTile.adaptive(
        key: const Key('setor-ignorar-localizacao'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Ignorar localização'),
        subtitle: const Text('Permitir marcações sem posição do aparelho.'),
        value: _ignorar,
        onChanged: _salvando
            ? null
            : (value) => setState(() => _ignorar = value),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const Key('setor-acao-fora'),
        isExpanded: true,
        initialValue: _acao,
        decoration: const InputDecoration(labelText: 'Fora do perímetro'),
        items: const [
          DropdownMenuItem(value: 'BLOQUEAR', child: Text('Bloquear marcação')),
          DropdownMenuItem(
            value: 'PENDENTE',
            child: Text('Enviar para análise'),
          ),
        ],
        onChanged: _salvando ? null : (value) => setState(() => _acao = value!),
        validator: (value) => value == null ? 'Selecione a política.' : null,
      ),
      if (_ignorar)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Com localização dispensada, o perímetro não é exigido na marcação.',
          ),
        ),
    ],
  );

  Widget _perimetro() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Clique no mapa para escolher o centro do setor.'),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 320,
            child: Stack(
              children: [
                FlutterMap(
                  key: const Key('setor-mapa'),
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _ponto ?? const LatLng(-14.235, -51.9253),
                    initialZoom: _ponto == null ? 4 : 15,
                    minZoom: 2,
                    maxZoom: 19,
                    onMapReady: () => _mapReady = true,
                    interactionOptions: InteractionOptions(
                      flags: _salvando
                          ? InteractiveFlag.none
                          : InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onTap: (_, point) => _selecionar(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      tileProvider: _tiles,
                      userAgentPackageName: 'br.com.pontoaqui.admin',
                      errorTileCallback: (_, _, _) {
                        if (mounted && !_tilesFalharam) {
                          _tilesFalharam = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() {});
                          });
                        }
                      },
                    ),
                    if (_ponto != null)
                      CircleLayer(
                        key: const Key('setor-circulo'),
                        circles: [
                          CircleMarker(
                            point: _ponto!,
                            radius: _raio,
                            useRadiusInMeter: true,
                            color: colors.primary.withValues(alpha: .18),
                            borderColor: colors.primary,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    if (_ponto != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _ponto!,
                            width: 42,
                            height: 42,
                            alignment: Alignment.bottomCenter,
                            child: Icon(
                              Icons.location_on,
                              key: const Key('setor-pino'),
                              color: colors.primary,
                              size: 42,
                            ),
                          ),
                        ],
                      ),
                    RichAttributionWidget(
                      showFlutterMapAttribution: false,
                      attributions: [
                        TextSourceAttribution(
                          'OpenStreetMap contributors',
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://www.openstreetmap.org/copyright',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Card(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Ampliar mapa',
                          onPressed: _salvando
                              ? null
                              : () => _map.move(
                                  _map.camera.center,
                                  math.min(19, _map.camera.zoom + 1),
                                ),
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: 'Reduzir mapa',
                          onPressed: _salvando
                              ? null
                              : () => _map.move(
                                  _map.camera.center,
                                  math.max(2, _map.camera.zoom - 1),
                                ),
                          icon: const Icon(Icons.remove),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_tilesFalharam)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Mapa indisponível no momento. Você pode informar as coordenadas manualmente.',
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('setor-latitude'),
                controller: _latitude,
                enabled: !_salvando,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Latitude'),
                onChanged: _coordenadasDigitadas,
                validator: (value) => _validarNumero(value, 90),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('setor-longitude'),
                controller: _longitude,
                enabled: !_salvando,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Longitude'),
                onChanged: _coordenadasDigitadas,
                validator: (value) => _validarNumero(value, 180),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('setor-raio'),
          controller: _raioInput,
          enabled: !_salvando,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Raio (metros)'),
          onChanged: _raioDigitado,
          validator: (value) {
            final number = _numero(value ?? '');
            return number == null || !number.isFinite || number <= 0
                ? 'Informe um raio maior que zero.'
                : null;
          },
        ),
        Slider(
          key: const Key('setor-raio-slider'),
          min: math.min(1, _raio),
          max: math.max(5000, _raio),
          value: _raio,
          label: '${_raio.toStringAsFixed(2)} m',
          onChanged: _salvando
              ? null
              : (value) => setState(() {
                  _raio = (value * 100).roundToDouble() / 100;
                  _raioInput.text = _raio.toStringAsFixed(2);
                }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => PopScope(
      canPop: !_salvando,
      child: AlertDialog(
        title: Text(widget.setor == null ? 'Novo Setor' : 'Editar Setor'),
        scrollable: true,
        content: SizedBox(
          width: 1040,
          child: Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (constraints.maxWidth - 128 >= 760)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 320, child: _campos()),
                      const SizedBox(width: 28),
                      SizedBox(
                        width: math.min(1040, constraints.maxWidth - 128) - 348,
                        child: _perimetro(),
                      ),
                    ],
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _campos(),
                      const SizedBox(height: 24),
                      _perimetro(),
                    ],
                  ),
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _erro!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_salvando) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _salvando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _salvando ? null : _salvar,
            child: Text(_salvando ? 'Salvando...' : 'Salvar'),
          ),
        ],
      ),
    ),
  );
}
