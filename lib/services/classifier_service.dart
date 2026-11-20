import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'model_update_service.dart';

class Prediccion {
  const Prediccion(this.clase, this.confianza, {this.salidaValida = true});

  final String clase; // compatible | no_compatible | indeterminado
  final double confianza;

  /// false si el modelo devolvió NaN o valores imposibles (modelo dañado).
  final bool salidaValida;
}

/// Contrato del modelo (`assets/modelo/modelo.json`), igual que el manifiesto del backend.
class ContratoModelo {
  ContratoModelo.desdeJson(Map<String, dynamic> j)
      : version = j['version'] as String,
        ancho = (j['entrada'] as Map)['ancho'] as int,
        alto = (j['entrada'] as Map)['alto'] as int,
        normalizacion = (j['entrada'] as Map)['normalizacion'] as String,
        clases = (j['clases'] as List).cast<String>(),
        umbral = (j['umbral_confianza'] as num).toDouble();

  final String version;
  final int ancho;
  final int alto;
  final String normalizacion; // 0_255 | 0_1 | -1_1
  final List<String> clases;
  final double umbral;

  double normalizar(num v) => switch (normalizacion) {
        '0_1' => v / 255,
        '-1_1' => v / 127.5 - 1,
        _ => v.toDouble(),
      };
}

/// Clasificador de la lesión (US06). Corre en el celular: la foto no sale de ahí.
abstract class Clasificador {
  static Clasificador instancia = ClasificadorTflite(leerDescargado: ActualizadorModelo.leerInstalado);

  String get versionModelo;
  Future<Prediccion> clasificar(Uint8List jpeg);
}

/// Prepara la entrada del modelo: [1, alto, ancho, 3] en float32, normalizada
/// según el contrato. Se hace en otro isolate.
Float32List prepararEntrada((Uint8List, int, int, String) datos) {
  final (jpeg, ancho, alto, normalizacion) = datos;
  final contrato = ContratoModelo.desdeJson({
    'version': '',
    'entrada': {'ancho': ancho, 'alto': alto, 'normalizacion': normalizacion},
    'clases': <String>[],
    'umbral_confianza': 0,
  });
  final imagen = img.copyResize(img.decodeJpg(jpeg)!, width: ancho, height: alto);
  final entrada = Float32List(ancho * alto * 3);
  var i = 0;
  for (final p in imagen) {
    entrada[i++] = contrato.normalizar(p.r);
    entrada[i++] = contrato.normalizar(p.g);
    entrada[i++] = contrato.normalizar(p.b);
  }
  return entrada;
}

/// Interpreta la salida del modelo. Si hay NaN o no suma ~1 (softmax), el modelo
/// está dañado: indeterminado. Si la mejor clase no llega al umbral: indeterminado.
Prediccion interpretarSalida(List<double> salida, ContratoModelo contrato) {
  final valida = salida.length == contrato.clases.length &&
      salida.every((v) => v.isFinite && v >= 0 && v <= 1) &&
      (salida.fold<double>(0, (a, b) => a + b) - 1).abs() < 0.05;
  if (!valida) return const Prediccion('indeterminado', 0, salidaValida: false);
  final mejor = salida.indexOf(salida.reduce(max));
  final confianza = salida[mejor];
  if (confianza < contrato.umbral) return Prediccion('indeterminado', confianza);
  return Prediccion(contrato.clases[mejor], confianza);
}

/// Ejecuta un .tflite sobre una imagen gris y dice si su salida es válida (sin NaN, suma 1).
/// Antes de usar un modelo descargado se prueba con esto: así no se instala uno dañado.
Future<bool> probarModeloTflite(Uint8List modelo, ContratoModelo contrato) async {
  Interpreter? interprete;
  try {
    interprete = Interpreter.fromBuffer(modelo);
    final entrada = Float32List(contrato.ancho * contrato.alto * 3)..fillRange(0, contrato.ancho * contrato.alto * 3, contrato.normalizar(128));
    final salida = [List<double>.filled(contrato.clases.length, 0)];
    interprete.run(entrada.reshape([1, contrato.alto, contrato.ancho, 3]), salida);
    return interpretarSalida(salida.first, contrato).salidaValida;
  } catch (error) {
    debugPrint('Modelo descargado: no se pudo probar ($error)');
    return false;
  } finally {
    interprete?.close();
  }
}

class ClasificadorTflite implements Clasificador {
  /// Lee el modelo descargado (ver [ActualizadorModelo]); si no hay, usa el del APK.
  ClasificadorTflite({this.leerDescargado});

  final Future<(Uint8List, Map<String, dynamic>)?> Function()? leerDescargado;

  ContratoModelo? _contrato;
  Interpreter? _interprete;
  bool _recargar = false;

  @override
  String get versionModelo => _contrato?.version ?? 'sin-modelo';

  /// Llega un modelo nuevo: se carga en la próxima clasificación.
  void recargar() => _recargar = true;

  Future<void> _cargar() async {
    if (_interprete != null && !_recargar) return;
    _interprete?.close();
    _interprete = null;
    _recargar = false;
    final opciones = InterpreterOptions()..threads = 2;
    try {
      final descargado = await leerDescargado?.call();
      if (descargado != null) {
        _contrato = ContratoModelo.desdeJson(descargado.$2);
        _interprete = Interpreter.fromBuffer(descargado.$1, options: opciones);
        return;
      }
    } catch (error) {
      debugPrint('Modelo descargado: no se pudo cargar, se usa el del APK ($error)');
    }
    final json = await rootBundle.loadString('assets/modelo/modelo.json');
    _contrato = ContratoModelo.desdeJson(jsonDecode(json) as Map<String, dynamic>);
    _interprete = await Interpreter.fromAsset('assets/modelo/modelo.tflite', options: opciones);
  }

  @override
  Future<Prediccion> clasificar(Uint8List jpeg) async {
    try {
      await _cargar();
      final c = _contrato!;
      final entrada = await compute(prepararEntrada, (jpeg, c.ancho, c.alto, c.normalizacion));
      final salida = [List<double>.filled(c.clases.length, 0)];
      _interprete!.run(entrada.reshape([1, c.alto, c.ancho, 3]), salida);
      final prediccion = interpretarSalida(salida.first, c);
      if (!prediccion.salidaValida) debugPrint('Modelo: salida inválida ${salida.first}');
      return prediccion;
    } catch (error) {
      debugPrint('Modelo: no se pudo ejecutar ($error)');
      return const Prediccion('indeterminado', 0, salidaValida: false);
    }
  }
}
