import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.ativo,
    this.activeLabel = 'Ativa',
    this.inactiveLabel = 'Inativa',
  });
  final bool ativo;
  final String activeLabel;
  final String inactiveLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = ativo
        ? colors.onSecondaryContainer
        : dark
        ? const Color(0xFFFCA5A5)
        : const Color(0xFF9B2C2C);
    final background = ativo
        ? colors.secondaryContainer
        : dark
        ? const Color(0xFF3F1D1D)
        : const Color(0xFFFDECEC);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            ativo ? activeLabel : inactiveLabel,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
