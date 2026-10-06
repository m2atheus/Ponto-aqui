import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.ativo});
  final bool ativo;

  @override
  Widget build(BuildContext context) {
    final color = ativo ? BrandColors.teal : BrandColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ativo ? BrandColors.mint : BrandColors.background,
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
            ativo ? 'Ativa' : 'Inativa',
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
