import 'package:flutter/material.dart';

/// A imagem original é enquadrada pela UI, preservando o arquivo da marca.
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
          'assets/brand/ponto_aqui_logo.png',
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.03),
          semanticLabel: 'Ponto Aqui',
        ),
      ),
    ),
  );
}
