import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Almacenamiento local de la app. Solo guarda:
/// - `config.json`: installation_id y preferencias.
/// - `ultima_evaluacion.json` + `ultima_foto.jpg`: la ÚLTIMA evaluación (la foto, las
///   respuestas, la severidad y las recomendaciones con sus fuentes). Cada evaluación
///   nueva reemplaza a la anterior (guía del backend, sección 1 y 5.4).
abstract class Almacen {
  Future<Map<String, dynamic>?> leerJson(String nombre);
  Future<void> escribirJson(String nombre, Map<String, dynamic> datos);
  Future<Uint8List?> leerBytes(String nombre);
  Future<void> escribirBytes(String nombre, Uint8List datos);
  Future<void> borrar(String nombre);
}

/// Archivos en el directorio de soporte de la app: privado, nunca en la galería.
class AlmacenArchivos implements Almacen {
  Directory? _carpeta;

  Future<File> _archivo(String nombre) async {
    _carpeta ??= await getApplicationSupportDirectory();
    return File('${_carpeta!.path}/$nombre');
  }

  @override
  Future<Map<String, dynamic>?> leerJson(String nombre) async {
    final bytes = await leerBytes(nombre);
    if (bytes == null) return null;
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return null; // archivo dañado: se ignora
    }
  }

  @override
  Future<void> escribirJson(String nombre, Map<String, dynamic> datos) =>
      escribirBytes(nombre, Uint8List.fromList(utf8.encode(jsonEncode(datos))));

  @override
  Future<Uint8List?> leerBytes(String nombre) async {
    final archivo = await _archivo(nombre);
    return await archivo.exists() ? archivo.readAsBytes() : null;
  }

  @override
  Future<void> escribirBytes(String nombre, Uint8List datos) async {
    final archivo = await _archivo(nombre);
    final temporal = File('${archivo.path}.tmp');
    await temporal.writeAsBytes(datos, flush: true);
    await temporal.rename(archivo.path); // reemplazo atómico
  }

  @override
  Future<void> borrar(String nombre) async {
    final archivo = await _archivo(nombre);
    if (await archivo.exists()) await archivo.delete();
  }
}

/// En memoria, para las pruebas.
class AlmacenMemoria implements Almacen {
  final Map<String, Uint8List> archivos = {};

  @override
  Future<Map<String, dynamic>?> leerJson(String nombre) async {
    final bytes = archivos[nombre];
    return bytes == null ? null : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  @override
  Future<void> escribirJson(String nombre, Map<String, dynamic> datos) async =>
      archivos[nombre] = Uint8List.fromList(utf8.encode(jsonEncode(datos)));

  @override
  Future<Uint8List?> leerBytes(String nombre) async => archivos[nombre];

  @override
  Future<void> escribirBytes(String nombre, Uint8List datos) async => archivos[nombre] = datos;

  @override
  Future<void> borrar(String nombre) async => archivos.remove(nombre);
}
