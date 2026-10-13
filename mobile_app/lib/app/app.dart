import 'package:flutter/material.dart';

import '../features/marcacoes/presentation/mark_screen.dart';

class PontoApp extends StatelessWidget {
  const PontoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ponto-aqui',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF008E89),
        primary: const Color(0xFF0B3158),
        secondary: const Color(0xFF008E89),
      ),
      scaffoldBackgroundColor: const Color(0xFFF3F6FA),
    ),
    home: const MarkHome(),
  );
}
