import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Resultado del análisis de una foto (guía del backend, secciones 5.2 y 5.3).
class FotoProcesada {
  const FotoProcesada({
    required this.anchoOriginal,
    required this.altoOriginal,
    required this.nitidez,
    required this.luminancia,
    required this.proporcionPiel,
    required this.recorte,
  });

  final int anchoOriginal;
  final int altoOriginal;

  /// Varianza del Laplaciano sobre el recorte reducido a 512 px en grises.
  final double nitidez;

  /// Luminancia media (0 a 255).
  final double luminancia;

  /// Fracción de píxeles con color de piel (0 a 1).
  final double proporcionPiel;

  /// Recorte central cuadrado de 1024 px (o menos si la foto es chica),
  /// JPEG calidad 85, SIN metadatos EXIF. Es lo único que se guarda y se dona.
  final Uint8List recorte;

  int get ladoCorto => min(anchoOriginal, altoOriginal);
}

const _ladoRecorte = 1024;
const _ladoMetricas = 512;

/// En las pruebas de widgets los isolates no avanzan: ahí se procesa en el mismo hilo.
bool usarIsolates = true;

/// Procesa la foto en otro isolate para no congelar la pantalla.
Future<FotoProcesada?> procesarFoto(Uint8List bytes) async =>
    usarIsolates ? compute(procesarFotoSincrono, bytes) : procesarFotoSincrono(bytes);

Uint8List _muestra(int lado) => fotoDeMuestra(lado: lado);

/// Foto de muestra generada en otro isolate.
Future<Uint8List> generarFotoDeMuestra() async =>
    usarIsolates ? compute(_muestra, 1200) : fotoDeMuestra();

/// 1. Decodifica y aplica la orientación EXIF (luego el EXIF se descarta).
/// 2. Recorte central cuadrado.
/// 3. Recorte de 1024 px en JPEG 85 sin EXIF, y métricas sobre una copia de 512 px.
FotoProcesada? procesarFotoSincrono(Uint8List bytes) {
  final decodificada = img.decodeImage(bytes);
  if (decodificada == null) return null;
  final orientada = img.bakeOrientation(decodificada);
  final lado = min(orientada.width, orientada.height);
  final cuadrada = img.copyCrop(
    orientada,
    x: (orientada.width - lado) ~/ 2,
    y: (orientada.height - lado) ~/ 2,
    width: lado,
    height: lado,
  );
  final recorte = lado > _ladoRecorte
      ? img.copyResize(cuadrada, width: _ladoRecorte, height: _ladoRecorte, interpolation: img.Interpolation.average)
      : cuadrada;
  recorte.exif = img.ExifData(); // sin metadatos (incluida la geolocalización)

  final chica = img.copyResize(recorte, width: _ladoMetricas, height: _ladoMetricas);
  return FotoProcesada(
    anchoOriginal: orientada.width,
    altoOriginal: orientada.height,
    nitidez: varianzaLaplaciano(chica),
    luminancia: luminanciaMedia(chica),
    proporcionPiel: proporcionPiel(chica),
    recorte: img.encodeJpg(recorte, quality: 85),
  );
}

double _gris(img.Pixel p) => 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;

/// Nitidez: varianza de la respuesta al operador Laplaciano (4 vecinos).
/// Una foto borrosa casi no tiene bordes, así que la varianza es baja.
double varianzaLaplaciano(img.Image imagen) {
  final gris = Float64List(imagen.width * imagen.height);
  var i = 0;
  for (final p in imagen) {
    gris[i++] = _gris(p);
  }
  return _varianzaLaplacianoGris(gris, imagen.width, imagen.height);
}

double _varianzaLaplacianoGris(Float64List gris, int w, int h) {
  var suma = 0.0, sumaCuadrados = 0.0, n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final c = y * w + x;
      final lap = gris[c - 1] + gris[c + 1] + gris[c - w] + gris[c + w] - 4 * gris[c];
      suma += lap;
      sumaCuadrados += lap * lap;
      n++;
    }
  }
  if (n == 0) return 0;
  final media = suma / n;
  return sumaCuadrados / n - media * media;
}

/// Luz y nitidez de un cuadro de la vista previa de la cámara, en vivo.
///
/// Usa solo el plano Y (luminancia, 0 a 255) del cuadro YUV que entrega la cámara.
/// Se mide el cuadrado central (lo que cae en el círculo y lo que luego se recorta),
/// muestreado a lo sumo a 512 px, igual que en [procesarFotoSincrono]: así los mismos
/// umbrales de `db.json -> foto` sirven para la vista previa y para la foto.
///
/// Si llegan los planos de color U (Cb) y V (Cr), también mide qué fracción del
/// centro del cuadro es piel ([esPiel] en YCbCr, la misma regla que la foto), solo
/// dentro del círculo de la pantalla: el cuadrado central del [fraccionCirculo]
/// del lado corto. Sin ellos, `piel` es null.
({double nitidez, double luminancia, double? piel}) metricasDeCuadro(
  Uint8List planoY, {
  required int ancho,
  required int alto,
  required int bytesPorFila,
  Uint8List? planoU,
  Uint8List? planoV,
  int bytesPorFilaUV = 0,
  int bytesPorPixelUV = 1,
}) {
  final cuadrado = min(ancho, alto);
  final n = min(cuadrado, _ladoMetricas);
  if (n < 3) return (nitidez: 0, luminancia: 0, piel: null);
  final x0 = (ancho - cuadrado) ~/ 2, y0 = (alto - cuadrado) ~/ 2;
  final gris = Float64List(n * n);
  var suma = 0.0;
  for (var j = 0; j < n; j++) {
    final fila = (y0 + j * cuadrado ~/ n) * bytesPorFila + x0;
    for (var i = 0; i < n; i++) {
      final v = planoY[fila + i * cuadrado ~/ n].toDouble();
      gris[j * n + i] = v;
      suma += v;
    }
  }
  final piel = planoU == null || planoV == null
      ? null
      : _pielEnCirculo(planoU, planoV, ancho, alto, bytesPorFilaUV, bytesPorPixelUV);
  return (nitidez: _varianzaLaplacianoGris(gris, n, n), luminancia: suma / (n * n), piel: piel);
}

/// Lado del cuadrado medido para la piel, como fracción del lado corto del cuadro.
/// El círculo de la pantalla ocupa ~60 % del ancho visible.
const fraccionCirculo = 0.6;
const _muestrasPiel = 48;

/// Fracción de piel en el centro, con los planos U y V (submuestreados 2×2 en YUV 4:2:0).
double _pielEnCirculo(Uint8List u, Uint8List v, int ancho, int alto, int fila, int paso) {
  final anchoUV = ancho ~/ 2, altoUV = alto ~/ 2;
  final lado = (min(anchoUV, altoUV) * fraccionCirculo).floor();
  if (lado < 2 || fila <= 0) return 0;
  final x0 = (anchoUV - lado) ~/ 2, y0 = (altoUV - lado) ~/ 2;
  final m = min(lado, _muestrasPiel);
  var piel = 0, total = 0;
  for (var j = 0; j < m; j++) {
    final y = y0 + j * lado ~/ m;
    for (var i = 0; i < m; i++) {
      final k = y * fila + (x0 + i * lado ~/ m) * paso;
      if (k >= u.length || k >= v.length) continue;
      final cb = u[k], cr = v[k];
      if (cb >= 77 && cb <= 127 && cr >= 133 && cr <= 180) piel++;
      total++;
    }
  }
  return total == 0 ? 0 : piel / total;
}

double luminanciaMedia(img.Image imagen) {
  var suma = 0.0;
  for (final p in imagen) {
    suma += _gris(p);
  }
  return suma / (imagen.width * imagen.height);
}

/// Piel por color en YCbCr (regla clásica de Chai y Ngan, con el rango de Cr
/// algo más amplio para incluir piel enrojecida por las ronchas).
double proporcionPiel(img.Image imagen) {
  var piel = 0;
  for (final p in imagen) {
    if (esPiel(p.r, p.g, p.b)) piel++;
  }
  return piel / (imagen.width * imagen.height);
}

/// ¿El color (0..255) es de piel? También la usa la zona principal (nivel 1).
bool esPiel(num r, num g, num b) {
  final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
  final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
  return cb >= 77 && cb <= 127 && cr >= 133 && cr <= 180;
}

/// Foto de muestra para cuando no hay cámara (emulador sin cámara, pruebas).
/// Piel con textura y tres habones; es nítida para que pase la validación.
Uint8List fotoDeMuestra({int lado = 1200}) {
  final imagen = img.Image(width: lado, height: lado);
  final azar = Random(7);
  final habones = [(0.38, 0.52, 0.17), (0.68, 0.33, 0.11), (0.66, 0.75, 0.09)];
  for (final p in imagen) {
    final u = p.x / lado, v = p.y / lado;
    var mezcla = 0.0;
    for (final (cx, cy, r) in habones) {
      final d = sqrt(pow(u - cx, 2) + pow(v - cy, 2)) / r;
      if (d < 1.6) mezcla = max(mezcla, 0.8 * exp(-pow(d - 0.8, 2) * 6));
    }
    final ruido = azar.nextInt(36) - 18; // poros y textura
    p
      ..r = (207 * (1 - mezcla) + 215 * mezcla + ruido).clamp(0, 255)
      ..g = (156 * (1 - mezcla) + 128 * mezcla + ruido).clamp(0, 255)
      ..b = (126 * (1 - mezcla) + 108 * mezcla + ruido).clamp(0, 255);
  }
  return img.encodeJpg(imagen, quality: 92);
}
