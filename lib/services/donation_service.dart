import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../data/cuestionario.dart';
import '../state/app_state.dart';
import 'api_client.dart';
import 'classifier_service.dart';

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

/// Dona la foto de una evaluación si corresponde: el padre aceptó donar, hay foto
/// real, no se ve un rostro y el modelo dio un resultado.
class DonacionService {
  static bool corresponde(Episodio e) =>
      AppState.instance.donarFotos && e.donable && e.resultado != null && !e.hayAlarma;

  static Future<void> donarSiCorresponde(Episodio e) async {
    if (!corresponde(e)) return;
    final estado = AppState.instance;
    estado.marcarDonacion(e, 'enviando');
    try {
      final api = ApiCliente.instancia;
      final clave = ClavePublicaJwk.desdeJson(await api.clavePublica(estado.installationId));
      final paquete = cifrarDonacion(
        clave: clave,
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
      await api.donar(estado.installationId, paquete);
      estado.marcarDonacion(e, 'enviada');
    } on Object {
      estado.marcarDonacion(e, 'fallo');
    }
  }
}
