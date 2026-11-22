import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/zona_principal.dart';
import '../theme/app_theme.dart';
import 'shared.dart';

/// Foto con el contorno de la zona de piel que evaluó el modelo. Si se veían varias partes
/// del cuerpo (por ejemplo, dos brazos), lo dice: así el padre sabe qué se evaluó.
class ZonaEvaluada extends StatelessWidget {
  const ZonaEvaluada({super.key, required this.foto, required this.zona});

  final Uint8List foto;
  final ZonaPrincipal zona;

  @override
  Widget build(BuildContext context) {
    final texto = zona.variasZonas
        ? 'Vimos ${zona.zonas} zonas de piel en la foto y evaluamos solo la marcada. '
            'Si querías revisar otra, toma una foto solo de esa zona.'
        : 'Esta es la zona de piel que evaluamos.';
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zona evaluada', style: AppText.cuerpo(14, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FotoLesion(bytes: foto),
                  CustomPaint(painter: ContornoZonaPainter(zona)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(texto, style: AppText.cuerpo(12.5, color: AppColors.textoSuave, height: 1.45)),
        ],
      ),
    );
  }
}

/// Oscurece lo que quedó fuera de la zona y dibuja su borde, celda por celda de la máscara.
class ContornoZonaPainter extends CustomPainter {
  ContornoZonaPainter(this.zona);

  final ZonaPrincipal zona;

  @override
  void paint(Canvas canvas, Size size) {
    if (!zona.tieneContorno) return;
    const n = ladoMascara;
    final m = zona.mascara;
    final cw = size.width / n, ch = size.height / n;
    bool dentro(int x, int y) => x >= 0 && y >= 0 && x < n && y < n && m[y * n + x] == 1;

    final fuera = Path()..fillType = PathFillType.evenOdd;
    final borde = Path();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (!dentro(x, y)) {
          fuera.addRect(Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5));
          continue;
        }
        final l = x * cw, t = y * ch, r = l + cw, b = t + ch;
        if (!dentro(x, y - 1)) borde..moveTo(l, t)..lineTo(r, t);
        if (!dentro(x, y + 1)) borde..moveTo(l, b)..lineTo(r, b);
        if (!dentro(x - 1, y)) borde..moveTo(l, t)..lineTo(l, b);
        if (!dentro(x + 1, y)) borde..moveTo(r, t)..lineTo(r, b);
      }
    }
    canvas.drawPath(fuera, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawPath(
      borde,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      borde,
      Paint()
        ..color = AppColors.carameloOscuro
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(ContornoZonaPainter old) => old.zona != zona;
}
