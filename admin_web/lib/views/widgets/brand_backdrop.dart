import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Decorative geometry drawn locally; no external image or network dependency.
class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({super.key, required this.child, this.subtle = false});

  final Widget child;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: subtle
              ? [
                  Theme.of(context).scaffoldBackgroundColor,
                  dark ? const Color(0xFF14232A) : const Color(0xFFF0F8F7),
                ]
              : dark
              ? [
                  const Color(0xFF061C31),
                  const Color(0xFF142830),
                  const Color(0xFF203B40),
                ]
              : [
                  const Color(0xFF062C50),
                  const Color(0xFF91A6B3),
                  const Color(0xFFECF8F5),
                ],
          stops: subtle ? null : const [0, 0.55, 1],
        ),
      ),
      child: CustomPaint(
        painter: _BrandGeometry(subtle: subtle, dark: dark),
        child: child,
      ),
    );
  }
}

class _BrandGeometry extends CustomPainter {
  const _BrandGeometry({required this.subtle, required this.dark});
  final bool subtle;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final opacity = subtle ? 0.035 : 0.22;
    final teal = Paint()..color = BrandColors.teal.withValues(alpha: opacity);
    final blue = Paint()
      ..color = const Color(0xFF2582BF).withValues(alpha: opacity);
    for (final (x, y, paint) in [
      (0.72, 0.2, blue),
      (0.77, 0.24, teal),
      (0.23, 0.78, teal),
    ]) {
      canvas.save();
      canvas.translate(size.width * x, size.height * y);
      canvas.skew(0, -0.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: size.width * 0.14,
            height: size.height * 0.28,
          ),
          const Radius.circular(18),
        ),
        paint,
      );
      canvas.restore();
    }
    final ribbon = Path()
      ..moveTo(size.width * 0.16, size.height * 0.85)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.25,
        size.width * 0.66,
        size.height * 0.94,
        size.width * 0.82,
        size.height * 0.31,
      );
    canvas.drawPath(
      ribbon,
      Paint()
        ..color = const Color(0xFF38BAAB).withValues(alpha: opacity * 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.12,
    );
    final dots = Paint()
      ..color = (dark ? Colors.white : BrandColors.navy).withValues(
        alpha: subtle ? 0.04 : 0.14,
      );
    for (var x = 0; x < 16; x++) {
      for (var y = 0; y < 13; y++) {
        canvas.drawCircle(
          Offset(size.width * 0.81 + x * 15, y * 15 + 10),
          0.8,
          dots,
        );
        if (!subtle) {
          canvas.drawCircle(
            Offset(x * 15 + 8, size.height * 0.69 + y * 15),
            0.8,
            dots,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandGeometry oldDelegate) =>
      oldDelegate.subtle != subtle || oldDelegate.dark != dark;
}

/// A small, purely illustrative dashboard, not live employee statistics.
class BrandJourneyArt extends StatelessWidget {
  const BrandJourneyArt({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      width: 230,
      height: 128,
      child: CustomPaint(painter: _JourneyPainter()),
    ),
  );
}

class _JourneyPainter extends CustomPainter {
  const _JourneyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 230, size.height / 128);
    final pale = Paint()..color = const Color(0xFFD5F4EE);
    final teal = Paint()..color = const Color(0xFF50BBAC);
    final navy = Paint()..color = BrandColors.navy;
    canvas.drawCircle(
      const Offset(160, 66),
      60,
      Paint()..color = const Color(0xFF62CDBA).withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(28, 15, 174, 104),
        const Radius.circular(9),
      ),
      pale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(35, 23, 25, 88),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFAFDDD8),
    );
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(
        Offset(42, 43 + i * 12),
        Offset(53, 43 + i * 12),
        Paint()
          ..color = const Color(0xFF5F9E9F)
          ..strokeWidth = 2,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(69, 23, 123, 9),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(69, 40, 123, 39),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white,
    );
    final chart = Path()
      ..moveTo(76, 70)
      ..lineTo(91, 59)
      ..lineTo(106, 64)
      ..lineTo(123, 49)
      ..lineTo(139, 55)
      ..lineTo(155, 46)
      ..lineTo(184, 48);
    canvas.drawPath(
      chart,
      Paint()
        ..color = const Color(0xFF36A595)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(69 + i * 43, 87, 37, 23),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.white,
      );
      canvas.drawLine(
        Offset(77 + i * 43, 98),
        Offset(95 + i * 43, 98),
        teal..strokeWidth = 3,
      );
    }
    canvas.drawCircle(const Offset(207, 76), 7, pale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(199, 85, 15, 24),
        const Radius.circular(5),
      ),
      teal,
    );
    canvas.drawLine(
      const Offset(203, 108),
      const Offset(201, 124),
      navy..strokeWidth = 4,
    );
    canvas.drawLine(const Offset(211, 108), const Offset(216, 124), navy);
    canvas.drawCircle(const Offset(23, 94), 7, pale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(15, 103, 16, 18),
        const Radius.circular(5),
      ),
      teal,
    );
    canvas.drawLine(
      const Offset(10, 124),
      const Offset(223, 124),
      Paint()
        ..color = const Color(0xFF96DACE)
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JourneyPainter oldDelegate) => false;
}
