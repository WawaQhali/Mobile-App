import 'dart:typed_data';

import '../data/db.dart';

class Prediccion {
  const Prediccion(this.clase, this.confianza);

  final String clase; // compatible | no_compatible | indeterminado
  final double confianza;
}

/// Clasificador de la lesión (US06).
///
/// SIMULADO: devuelve lo que diga `db.json -> demo`.
/// Aquí irá la inferencia local con TensorFlow Lite (tflite_flutter + modelo .tflite).
class ClasificadorService {
  /// Por debajo de este umbral no se arriesga un resultado: «indeterminado».
  static const umbralConfianza = 0.6;

  static Future<Prediccion> clasificar(Uint8List? foto) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    final demo = Db.instance.demo;
    final confianza = (demo['confianza'] as num).toDouble();
    final clase = confianza < umbralConfianza ? 'indeterminado' : demo['resultado'] as String;
    return Prediccion(clase, confianza);
  }
}
