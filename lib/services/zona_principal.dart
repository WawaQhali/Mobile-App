import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'image_processing.dart';

/// Resolución de las máscaras de piel (n × n celdas sobre la foto cuadrada).
const ladoMascara = 64;

/// Una zona debe ocupar al menos esta fracción de la foto para contar.
const _areaMinima = 0.02;

/// Otra zona «compite» con la principal si mide al menos esta fracción de ella.
const _proporcionOtraZona = 0.25;

/// El recorte es un cuadrado del lado MENOR de la zona (más un margen), centrado en ella: en un
/// brazo largo toma su parte central y no alcanza al otro brazo. Nunca menos de [_ladoMinimo]
/// de la foto, para que el modelo vea piel alrededor de la lesión (como en su entrenamiento).
const _margen = 1.2;
const _ladoMinimo = 0.4;

/// La zona de piel que se evalúa cuando en la foto se ven varias partes del cuerpo
/// (por ejemplo, dos brazos). Todo va en coordenadas de 0 a 1 sobre la foto cuadrada.
class ZonaPrincipal {
  const ZonaPrincipal({
    required this.x,
    required this.y,
    required this.lado,
    required this.mascara,
    required this.zonas,
    required this.metodo,
  });

  /// Toda la foto: no se encontró piel separable (o la piel la llena).
  factory ZonaPrincipal.completa({String metodo = 'ninguno'}) => ZonaPrincipal(
        x: 0,
        y: 0,
        lado: 1,
        mascara: Uint8List(0),
        zonas: 0,
        metodo: metodo,
      );

  /// Esquina superior izquierda y lado del recorte cuadrado que va al modelo.
  final double x, y, lado;

  /// Celdas de la zona principal ([ladoMascara]²; 1 = zona). Vacía si no hay zona.
  final Uint8List mascara;

  /// Zonas de piel de tamaño parecido que se vieron en la foto (0 si no hubo ninguna).
  final int zonas;

  /// `segmentador` (MediaPipe, nivel 2), `color` (piel por color, nivel 1) o `ninguno`.
  final String metodo;

  bool get recortada => lado < 0.999;
  bool get variasZonas => zonas > 1;
  bool get tieneContorno => mascara.isNotEmpty;
}

/// Elige la zona principal de una máscara de piel (nivel 1): separa las zonas conectadas,
/// descarta las muy chicas y se queda con la más grande, dando algo más de peso a la del
/// centro, porque es la que el padre encuadró.
ZonaPrincipal elegirZona(List<bool> piel, String metodo, {int n = ladoMascara}) {
  final limpia = _suavizar(piel, n);
  final etiqueta = List<int>.filled(n * n, -1);
  final componentes = <List<int>>[];
  for (var inicio = 0; inicio < n * n; inicio++) {
    if (!limpia[inicio] || etiqueta[inicio] >= 0) continue;
    final celdas = <int>[inicio];
    etiqueta[inicio] = componentes.length;
    for (var k = 0; k < celdas.length; k++) {
      final c = celdas[k], cx = c % n, cy = c ~/ n;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final vx = cx + dx, vy = cy + dy;
          if (vx < 0 || vy < 0 || vx >= n || vy >= n) continue;
          final v = vy * n + vx;
          if (limpia[v] && etiqueta[v] < 0) {
            etiqueta[v] = componentes.length;
            celdas.add(v);
          }
        }
      }
    }
    componentes.add(celdas);
  }

  final grandes = componentes.where((c) => c.length >= _areaMinima * n * n).toList();
  if (grandes.isEmpty) return ZonaPrincipal.completa(metodo: metodo);

  double puntaje(List<int> celdas) {
    var sx = 0.0, sy = 0.0;
    for (final c in celdas) {
      sx += c % n;
      sy += c ~/ n;
    }
    final mx = sx / celdas.length / n - 0.5, my = sy / celdas.length / n - 0.5;
    final distancia = sqrt(mx * mx + my * my) / sqrt(0.5); // 0 en el centro, 1 en la esquina
    return celdas.length * (1 - 0.5 * distancia);
  }

  grandes.sort((a, b) => puntaje(b).compareTo(puntaje(a)));
  final principal = grandes.first;
  final zonas = grandes.where((c) => c.length >= _proporcionOtraZona * principal.length).length;

  var x0 = n, y0 = n, x1 = 0, y1 = 0;
  var sx = 0.0, sy = 0.0;
  final mascara = Uint8List(n * n);
  for (final c in principal) {
    mascara[c] = 1;
    x0 = min(x0, c % n);
    x1 = max(x1, c % n + 1);
    y0 = min(y0, c ~/ n);
    y1 = max(y1, c ~/ n + 1);
    sx += c % n + 0.5;
    sy += c ~/ n + 0.5;
  }
  final lado = min(1.0, max(_ladoMinimo, min(x1 - x0, y1 - y0) / n * _margen));
  final cx = sx / principal.length / n, cy = sy / principal.length / n;
  final x = (cx - lado / 2).clamp(0.0, 1.0 - lado);
  final y = (cy - lado / 2).clamp(0.0, 1.0 - lado);
  return ZonaPrincipal(x: x, y: y, lado: lado, mascara: mascara, zonas: zonas, metodo: metodo);
}

/// Filtro de mayoría 3 × 3: quita puntos sueltos y tapa agujeros chicos (poros, ronchas
/// muy rojas que la regla de color no toma como piel).
List<bool> _suavizar(List<bool> m, int n) {
  final salida = List<bool>.filled(n * n, false);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      var si = 0, total = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final vx = x + dx, vy = y + dy;
          if (vx < 0 || vy < 0 || vx >= n || vy >= n) continue;
          total++;
          if (m[vy * n + vx]) si++;
        }
      }
      salida[y * n + x] = si * 2 > total;
    }
  }
  return salida;
}

/// Nivel 1: máscara de piel por color (la misma regla YCbCr de la validación de la foto).
List<bool> mascaraPorColor(Uint8List jpeg) {
  final chica = img.copyResize(img.decodeJpg(jpeg)!, width: ladoMascara, height: ladoMascara,
      interpolation: img.Interpolation.average);
  return [for (final p in chica) esPiel(p.r, p.g, p.b)];
}

/// Recorta la zona principal del JPEG cuadrado (en otro isolate).
Uint8List recortarZona((Uint8List, double, double, double) datos) {
  final (jpeg, x, y, lado) = datos;
  final foto = img.decodeJpg(jpeg)!;
  final px = (lado * foto.width).round();
  final recorte = img.copyCrop(foto,
      x: (x * foto.width).round(), y: (y * foto.height).round(), width: px, height: px);
  return img.encodeJpg(recorte, quality: 92);
}

/// Nivel 2: segmentación de personas en el celular (MediaPipe Multiclass Selfie Segmenter,
/// Apache 2.0). Separa piel del cuerpo, piel de la cara, pelo, ropa y fondo, así que la
/// zona nunca es la cara ni la ropa. En primeros planos no reconoce a la persona: ahí
/// devuelve null y se usa el nivel 1.
abstract class Segmentador {
  static Segmentador instancia = SegmentadorTflite();

  /// Máscara de piel del cuerpo ([ladoMascara]²) o null si no sirve para esta foto.
  Future<List<bool>?> pielDelCuerpo(Uint8List jpeg);
}

/// Entrada del segmentador: 256 × 256 × 3 en -1..1.
Float32List prepararSegmentador(Uint8List jpeg) {
  final foto = img.copyResize(img.decodeJpg(jpeg)!, width: 256, height: 256);
  final entrada = Float32List(256 * 256 * 3);
  var i = 0;
  for (final p in foto) {
    entrada[i++] = p.r / 127.5 - 1;
    entrada[i++] = p.g / 127.5 - 1;
    entrada[i++] = p.b / 127.5 - 1;
  }
  return entrada;
}

class SegmentadorTflite implements Segmentador {
  static const _asset = 'assets/modelo/segmentador.tflite';
  static const _clasePielCuerpo = 2; // 0 fondo, 1 pelo, 2 piel del cuerpo, 3 cara, 4 ropa, 5 otros
  static const _coberturaMinima = 0.08;

  Interpreter? _interprete;

  @override
  Future<List<bool>?> pielDelCuerpo(Uint8List jpeg) async {
    try {
      _interprete ??= await Interpreter.fromAsset(_asset, options: InterpreterOptions()..threads = 2);
      final entrada = await _enIsolate(prepararSegmentador, jpeg);
      final salida = List<double>.filled(256 * 256 * 6, 0).reshape([1, 256, 256, 6]);
      _interprete!.run(entrada.reshape([1, 256, 256, 3]), salida);
      final filas = salida[0] as List;
      final paso = 256 ~/ ladoMascara;
      final mascara = <bool>[];
      for (var y = 0; y < ladoMascara; y++) {
        final fila = filas[y * paso + paso ~/ 2] as List;
        for (var x = 0; x < ladoMascara; x++) {
          final clases = (fila[x * paso + paso ~/ 2] as List).cast<double>();
          var mejor = 0;
          for (var k = 1; k < clases.length; k++) {
            if (clases[k] > clases[mejor]) mejor = k;
          }
          mascara.add(mejor == _clasePielCuerpo);
        }
      }
      final cobertura = mascara.where((m) => m).length / mascara.length;
      return cobertura >= _coberturaMinima ? mascara : null;
    } catch (error) {
      debugPrint('Segmentador: no disponible ($error)');
      return null;
    }
  }
}

/// En las pruebas de widgets los isolates no avanzan: ahí todo corre en el mismo hilo.
Future<R> _enIsolate<Q, R>(R Function(Q) f, Q datos) async =>
    usarIsolates ? compute(f, datos) : f(datos);

/// Busca la zona principal (nivel 2 y, si no sirve, nivel 1) y devuelve la zona y la
/// imagen que va al modelo: el recorte de la zona, o la foto entera si no hace falta recortar.
Future<(ZonaPrincipal, Uint8List)> zonaParaClasificar(Uint8List jpeg) async {
  try {
    final segmentada = await Segmentador.instancia.pielDelCuerpo(jpeg);
    final zona = segmentada != null
        ? elegirZona(segmentada, 'segmentador')
        : elegirZona(await _enIsolate(mascaraPorColor, jpeg), 'color');
    if (!zona.recortada) return (zona, jpeg);
    return (zona, await _enIsolate(recortarZona, (jpeg, zona.x, zona.y, zona.lado)));
  } catch (error) {
    debugPrint('Zona principal: no se pudo calcular ($error)');
    return (ZonaPrincipal.completa(), jpeg);
  }
}
