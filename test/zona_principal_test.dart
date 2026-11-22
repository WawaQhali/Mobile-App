import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wawa_qhali/services/image_processing.dart';
import 'package:wawa_qhali/services/zona_principal.dart';

/// Máscara n × n con rectángulos de piel (en celdas).
List<bool> mascara(List<(int, int, int, int)> rectangulos, {int n = ladoMascara}) => [
      for (var y = 0; y < n; y++)
        for (var x = 0; x < n; x++)
          rectangulos.any((r) => x >= r.$1 && x < r.$1 + r.$3 && y >= r.$2 && y < r.$2 + r.$4),
    ];

/// Foto con dos «brazos» color piel sobre un fondo azul (no es piel).
Uint8List fotoDosBrazos({int lado = 512}) {
  final foto = img.Image(width: lado, height: lado);
  for (final p in foto) {
    final izquierdo = p.x > lado * 0.05 && p.x < lado * 0.40 && p.y > lado * 0.10 && p.y < lado * 0.90;
    final derecho = p.x > lado * 0.60 && p.x < lado * 0.85 && p.y > lado * 0.20 && p.y < lado * 0.80;
    if (izquierdo || derecho) {
      p
        ..r = 205
        ..g = 150
        ..b = 125;
    } else {
      p
        ..r = 40
        ..g = 70
        ..b = 160;
    }
  }
  return img.encodeJpg(foto, quality: 95);
}

class SegmentadorFalso implements Segmentador {
  SegmentadorFalso(this.respuesta);

  final List<bool>? respuesta;

  @override
  Future<List<bool>?> pielDelCuerpo(Uint8List jpeg) async => respuesta;
}

void main() {
  setUp(() => usarIsolates = false);

  test('con dos brazos elige el más grande y avisa que hay dos zonas', () {
    final zona = elegirZona(mascara([(4, 6, 22, 52), (40, 12, 16, 40)]), 'color');
    expect(zona.zonas, 2);
    expect(zona.variasZonas, isTrue);
    expect(zona.recortada, isTrue);
    // El recorte contiene el centro del brazo izquierdo (x ≈ 15/64) y no toca el derecho (desde 40/64).
    expect(zona.x, lessThanOrEqualTo(15 / 64));
    expect(zona.x + zona.lado, greaterThan(15 / 64));
    expect(zona.x + zona.lado, lessThanOrEqualTo(40 / 64));
    // La máscara solo marca la zona principal.
    expect(zona.mascara[30 * ladoMascara + 10], 1);
    expect(zona.mascara[30 * ladoMascara + 48], 0);
  });

  test('a igual tamaño gana la zona más centrada', () {
    final zona = elegirZona(mascara([(0, 0, 12, 12), (26, 26, 12, 12)]), 'color');
    expect(zona.x + zona.lado / 2, closeTo(32 / 64, 0.02));
    expect(zona.y + zona.lado / 2, closeTo(32 / 64, 0.02));
  });

  test('un primer plano que llena la foto no se recorta', () {
    final zona = elegirZona(mascara([(2, 2, 60, 60)]), 'color');
    expect(zona.zonas, 1);
    expect(zona.recortada, isFalse);
    expect(zona.tieneContorno, isTrue);
  });

  test('una zona chica no se recorta a menos del 40 % de la foto', () {
    final zona = elegirZona(mascara([(30, 30, 10, 10)]), 'color');
    expect(zona.lado, closeTo(0.4, 1e-9));
    expect(zona.x, greaterThanOrEqualTo(0));
    expect(zona.x + zona.lado, lessThanOrEqualTo(1));
  });

  test('sin piel se evalúa la foto completa', () {
    final zona = elegirZona(mascara([]), 'color');
    expect(zona.recortada, isFalse);
    expect(zona.tieneContorno, isFalse);
    expect(zona.zonas, 0);
  });

  test('sin segmentador usa el color (nivel 1) y recorta la zona principal', () async {
    Segmentador.instancia = SegmentadorFalso(null);
    final foto = fotoDosBrazos();
    final (zona, entrada) = await zonaParaClasificar(foto);
    expect(zona.metodo, 'color');
    expect(zona.zonas, 2);
    final recorte = img.decodeJpg(entrada)!;
    expect(recorte.width, recorte.height);
    expect(recorte.width, lessThan(512));
  });

  test('con segmentador (nivel 2) usa su máscara', () async {
    Segmentador.instancia = SegmentadorFalso(mascara([(10, 10, 20, 20)]));
    final (zona, _) = await zonaParaClasificar(fotoDosBrazos());
    expect(zona.metodo, 'segmentador');
    expect(zona.zonas, 1);
  });

  test('si el segmentador falla, sigue con la foto completa sin romperse', () async {
    Segmentador.instancia = SegmentadorFalso(null);
    final (zona, entrada) = await zonaParaClasificar(Uint8List.fromList([1, 2, 3]));
    expect(zona.recortada, isFalse);
    expect(entrada, [1, 2, 3]);
  });
}
