import 'dart:convert';

import 'package:flutter/services.dart';

typedef CuestionarioJson = Map<String, dynamic>;

class Opcion {
  const Opcion(this.id, this.texto);

  final String id;
  final String texto;
}

class Pregunta {
  const Pregunta({
    required this.id,
    required this.tipo,
    required this.respuesta,
    required this.texto,
    this.opciones = const [],
  });

  Pregunta.desdeJson(CuestionarioJson j)
    : id = j['id'] as String,
      tipo = j['tipo'] as String,
      respuesta = j['respuesta'] as String,
      texto = j['texto'] as String,
      opciones = [
        for (final o in (j['opciones'] as List? ?? const []).cast<CuestionarioJson>())
          Opcion(o['id'] as String, o['texto'] as String),
      ];

  final String id;
  final String tipo; // riesgo | normal
  final String respuesta; // si_no | opcion
  final String texto;
  final List<Opcion> opciones;

  bool get esRiesgo => tipo == 'riesgo';
  bool get esSiNo => respuesta == 'si_no';

  /// Botones de la pregunta: (texto, valor). Sí/No valen `true`/`false`; una opción, su id.
  List<(String, Object)> get botones =>
      esSiNo ? const [('Sí', true), ('No', false)] : [for (final o in opciones) (o.texto, o.id)];

  String textoRespuesta(Object valor) {
    if (esSiNo) return valor == true ? 'Sí' : 'No';
    return opciones.firstWhere((o) => o.id == valor, orElse: () => Opcion('$valor', '$valor')).texto;
  }
}

/// Cuestionario configurable: `assets/preguntas.json` es una copia EXACTA de
/// `backend/app/modules/orientacion/preguntas.json`. Si cambia, se actualizan los dos.
class Cuestionario {
  Cuestionario.desdeJson(CuestionarioJson j)
    : version = j['version'] as String,
      mensajeEmergencia = j['mensaje_emergencia'] as String,
      preguntas = [for (final p in (j['preguntas'] as List).cast<CuestionarioJson>()) Pregunta.desdeJson(p)],
      reglasModerada = [
        for (final r in (j['reglas_moderada'] as List).cast<CuestionarioJson>()) (r['pregunta'] as String, r['valor'] as Object),
      ];

  static late Cuestionario instancia;

  static Future<void> cargar() async {
    final raw = await rootBundle.loadString('assets/preguntas.json');
    instancia = Cuestionario.desdeJson(jsonDecode(raw) as CuestionarioJson);
  }

  final String version;
  final String mensajeEmergencia;
  final List<Pregunta> preguntas;
  final List<(String, Object)> reglasModerada;

  Pregunta pregunta(String id) => preguntas.firstWhere((p) => p.id == id);

  /// D42 (opción A): la app pregunta si se ven ronchas. NO es parte de `preguntas.json`
  /// (el backend valida el cuestionario v1) y su respuesta no se envía en `respuestas`:
  /// solo corrige el resultado del modelo en el celular (ver [claseFinal]).
  static const preguntaRonchas = Pregunta(
    id: 've_ronchas',
    tipo: 'app',
    respuesta: 'opcion',
    texto: '¿Ves ronchas o manchas rojas en la piel de tu wawa?',
    opciones: [Opcion('si', 'Sí'), Opcion('no', 'No'), Opcion('no_se', 'No estoy seguro')],
  );

  /// Lo que ve el papá o la mamá en pantalla: las del cuestionario v1 y, al final, la de ronchas.
  List<Pregunta> get preguntasEnPantalla => [...preguntas, preguntaRonchas];

  /// Reglas del cuestionario v1, en este orden:
  /// algún «sí» de riesgo → alta; alguna regla moderada, o modelo indeterminado o
  /// no compatible (D41) → moderada; si no, leve. El backend NO calcula la severidad:
  /// la recibe de la app (y rechaza «no_compatible» con «leve»).
  String severidad(Map<String, Object> respuestas, String? clase) {
    final hayRiesgo = preguntas.any((p) => p.esRiesgo && respuestas[p.id] == true);
    if (hayRiesgo) return 'alta';
    final reglaModerada = reglasModerada.any((r) => respuestas[r.$1] == r.$2);
    if (reglaModerada || clase == 'indeterminado' || clase == 'no_compatible') return 'moderada';
    return 'leve';
  }

  /// Por qué salió esa severidad: las reglas que se cumplieron, en palabras.
  List<String> motivosSeveridad(Map<String, Object> respuestas, String? clase, {bool sinRonchas = false}) {
    final riesgos = [
      for (final p in preguntas)
        if (p.esRiesgo && respuestas[p.id] == true) 'Signo de alarma: ${p.texto} Sí',
    ];
    if (riesgos.isNotEmpty) return riesgos;
    return [
      for (final (id, valor) in reglasModerada)
        if (respuestas[id] == valor) '${pregunta(id).texto} ${pregunta(id).textoRespuesta(valor)}',
      if (clase == 'indeterminado') 'El análisis de la foto no fue concluyente.',
      if (clase == 'no_compatible' && sinRonchas)
        'Indicaste que no ves ronchas en la piel: conviene que un médico la evalúe.'
      else if (clase == 'no_compatible')
        'La foto no muestra lesiones compatibles con urticaria: conviene que la vea un médico.',
    ];
  }
}

/// D42 (opción A): si el papá o la mamá dice que NO ve ronchas, el resultado nunca es
/// «compatible» ni queda indeterminado, aunque el modelo se equivoque con piel sana:
/// pasa a «no compatible» (severidad moderada y consulta médica, D41).
/// Con «Sí» o «No estoy seguro» manda el modelo.
String claseFinal(String claseModelo, String? veRonchas) =>
    veRonchas == 'no' && claseModelo != 'no_compatible' ? 'no_compatible' : claseModelo;
