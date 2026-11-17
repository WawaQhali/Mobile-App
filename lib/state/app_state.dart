import 'package:flutter/foundation.dart';

/// Lo que devuelven el clasificador y la capa de recomendación.
class ResultadoAnalisis {
  const ResultadoAnalisis({
    required this.clase,
    required this.confianza,
    required this.riesgo,
    required this.recomendaciones,
  });

  final String clase; // compatible | no_compatible | indeterminado
  final double confianza; // 0..1
  final String riesgo; // bajo | moderado
  final List<String> recomendaciones;
}

/// Una evaluación: foto + respuestas del cuestionario + resultado.
class Episodio {
  Episodio({this.foto});

  Uint8List? foto;
  final Map<String, String> respuestas = {}; // id de la pregunta -> id de la opción
  String? alarma; // pregunta de alarma respondida con «Sí» (corta el cuestionario)
  bool conRostro = false; // se ve el rostro del menor: la foto no se dona
  bool get donable => foto != null && !conRostro;
  ResultadoAnalisis? resultado;
  final DateTime fecha = DateTime.now();

  bool get hayAlarma => alarma != null;
}

/// Estado global en memoria. Sin login ni persistencia todavía:
/// al cerrar la app se pierde (más adelante: almacenamiento local).
class AppState extends ChangeNotifier {
  AppState._();
  static final instance = AppState._();

  bool terminosAceptados = false;
  bool donarFotos = false;
  bool guardarFoto = true;
  final Map<String, bool> permisos = {'camara': false, 'telefono': false, 'ubicacion': false};

  /// Guía desplegada en la pestaña Guías (se abre desde el carrusel de Inicio).
  String? guiaAbierta = 'alarma';

  Episodio? actual; // evaluación en curso
  Episodio? ultimo; // última evaluación, con resultado o con signo de alarma (US10)

  Episodio get episodio => actual ??= Episodio();

  void aceptarTerminos() {
    terminosAceptados = true;
    notifyListeners();
  }

  void setDonarFotos(bool valor) {
    donarFotos = valor;
    notifyListeners();
  }

  void setGuardarFoto(bool valor) {
    guardarFoto = valor;
    if (!valor) ultimo?.foto = null;
    notifyListeners();
  }

  /// Simulado: el permiso real del sistema lo pedirá permission_handler / image_picker.
  void permitir(String id) {
    permisos[id] = true;
    notifyListeners();
  }

  void abrirGuia(String? id) {
    guiaAbierta = id;
    notifyListeners();
  }

  void nuevoEpisodio(Uint8List? foto) {
    actual = Episodio(foto: foto);
  }

  /// Un «Sí» en una pregunta de alarma: no se analiza la foto, pero el episodio
  /// queda guardado para mostrarle el resumen al médico de emergencia.
  void marcarAlarma(String pregunta) {
    episodio
      ..alarma = pregunta
      ..respuestas[pregunta] = 'si';
    ultimo = episodio;
    notifyListeners();
  }

  void guardarResultado(ResultadoAnalisis resultado) {
    episodio.resultado = resultado;
    ultimo = episodio; // solo se guarda la última, se reemplaza en el siguiente análisis
    notifyListeners();
  }

  void terminarEpisodio() {
    if (!guardarFoto) ultimo?.foto = null;
    actual = null;
    notifyListeners();
  }

  void borrarFoto() {
    ultimo?.foto = null;
    notifyListeners();
  }
}
