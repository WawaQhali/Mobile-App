import 'dart:math';

import 'package:flutter/foundation.dart';

import '../services/api_client.dart';
import '../services/donation_service.dart';
import '../services/image_processing.dart';
import '../services/local_storage.dart';
import '../services/permissions_service.dart';
import '../services/zona_principal.dart';

/// Lo que devuelve el clasificador (el modelo corre en el celular).
class ResultadoAnalisis {
  const ResultadoAnalisis({required this.clase, required this.confianza});

  final String clase; // compatible | no_compatible | indeterminado
  final double confianza; // 0..1
}

/// Severidad y recomendaciones. `origen` dice de dónde salieron:
/// `rag` = backend (LLM + guías clínicas), `local` = respaldo de la app.
class Orientacion {
  const Orientacion({
    required this.severidad,
    required this.recomendaciones,
    this.fuentes = const [],
    required this.origen,
  });

  final String severidad; // leve | moderada | alta
  final List<String> recomendaciones;
  final List<String> fuentes;
  final String origen; // rag | local

  bool get delBackend => origen == 'rag';

  Map<String, dynamic> aJson() => {
    'severidad': severidad,
    'recomendaciones': recomendaciones,
    'fuentes': fuentes,
    'origen': origen,
  };

  static Orientacion desdeJson(Map<String, dynamic> j) => Orientacion(
    severidad: j['severidad'] as String,
    recomendaciones: (j['recomendaciones'] as List).cast<String>(),
    fuentes: (j['fuentes'] as List).cast<String>(),
    origen: j['origen'] as String,
  );
}

/// Una evaluación: foto + respuestas del cuestionario + resultado + orientación.
class Episodio {
  Episodio({this.foto, DateTime? fecha}) : fecha = fecha ?? DateTime.now();

  /// Recorte cuadrado de 1024 px sin EXIF (lo único que se guarda y se dona).
  Uint8List? foto;

  /// La foto tal como salió de la cámara, solo mientras se valida. Nunca se guarda.
  Uint8List? fotoOriginal;

  /// Métricas y recorte que la cámara ya calculó (luz y nitidez revisadas). Solo en memoria.
  FotoProcesada? procesada;

  /// Datos del niño o la niña, que se piden antes del cuestionario (1 a 4 años).
  /// Se envían al backend (orientación y donación) y salen en el resumen.
  int? edadAnios;
  String? sexo; // femenino | masculino

  /// Donación de esta foto: null (no se intentó), 'enviando', 'enviada', 'pendiente'
  /// (cifrada en la cola, se envía cuando haya conexión) o 'fallo'.
  String? donacion;
  final Map<String, Object> respuestas = {}; // id -> true/false o id de la opción
  String? alarma; // pregunta de riesgo respondida con «Sí» (corta el cuestionario)
  bool conRostro = false; // se ve el rostro del menor: la foto no se dona
  bool get donable => foto != null && !conRostro;
  ResultadoAnalisis? resultado;

  /// Zona de piel que evaluó el modelo (si se veían varias partes del cuerpo). Solo en memoria.
  ZonaPrincipal? zona;
  Orientacion? orientacion;
  final DateTime fecha;

  bool get hayAlarma => alarma != null;
  String? get severidad => hayAlarma ? 'alta' : orientacion?.severidad;

  Map<String, dynamic> aJson() => {
    'fecha': fecha.toIso8601String(),
    'edad_anios': edadAnios,
    'sexo': sexo,
    'respuestas': respuestas,
    'alarma': alarma,
    if (resultado != null) 'resultado': {'clase': resultado!.clase, 'confianza': resultado!.confianza},
    if (orientacion != null) 'orientacion': orientacion!.aJson(),
  };

  static Episodio desdeJson(Map<String, dynamic> j, Uint8List? foto) {
    final e = Episodio(foto: foto, fecha: DateTime.parse(j['fecha'] as String))
      ..alarma = j['alarma'] as String?
      ..edadAnios = j['edad_anios'] as int?
      ..sexo = j['sexo'] as String?;
    e.respuestas.addAll((j['respuestas'] as Map).cast<String, Object>());
    final r = j['resultado'] as Map<String, dynamic>?;
    if (r != null) {
      e.resultado = ResultadoAnalisis(clase: r['clase'] as String, confianza: (r['confianza'] as num).toDouble());
    }
    final o = j['orientacion'] as Map<String, dynamic>?;
    if (o != null) e.orientacion = Orientacion.desdeJson(o);
    return e;
  }
}

/// Estado global. Se guarda en el celular (ver [Almacen]): las preferencias, el
/// installation_id y solo la ÚLTIMA evaluación, que se reemplaza en la siguiente.
class AppState extends ChangeNotifier {
  AppState._();
  static final instance = AppState._();

  static const _config = 'config.json';
  static const _evaluacion = 'ultima_evaluacion.json';
  static const _foto = 'ultima_foto.jpg';

  /// Versión del texto de autorización que el padre acepta en la pantalla de donación.
  static const versionTextoDonacion = 'v1';

  Almacen almacen = AlmacenArchivos();

  late String installationId;
  bool terminosAceptados = false;
  bool donarFotos = false;
  bool guardarFoto = true;
  final Map<String, bool> permisos = {'camara': false, 'telefono': false, 'ubicacion': false};

  /// Guía desplegada en la pestaña Guías (se abre desde el carrusel de Inicio).
  String? guiaAbierta = 'alarma';

  Episodio? actual; // evaluación en curso
  Episodio? ultimo; // última evaluación, con resultado o con signo de alarma (US10)

  Episodio get episodio => actual ??= Episodio();

  /// Lee lo guardado. Si es la primera vez, crea el installation_id.
  Future<void> cargar() async {
    final config = await almacen.leerJson(_config) ?? {};
    installationId = config['installation_id'] as String? ?? _nuevoUuid();
    terminosAceptados = config['terminos_aceptados'] as bool? ?? false;
    donarFotos = config['donar_fotos'] as bool? ?? false;
    guardarFoto = config['guardar_foto'] as bool? ?? true;
    actual = null;
    ultimo = null;
    final evaluacion = await almacen.leerJson(_evaluacion);
    if (evaluacion != null) {
      try {
        ultimo = Episodio.desdeJson(evaluacion, await almacen.leerBytes(_foto));
      } catch (_) {
        ultimo = null; // formato viejo o dañado
      }
    }
    if (config['installation_id'] == null) await _guardarConfig();
    notifyListeners();
  }

  /// UUID v4 aleatorio, en minúsculas (también es el AAD del cifrado, sección 6.2).
  static String _nuevoUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> _guardarConfig() => almacen.escribirJson(_config, {
    'installation_id': installationId,
    'terminos_aceptados': terminosAceptados,
    'donar_fotos': donarFotos,
    'guardar_foto': guardarFoto,
  });

  Future<void> _guardarUltimo() async {
    final e = ultimo;
    if (e == null) {
      await almacen.borrar(_evaluacion);
      await almacen.borrar(_foto);
      return;
    }
    await almacen.escribirJson(_evaluacion, e.aJson());
    if (e.foto != null && guardarFoto) {
      await almacen.escribirBytes(_foto, e.foto!);
    } else {
      await almacen.borrar(_foto);
    }
  }

  void aceptarTerminos() {
    terminosAceptados = true;
    _guardarConfig();
    notifyListeners();
  }

  /// Registra o revoca la autorización en el backend. Devuelve un mensaje de error
  /// para mostrar, o null si salió bien. Si falla, la preferencia no cambia.
  Future<String?> setDonarFotos(bool valor) async {
    try {
      if (valor) {
        await ApiCliente.instancia.autorizar(installationId, versionTextoDonacion);
        // Se guarda la clave pública ahora, para poder cifrar luego aunque no haya conexión.
        await DonacionService.clavePublica().then((_) {}, onError: (_) {});
      } else {
        await ApiCliente.instancia.revocar(installationId);
        await DonacionService.cola.vaciar(); // nada pendiente sale después de revocar
      }
    } on ApiExcepcion {
      return valor
          ? 'No pudimos registrar tu permiso. Inténtalo luego desde Ajustes.'
          : 'No pudimos quitar el permiso. Revisa tu conexión e inténtalo de nuevo.';
    }
    donarFotos = valor;
    await _guardarConfig();
    notifyListeners();
    return null;
  }

  void setGuardarFoto(bool valor) {
    guardarFoto = valor;
    if (!valor) ultimo?.foto = null;
    _guardarConfig();
    _guardarUltimo();
    notifyListeners();
  }

  /// Pide el permiso con el diálogo del sistema (Android).
  Future<ResultadoPermiso> permitir(String id) async {
    final resultado = await Permisos.instancia.solicitar(id);
    permisos[id] = resultado == ResultadoPermiso.concedido;
    notifyListeners();
    return resultado;
  }

  /// Lee el estado real de los permisos: al abrir la app y al volver a ella
  /// (por ejemplo, después de cambiarlos en los ajustes del celular).
  Future<void> actualizarPermisos() async {
    for (final id in permisos.keys.toList()) {
      permisos[id] = await Permisos.instancia.concedido(id);
    }
    notifyListeners();
  }

  void abrirGuia(String? id) {
    guiaAbierta = id;
    notifyListeners();
  }

  /// Empieza una evaluación con la foto recién tomada. La cámara ya revisó su luz y
  /// su nitidez ([procesada]); falta la validación de resolución, piel y rostro.
  void nuevoEpisodio(Uint8List original, {FotoProcesada? procesada}) {
    actual = Episodio()
      ..fotoOriginal = original
      ..procesada = procesada;
  }

  /// Edad y sexo del niño o la niña (pantalla anterior al cuestionario).
  void guardarDatosNino({required int edadAnios, required String sexo}) {
    assert(edadAnios >= edadMinima && edadAnios <= edadMaxima);
    episodio
      ..edadAnios = edadAnios
      ..sexo = sexo;
  }

  /// Wawa Qhali es para niños y niñas de 1 a 4 años.
  static const edadMinima = 1;
  static const edadMaxima = 4;

  void marcarDonacion(Episodio e, String estado) {
    e.donacion = estado;
    notifyListeners();
  }

  /// Un «Sí» de riesgo: no se analiza la foto. El episodio queda guardado (severidad
  /// alta) para mostrarle el resumen al médico de emergencia.
  Future<void> marcarAlarma(String pregunta) async {
    final e = episodio
      ..alarma = pregunta
      ..respuestas[pregunta] = true
      ..resultado = null
      ..orientacion = null;
    ultimo = e;
    notifyListeners();
    await _guardarUltimo();
  }

  /// Recomendaciones que llegaron después (p. ej. las del backend en emergencia).
  Future<void> guardarOrientacion(Episodio e, Orientacion orientacion) async {
    e.orientacion = orientacion;
    notifyListeners();
    if (identical(e, ultimo)) await _guardarUltimo();
  }

  Future<void> guardarResultado(ResultadoAnalisis resultado, Orientacion orientacion) async {
    episodio
      ..resultado = resultado
      ..orientacion = orientacion;
    ultimo = episodio; // solo se guarda la última: reemplaza a la anterior
    notifyListeners();
    await _guardarUltimo();
  }

  void terminarEpisodio() {
    if (!guardarFoto) ultimo?.foto = null;
    actual = null;
    _guardarUltimo();
    notifyListeners();
  }

  void borrarFoto() {
    ultimo?.foto = null;
    _guardarUltimo();
    notifyListeners();
  }
}
