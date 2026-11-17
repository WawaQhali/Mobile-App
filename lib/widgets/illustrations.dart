import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Montaña + línea de pulso del logo (viewBox 40×28 del mockup).
class LogoPainter extends CustomPainter {
  const LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40, size.height / 28);
    final montana = Path()
      ..moveTo(1, 26)
      ..lineTo(13, 8)
      ..lineTo(19, 16)
      ..lineTo(26, 5)
      ..lineTo(39, 26)
      ..close();
    canvas.drawPath(montana, Paint()..color = AppColors.tostado);

    final pulso = Path()
      ..moveTo(4, 19)
      ..relativeLineTo(8, 0)
      ..relativeLineTo(2.5, -5)
      ..relativeLineTo(3.5, 9)
      ..relativeLineTo(3, -6)
      ..relativeLineTo(14, 0);
    canvas.drawPath(
      pulso,
      Paint()
        ..color = AppColors.caramelo
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Wawa envuelta en su manta (viewBox 120×150 del mockup).
class WawaIlustracion extends StatelessWidget {
  const WawaIlustracion({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 150 / 120,
      child: const CustomPaint(painter: _WawaPainter()),
    );
  }
}

class _WawaPainter extends CustomPainter {
  const _WawaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 120, size.height / 150);
    Paint relleno(Color c) => Paint()..color = c;
    Paint trazo(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawOval(Rect.fromCenter(center: const Offset(60, 144), width: 80, height: 10), relleno(AppColors.tostado));
    canvas.drawRRect(
      RRect.fromLTRBR(24, 12, 96, 138, const Radius.circular(36)),
      relleno(const Color(0xFF8A8558)),
    );
    canvas.drawCircle(const Offset(60, 50), 21, relleno(const Color(0xFFEBC9A4)));

    final cara = trazo(const Color(0xFF5A3E2B), 1.6);
    canvas.drawPath(Path()..moveTo(51, 48)..quadraticBezierTo(54, 51, 57, 48), cara);
    canvas.drawPath(Path()..moveTo(63, 48)..quadraticBezierTo(66, 51, 69, 48), cara);
    canvas.drawPath(Path()..moveTo(56, 58)..quadraticBezierTo(60, 61, 64, 58), cara);
    final mejilla = relleno(const Color(0x99E3A58A));
    canvas.drawCircle(const Offset(48.5, 55), 3.2, mejilla);
    canvas.drawCircle(const Offset(71.5, 55), 3.2, mejilla);

    canvas.drawPath(Path()..moveTo(27, 80)..cubicTo(49, 73, 73, 84, 93, 102), trazo(AppColors.oliva, 2));
    _zigzag(canvas, 100, trazo(const Color(0xFFF3E6CF), 2));
    _zigzag(canvas, 116, trazo(const Color(0xFFC9B48E), 2));
  }

  void _zigzag(Canvas canvas, double y, Paint paint) {
    final p = Path()..moveTo(30, y);
    for (var i = 1; i <= 10; i++) {
      p.lineTo(30 + i * 6.0, i.isOdd ? y - 6 : y);
    }
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Lesión de muestra (cuando no hay foto real), escalada tipo «cover».
class LesionMuestraPainter extends CustomPainter {
  const LesionMuestraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFCF9C7E));
    final s = math.max(size.width, size.height) / 150;
    canvas.save();
    canvas.translate((size.width - 150 * s) / 2, (size.height - 150 * s) / 2);
    canvas.scale(s);
    const blur = MaskFilter.blur(BlurStyle.normal, 3);
    void ovalo(double cx, double cy, double rx, double ry, Color c) => canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
          Paint()
            ..color = c
            ..maskFilter = blur,
        );
    ovalo(66, 78, 34, 26, const Color(0xBFD7806C));
    ovalo(66, 78, 15, 10, const Color(0xFFEBC3AA));
    ovalo(112, 48, 22, 18, const Color(0xB3D7806C));
    ovalo(112, 48, 9, 7, const Color(0xFFEBC3AA));
    ovalo(104, 116, 20, 15, const Color(0xA6D7806C));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mapa simplificado (placeholder hasta integrar un mapa real).
/// [pines] y [usuario] van en fracciones del tamaño (0..1).
class MapaPainter extends CustomPainter {
  const MapaPainter({this.pines = const [Offset(0.56, 0.55)], this.usuario});

  final List<Offset> pines;
  final Offset? usuario;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.arena);

    final calle = Paint()
      ..color = AppColors.superficie
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(-10, h * .67)
        ..cubicTo(w * .3, h * .45, w * .55, h * .85, w + 10, h * .45),
      calle..strokeWidth = 10,
    );
    canvas.drawLine(Offset(w * .32, -10), Offset(w * .43, h + 10), calle..strokeWidth = 7);
    canvas.drawLine(Offset(w * .72, -10), Offset(w * .66, h + 10), calle);

    void manzana(double x, double y, double bw, double bh, Color c) => canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(w * x, h * y, bw, bh), const Radius.circular(6)),
          Paint()..color = c,
        );
    manzana(.06, .12, 60, 34, AppColors.borde);
    manzana(.78, .63, 56, 30, AppColors.borde);
    manzana(.49, .10, 44, 30, AppColors.tostado);

    for (final p in pines) {
      final c = Offset(p.dx * w, p.dy * h);
      canvas.drawCircle(c, 16, Paint()..color = AppColors.terracota.withValues(alpha: .18));
      final pin = Path()
        ..moveTo(c.dx, c.dy + 10)
        ..quadraticBezierTo(c.dx - 9, c.dy, c.dx - 9, c.dy - 4)
        ..arcToPoint(Offset(c.dx + 9, c.dy - 4), radius: const Radius.circular(9))
        ..quadraticBezierTo(c.dx + 9, c.dy, c.dx, c.dy + 10)
        ..close();
      canvas.drawPath(pin, Paint()..color = AppColors.terracota);
      canvas.drawCircle(c.translate(0, -4), 3, Paint()..color = AppColors.sobreAccion);
    }

    if (usuario != null) {
      final u = Offset(usuario!.dx * w, usuario!.dy * h);
      canvas.drawCircle(u, 11, Paint()..color = AppColors.sobreAccion);
      canvas.drawCircle(u, 7, Paint()..color = AppColors.caramelo);
    }
  }

  @override
  bool shouldRepaint(covariant MapaPainter oldDelegate) => oldDelegate.pines != pines || oldDelegate.usuario != usuario;
}
