import 'package:flutter/material.dart';

import '../../models/dispositivo.dart';
import '../widgets/status_badge.dart';

class AparelhoCard extends StatelessWidget {
  const AparelhoCard({
    super.key,
    required this.aparelho,
    required this.copiarCodigo,
    required this.copiarId,
    required this.podeGerenciar,
    this.revogar,
  });

  final DispositivoFuncionario aparelho;
  final VoidCallback copiarCodigo;
  final VoidCallback copiarId;
  final bool podeGerenciar;
  final VoidCallback? revogar;

  Widget get _status => StatusBadge(
    ativo: aparelho.ativo,
    activeLabel: 'Ativo',
    inactiveLabel: 'Inativo',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textoBotao = TextStyle(
      fontFamily: theme.textTheme.labelLarge?.fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 520;
            final codigo = compacto && aparelho.deviceUuid.length > 16
                ? '${aparelho.deviceUuid.substring(0, 8)}…${aparelho.deviceUuid.substring(aparelho.deviceUuid.length - 4)}'
                : aparelho.deviceUuid;
            final copiar = OutlinedButton.icon(
              style: OutlinedButton.styleFrom(textStyle: textoBotao),
              onPressed: copiarCodigo,
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copiar código'),
            );
            final id = TextButton.icon(
              onPressed: copiarId,
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text('Copiar ID de cadastro'),
            );
            final revogacao = OutlinedButton.icon(
              key: ValueKey('revogar-${aparelho.id}'),
              style: OutlinedButton.styleFrom(
                textStyle: textoBotao,
                foregroundColor: theme.brightness == Brightness.dark
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFF9B2C2C),
              ),
              onPressed: revogar,
              icon: const Icon(Icons.phonelink_erase, size: 18),
              label: const Text('Revogar acesso'),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        aparelho.tipo == TipoAparelho.relogio
                            ? Icons.tablet_android_outlined
                            : Icons.phone_android_outlined,
                        color: colors.onSecondaryContainer,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            aparelho.nome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            aparelho.tipo.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (compacto) ...[
                            const SizedBox(height: 10),
                            _status,
                          ],
                        ],
                      ),
                    ),
                    if (!compacto) ...[const SizedBox(width: 16), _status],
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Código do aparelho',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Sem tooltip sobreposto aos botões; a cópia sempre usa o UUID completo.
                      SelectableText(
                        codigo,
                        maxLines: 1,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                if (aparelho.tipo == TipoAparelho.relogio) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Compartilhado; cada funcionário mantém suas autorizações por setor.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (aparelho.setores.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Setores autorizados',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final setor in aparelho.setores)
                          Chip(
                            label: Text(
                              '${setor.nome}${setor.ativo ? '' : ' (inativo)'}',
                            ),
                            backgroundColor: setor.ativo
                                ? colors.secondaryContainer
                                : colors.surfaceContainerHighest,
                            labelStyle: TextStyle(
                              color: setor.ativo
                                  ? colors.onSecondaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                Divider(
                  height: 24,
                  color: colors.outlineVariant.withValues(alpha: .6),
                ),
                if (compacto)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      copiar,
                      const SizedBox(height: 8),
                      id,
                      if (podeGerenciar) ...[
                        const SizedBox(height: 8),
                        revogacao,
                      ],
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [copiar, id],
                        ),
                      ),
                      if (podeGerenciar) ...[
                        const SizedBox(width: 16),
                        revogacao,
                      ],
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
