import '../data/db.dart';
import '../state/app_state.dart';
import 'classifier_service.dart';

/// Nivel de riesgo y recomendación (US07, US08).
///
/// El riesgo sale de reglas fijas sobre los síntomas: si alguna respuesta tiene
/// `"riesgo": "moderado"` en db.json, el riesgo es moderado (US20).
/// Las recomendaciones salen de `db.json -> resultados` (SIMULADO: aquí irá el RAG).
class RecomendacionService {
  static Future<ResultadoAnalisis> recomendar(Prediccion prediccion, Episodio episodio) async {
    final db = Db.instance;
    final moderado = db.preguntas.any((p) {
      final r = episodio.respuestas[p['id']];
      return r != null && db.opcion(p, r)['riesgo'] == 'moderado';
    });
    final info = db.resultado(prediccion.clase);

    return ResultadoAnalisis(
      clase: prediccion.clase,
      confianza: prediccion.confianza,
      riesgo: moderado ? 'moderado' : 'bajo',
      recomendaciones: [
        ...(info['recomendaciones'] as List).cast<String>(),
        db.app['recomendacionAlarma'] as String,
      ],
    );
  }
}
