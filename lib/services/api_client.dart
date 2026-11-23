import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Recomendaciones con LLM + RAG que devuelve el backend.
class OrientacionRemota {
  const OrientacionRemota(this.recomendaciones, this.fuentes);

  final List<String> recomendaciones;
  final List<String> fuentes; // IDs de los fragmentos, p. ej. "guia-urticaria#3"
}

class ApiExcepcion implements Exception {
  const ApiExcepcion(this.status, this.codigo);

  final int status; // 0 = sin conexión o tiempo agotado
  final String codigo;

  @override
  String toString() => 'ApiExcepcion($status, $codigo)';
}

/// Cliente del backend de Wawa Qhali. La app se identifica solo con el
/// `X-Installation-Id` (UUID aleatorio de la instalación): no hay cuentas.
///
/// URL: `--dart-define=API_URL=...`. Por defecto, el backend local visto desde el
/// emulador de Android (10.0.2.2 es el localhost de la computadora).
class ApiCliente {
  ApiCliente({required this.baseUrl, http.Client? cliente}) : _cliente = cliente ?? http.Client();

  static ApiCliente instancia = ApiCliente(
    baseUrl: const String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000'),
  );

  final String baseUrl;
  final http.Client _cliente;

  /// El backend corta al LLM a los 15 s; se espera un poco más por la red.
  static const tiempoOrientacion = Duration(seconds: 20);
  static const tiempoNormal = Duration(seconds: 10);

  Map<String, String> _cabeceras(String installationId) => {
    'Content-Type': 'application/json',
    'X-Installation-Id': installationId,
  };

  Future<http.Response> _enviar(Future<http.Response> peticion, Duration tiempo) async {
    try {
      return await peticion.timeout(tiempo);
    } on TimeoutException {
      throw const ApiExcepcion(0, 'tiempo_agotado');
    } on ApiExcepcion {
      rethrow;
    } catch (_) {
      throw const ApiExcepcion(0, 'sin_conexion');
    }
  }

  ApiExcepcion _error(http.Response r) {
    try {
      final error = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['error'] as Map;
      return ApiExcepcion(r.statusCode, error['codigo'] as String);
    } catch (_) {
      return ApiExcepcion(r.statusCode, 'error');
    }
  }

  /// POST /v1/orientacion. Lanza [ApiExcepcion] si no hay respuesta válida
  /// (503, 422, sin conexión...): la app usa entonces su respaldo local.
  Future<OrientacionRemota> orientacion({
    required String installationId,
    required String severidad,
    required String clase,
    required double confianza,
    required String versionCuestionario,
    required Map<String, Object> respuestas,
    String? textoLibre,
    int? edadAnios,
    String? sexo,
  }) async {
    final r = await _enviar(
      _cliente.post(
        Uri.parse('$baseUrl/v1/orientacion'),
        headers: _cabeceras(installationId),
        body: jsonEncode({
          'severidad': severidad,
          'clase': clase,
          'confianza': confianza,
          'version_cuestionario': versionCuestionario,
          'respuestas': respuestas,
          if (textoLibre != null && textoLibre.isNotEmpty) 'texto_libre': textoLibre,
          'edad_anios': ?edadAnios,
          'sexo': ?sexo,
        }),
      ),
      tiempoOrientacion,
    );
    if (r.statusCode != 200) throw _error(r);
    final datos = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return OrientacionRemota(
      (datos['recomendaciones'] as List).cast<String>(),
      (datos['fuentes'] as List).cast<String>(),
    );
  }

  /// POST /v1/autorizaciones: el padre acepta donar sus fotos.
  Future<void> autorizar(String installationId, String versionTexto) async {
    final r = await _enviar(
      _cliente.post(
        Uri.parse('$baseUrl/v1/autorizaciones'),
        headers: _cabeceras(installationId),
        body: jsonEncode({'installation_id': installationId, 'version_texto': versionTexto}),
      ),
      tiempoNormal,
    );
    if (r.statusCode != 201) throw _error(r);
  }

  /// GET /v1/claves/publica: clave RSA del servidor (JWK) para cifrar la donación.
  Future<Map<String, dynamic>> clavePublica(String installationId) async {
    final r = await _enviar(
      _cliente.get(Uri.parse('$baseUrl/v1/claves/publica'), headers: _cabeceras(installationId)),
      tiempoNormal,
    );
    if (r.statusCode != 200) throw _error(r);
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// POST /v1/donaciones: el paquete ya cifrado (sección 6.2). Responde 202.
  Future<void> donar(String installationId, Map<String, dynamic> paquete) async {
    final r = await _enviar(
      _cliente.post(
        Uri.parse('$baseUrl/v1/donaciones'),
        headers: _cabeceras(installationId),
        body: jsonEncode(paquete),
      ),
      const Duration(seconds: 30),
    );
    if (r.statusCode != 202) throw _error(r);
  }

  /// GET /v1/modelos/manifiesto: el modelo publicado (versión, sha256, tamaño, enlace
  /// temporal y contrato). null si todavía no hay ninguno (404 `sin_modelo`).
  Future<Map<String, dynamic>?> manifiesto(String installationId) async {
    final r = await _enviar(
      _cliente.get(Uri.parse('$baseUrl/v1/modelos/manifiesto'), headers: _cabeceras(installationId)),
      tiempoNormal,
    );
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw _error(r);
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// Descarga el .tflite desde el enlace temporal (SAS de 5 minutos) del manifiesto.
  Future<Uint8List> descargar(String url) async {
    final r = await _enviar(_cliente.get(Uri.parse(url)), const Duration(minutes: 2));
    if (r.statusCode != 200) throw ApiExcepcion(r.statusCode, 'descarga');
    return r.bodyBytes;
  }

  /// DELETE /v1/autorizaciones/{id}: revoca y borra las fotos aún no usadas.
  /// 404 cuenta como éxito: nunca se había autorizado.
  Future<void> revocar(String installationId) async {
    final r = await _enviar(
      _cliente.delete(Uri.parse('$baseUrl/v1/autorizaciones/$installationId'), headers: _cabeceras(installationId)),
      tiempoNormal,
    );
    if (r.statusCode != 204 && r.statusCode != 404) throw _error(r);
  }
}
