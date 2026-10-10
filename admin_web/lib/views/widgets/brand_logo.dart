import 'package:flutter/material.dart';

/// Logo transparente; a versão noturna mantém a marca legível em fundos escuros.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 220});
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: AspectRatio(
      aspectRatio: 3.15,
      child: ClipRect(
        child: Image.asset(
          Theme.of(context).brightness == Brightness.dark
              ? 'assets/brand/ponto_aqui_logo_dark.png'
              : 'assets/brand/ponto_aqui_logo_transparent.png',
          fit: BoxFit.cover,
          alignment: const Alignment(0, 0.05),
          filterQuality: FilterQuality.high,
          semanticLabel: 'Ponto Aqui',
        ),
      ),
    ),
  );
}
