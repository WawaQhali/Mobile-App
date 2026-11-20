import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../data/cuestionario.dart';
import '../state/app_state.dart';
import 'api_client.dart';
import 'classifier_service.dart';
import 'local_storage.dart';

/// Clave pública del servidor (JWK) que devuelve GET /v1/claves/publica.
class ClavePublicaJwk {
  const ClavePublicaJwk({required this.n, required this.e, required this.kid});

  final BigInt n;
  final BigInt e;
  final String kid;

  static BigInt _entero(String b64url) {
    final bytes = base64Url.decode(base64Url.normalize(b64url));
    return bytes.fold(BigInt.zero, (acc, b) => (acc << 8) | BigInt.from(b));
  }

  static ClavePublicaJwk desdeJson(Map<String, dynamic> j) =>
      ClavePublicaJwk(n: _entero(j['n'] as String), e: _entero(j['e'] as String), kid: j['kid'] as String);
}

/// Cifrado híbrido de la foto donada (guía del backend, sección 6.2):
/// 1. JSON en claro: recorte JPEG 1024 px en base64 + etiqueta preliminar.
/// 2. Clave AES aleatoria de 32 bytes y nonce de 12 bytes.
/// 3. AES-256-GCM con el installation_id como AAD (no se puede reasignar a otra instalación).
/// 4. La clave AES se cifra con RSA-OAEP-256 (SHA-256 en el hash Y en MGF1).
/// El backend no puede descifrar: solo el servicio de reentrenamiento, con Key Vault.
Map<String, dynamic> cifrarDonacion({
  required ClavePublicaJwk clave,
  required String installationId,
  required Map<String, dynamic> contenido,
  Random? azar,
}) {
  final aleatorio = azar ?? Random.secure();
  Uint8List bytes(int n) => Uint8List.fromList(List.generate(n, (_) => aleatorio.nextInt(256)));

  final claveAes = bytes(32);
  final nonce = bytes(12);
  final claro = Uint8List.fromList(utf8.encode(jsonEncode(contenido)));

  final gcm = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(claveAes), 128, nonce, Uint8List.fromList(utf8.encode(installationId))));
  final datos = gcm.process(claro); // texto cifrado + tag de 16 bytes

  // OAEPEncoding.withSHA256 usa SHA-256 también en MGF1, como espera Key Vault.
  final oaep = OAEPEncoding.withSHA256(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(RSAPublicKey(clave.n, clave.e)));
  final claveCifrada = oaep.process(claveAes);
  claveAes.fillRange(0, claveAes.length, 0); // se borra la copia en claro

  return {
    'v': 1,
    'kid': clave.kid,
    'alg': 'RSA-OAEP-256+A256GCM',
    'clave_cifrada': base64.encode(claveCifrada),
    'nonce': base64.encode(nonce),
    'datos': base64.encode(datos),
  };
}

/// Cola local de donaciones. Guarda el paquete YA CIFRADO (solo Key Vault puede abrirlo),
/// así que en el celular nunca queda una copia en claro extra de la foto. Se reintenta al
/// abrir la app, al volver a ella y después de cada donación nueva.
class ColaDonaciones {
  ColaDonaciones(this.almacen);

  static const _indice = 'cola_donaciones.json';
  static const maximo = 10; // si se acumulan más, se descartan las más antiguas

  final Almacen almacen;
  Future<ResultadoEnvio>? _envioEnCurso;

  String _archivo(String id) => 'donacion_$id.json';

  Future<List<String>> ids() async =>
      ((await almacen.leerJson(_indice))?['ids'] as List?)?.cast<String>() ?? <String>[];

  Future<void> _guardarIds(List<String> ids) => almacen.escribirJson(_indice, {'ids': ids});

  Future<String> agregar(Map<String, dynamic> paquete) async {
    final r = Random.secure();
    final id = List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await almacen.escribirJson(_archivo(id), paquete);
    final lista = [...await ids(), id];
    while (lista.length > maximo) {
      await almacen.borrar(_archivo(lista.removeAt(0)));
    }
    await _guardarIds(lista);
    return id;
  }

  /// Al revocar el permiso: no queda nada pendiente de enviar.
  Future<void> vaciar() async {
    for (final id in await ids()) {
      await almacen.borrar(_archivo(id));
    }
    await almacen.borrar(_indice);
  }

  /// Envía en orden. Sin conexión, 429 o error del servidor: se detiene y deja el resto
  /// para después. Otro 4xx (sin autorización, formato, clave vieja): reintentar no lo
  /// arregla, así que se descarta.
  Future<ResultadoEnvio> enviar(ApiCliente api, String installationId) =>
      _envioEnCurso ??= _enviar(api, installationId).whenComplete(() => _envioEnCurso = null);

  Future<ResultadoEnvio> _enviar(ApiCliente api, String installationId) async {
    final resultado = ResultadoEnvio();
    for (final id in await ids()) {
      final paquete = await almacen.leerJson(_archivo(id));
      if (paquete != null) {
        try {
          await api.donar(installationId, paquete);
          resultado.enviadas.add(id);
        } on ApiExcepcion catch (e) {
          if (e.status == 0 || e.status == 429 || e.status >= 500) break;
          resultado.descartadas.add(id);
        }
      }
      await almacen.borrar(_archivo(id));
      final quedan = (await ids())..remove(id);
      await _guardarIds(quedan);
    }
    return resultado;
  }
}

class ResultadoEnvio {
  final enviadas = <String>{};
  final descartadas = <String>{};
}

/// Dona la foto de una evaluación si corresponde: el padre aceptó donar, hay foto
/// real, no se ve un rostro y el modelo dio un resultado.
class DonacionService {
  static const _clave = 'clave_publica.json';

  static bool corresponde(Episodio e) =>
      AppState.instance.donarFotos && e.donable && e.resultado != null && !e.hayAlarma;

  static ColaDonaciones? _cola;
  static Almacen? _almacenDeLaCola;

  /// La cola usa el almacén actual de la app (en las pruebas, uno en memoria).
  static ColaDonaciones get cola {
    final almacen = AppState.instance.almacen;
    if (_cola == null || !identical(_almacenDeLaCola, almacen)) {
      _cola = ColaDonaciones(almacen);
      _almacenDeLaCola = almacen;
    }
    return _cola!;
  }

  /// La clave pública del servidor. Se guarda para poder cifrar sin conexión; con
  /// conexión se renueva siempre, por si se rotó.
  static Future<ClavePublicaJwk> clavePublica() async {
    final estado = AppState.instance;
    try {
      final jwk = await ApiCliente.instancia.clavePublica(estado.installationId);
      await estado.almacen.escribirJson(_clave, jwk);
      return ClavePublicaJwk.desdeJson(jwk);
    } on ApiExcepcion {
      final guardada = await estado.almacen.leerJson(_clave);
      if (guardada == null) rethrow;
      return ClavePublicaJwk.desdeJson(guardada);
    }
  }

  static Future<void> donarSiCorresponde(Episodio e) async {
    if (!corresponde(e)) return;
    final estado = AppState.instance;
    estado.marcarDonacion(e, 'enviando');
    final String id;
    try {
      final paquete = cifrarDonacion(
        clave: await clavePublica(),
        installationId: estado.installationId,
        contenido: {
          'imagen_jpeg': base64.encode(e.foto!),
          'etiqueta_preliminar': {
            'clase': e.resultado!.clase,
            'confianza': e.resultado!.confianza,
            'respuestas': e.respuestas,
            'version_modelo': Clasificador.instancia.versionModelo,
            'version_cuestionario': Cuestionario.instancia.version,
          },
        },
      );
      id = await cola.agregar(paquete);
    } on Object {
      estado.marcarDonacion(e, 'fallo'); // sin clave guardada y sin conexión
      return;
    }
    final resultado = await cola.enviar(ApiCliente.instancia, estado.installationId);
    estado.marcarDonacion(
      e,
      resultado.enviadas.contains(id)
          ? 'enviada'
          : resultado.descartadas.contains(id)
              ? 'fallo'
              : 'pendiente',
    );
  }

  /// Envía lo que quedó pendiente (sin conexión la vez anterior).
  static Future<void> reintentarPendientes() async {
    final estado = AppState.instance;
    if (!estado.donarFotos) return;
    try {
      final resultado = await cola.enviar(ApiCliente.instancia, estado.installationId);
      final e = estado.ultimo;
      if (e != null && e.donacion == 'pendiente' && resultado.enviadas.isNotEmpty && (await cola.ids()).isEmpty) {
        estado.marcarDonacion(e, 'enviada');
      }
    } on Object catch (error) {
      debugPrint('Donaciones: no se pudo reintentar ($error)');
    }
  }
}
