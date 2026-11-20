import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

import '../state/app_state.dart';
import 'api_client.dart';
import 'classifier_service.dart';
import 'local_storage.dart';

/// Qué pasó al revisar si hay un modelo nuevo.
enum ResultadoActualizacion { sinModelo, alDia, actualizado, rechazado, sinConexion }

/// Actualiza el modelo sin reinstalar la app (guía del backend, sección 4, Modelos):
/// 1. Pide el manifiesto. Si la versión es la misma que la instalada, no hace nada.
/// 2. Revisa el contrato (entrada RGB, normalización conocida, clases) y descarga el .tflite.
/// 3. Comprueba el tamaño y el `sha256`, y prueba el modelo (sin NaN) antes de instalarlo.
/// 4. Lo guarda en el almacenamiento privado de la app. Si algo falla, sigue el anterior o el
///    del APK: la app nunca se queda sin modelo.
class ActualizadorModelo {
  ActualizadorModelo({
    required this.api,
    required this.almacen,
    this.probar = probarModeloTflite,
    this.versionDelApk = _versionDelApk,
  });

  static const archivoModelo = 'modelo_descargado.tflite';
  static const archivoContrato = 'modelo_descargado.json';
  static const _normalizaciones = {'0_255', '0_1', '-1_1'};

  /// Como mucho una revisión cada 6 horas mientras la app está abierta.
  static const intervalo = Duration(hours: 6);
  static DateTime? _ultimaRevision;

  final ApiCliente api;
  final Almacen almacen;
  final Future<bool> Function(Uint8List modelo, ContratoModelo contrato) probar;
  final Future<String> Function() versionDelApk;

  static Future<String> _versionDelApk() async {
    final json = await rootBundle.loadString('assets/modelo/modelo.json');
    return (jsonDecode(json) as Map<String, dynamic>)['version'] as String;
  }

  /// Lo que usa [ClasificadorTflite]: el modelo descargado y su contrato, si hay uno.
  static Future<(Uint8List, Map<String, dynamic>)?> leerInstalado() async {
    final almacen = AppState.instance.almacen;
    final contrato = await almacen.leerJson(archivoContrato);
    if (contrato == null) return null;
    final modelo = await almacen.leerBytes(archivoModelo);
    return modelo == null ? null : (modelo, contrato);
  }

  /// Al abrir la app y al volver a ella. No bloquea nada ni muestra errores.
  static Future<void> revisarEnSegundoPlano() async {
    final ahora = DateTime.now();
    if (_ultimaRevision != null && ahora.difference(_ultimaRevision!) < intervalo) return;
    _ultimaRevision = ahora;
    try {
      final actualizador = ActualizadorModelo(api: ApiCliente.instancia, almacen: AppState.instance.almacen);
      final resultado = await actualizador.revisar(AppState.instance.installationId);
      debugPrint('Modelo: ${resultado.name}');
    } catch (error) {
      debugPrint('Modelo: no se pudo revisar ($error)');
    }
  }

  Future<String> versionInstalada() async =>
      (await almacen.leerJson(archivoContrato))?['version'] as String? ?? await versionDelApk();

  Future<ResultadoActualizacion> revisar(String installationId) async {
    final Map<String, dynamic>? manifiesto;
    try {
      manifiesto = await api.manifiesto(installationId);
    } on ApiExcepcion {
      return ResultadoActualizacion.sinConexion;
    }
    if (manifiesto == null) return ResultadoActualizacion.sinModelo;
    if (manifiesto['version'] == await versionInstalada()) return ResultadoActualizacion.alDia;

    final ContratoModelo contrato;
    try {
      contrato = ContratoModelo.desdeJson(manifiesto);
      final entrada = manifiesto['entrada'] as Map;
      final valido = entrada['canales'] == 3 &&
          _normalizaciones.contains(contrato.normalizacion) &&
          contrato.ancho > 0 && contrato.ancho <= 1024 &&
          contrato.alto > 0 && contrato.alto <= 1024 &&
          contrato.clases.length >= 2 &&
          contrato.umbral >= 0 && contrato.umbral <= 1;
      if (!valido) return ResultadoActualizacion.rechazado;
    } catch (_) {
      return ResultadoActualizacion.rechazado;
    }

    final Uint8List modelo;
    try {
      modelo = await api.descargar(manifiesto['url'] as String);
    } on ApiExcepcion {
      return ResultadoActualizacion.sinConexion;
    }
    if (modelo.length != manifiesto['tamano'] || sha256Hex(modelo) != manifiesto['sha256']) {
      debugPrint('Modelo descargado: el tamaño o el sha256 no coinciden');
      return ResultadoActualizacion.rechazado;
    }
    if (!await probar(modelo, contrato)) return ResultadoActualizacion.rechazado;

    // Primero el .tflite y al final el contrato: si se corta a la mitad, el contrato viejo
    // no apunta a un modelo a medias (y si no había, se sigue usando el del APK).
    await almacen.borrar(archivoContrato);
    await almacen.escribirBytes(archivoModelo, modelo);
    await almacen.escribirJson(archivoContrato, {
      'version': manifiesto['version'],
      'sha256': manifiesto['sha256'],
      'entrada': manifiesto['entrada'],
      'clases': manifiesto['clases'],
      'umbral_confianza': manifiesto['umbral_confianza'],
    });
    final clasificador = Clasificador.instancia;
    if (clasificador is ClasificadorTflite) clasificador.recargar();
    return ResultadoActualizacion.actualizado;
  }
}

String sha256Hex(Uint8List datos) =>
    SHA256Digest().process(datos).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
