import '../data/cuestionario.dart';
import '../data/db.dart';
import '../state/app_state.dart';
import 'api_client.dart';

/// Severidad y recomendaciones (US07, US08).
///
/// - La severidad la calcula SIEMPRE la app, con las reglas de `preguntas.json`.
/// - Las recomendaciones las genera el backend con LLM + RAG (`POST /v1/orientacion`).
///   Si responde 503, no hay conexión o tarda más de 20 s, se usan las
///   recomendaciones locales de `db.json -> recomendacionesLocales`.
class RecomendacionService {
  static String severidad(Episodio episodio, String? clase) =>
      Cuestionario.instancia.severidad(episodio.respuestas, clase);

  /// D41: si la foto no es compatible (y no hay alarma), el respaldo no habla de
  /// cuidados de urticaria: dice lo mismo que la frase fija del backend.
  static Orientacion local(String severidad, {String? clase}) => Orientacion(
    severidad: severidad,
    recomendaciones: Db.instance.recomendacionesLocales(
      clase == 'no_compatible' && severidad != 'alta' ? 'no_compatible' : severidad,
    ),
    origen: 'local',
  );

  /// Pide las recomendaciones al backend; si falla, devuelve las locales.
  static Future<Orientacion> orientar(Episodio episodio, {ResultadoAnalisis? resultado}) async {
    final sev = severidad(episodio, resultado?.clase);
    final remota = await pedirAlBackend(episodio, sev, resultado);
    return remota ?? local(sev, clase: resultado?.clase);
  }

  /// null si el backend no dio una respuesta válida.
  static Future<Orientacion?> pedirAlBackend(Episodio episodio, String severidad, ResultadoAnalisis? resultado) async {
    try {
      final r = await ApiCliente.instancia.orientacion(
        installationId: AppState.instance.installationId,
        severidad: severidad,
        // Con un signo de alarma el modelo no se ejecuta: se envía indeterminado.
        clase: resultado?.clase ?? 'indeterminado',
        confianza: resultado?.confianza ?? 0,
        versionCuestionario: Cuestionario.instancia.version,
        respuestas: episodio.respuestas,
        edadAnios: episodio.edadAnios,
        sexo: episodio.sexo,
      );
      return Orientacion(severidad: severidad, recomendaciones: r.recomendaciones, fuentes: r.fuentes, origen: 'rag');
    } on ApiExcepcion {
      return null;
    }
  }
}
