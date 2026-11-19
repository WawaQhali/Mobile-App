import 'dart:convert';

import 'package:flutter/services.dart';

typedef Json = Map<String, dynamic>;

/// Contenido estático de la app, leído de `assets/db.json`.
/// Hace de backend mientras no exista uno (contenido clínico, centros, etc.).
class Db {
  Db._(this._data);

  static late Db instance;
  final Json _data;

  static Future<void> cargar() async {
    final raw = await rootBundle.loadString('assets/db.json');
    instance = Db._(jsonDecode(raw) as Json);
  }

  Json get app => _data['app'] as Json;
  Json get emergencia => _data['emergencia'] as Json;

  List<Json> get permisos => _lista('permisos');
  List<Json> get validaciones => _lista('validaciones');
  List<Json> get guias => _lista('guias');

  /// Umbrales de la validación de la foto (provisionales, sección 13 de la guía).
  Json get foto => _data['foto'] as Json;

  Json resultado(String clase) => (_data['resultados'] as Json)[clase] as Json;

  /// leve | moderada | alta -> label, nivel (1 a 3) y descripción.
  Json severidad(String id) => (_data['severidades'] as Json)[id] as Json;

  /// Respaldo local cuando el backend no da recomendaciones.
  List<String> recomendacionesLocales(String severidad) =>
      ((_data['recomendacionesLocales'] as Json)[severidad] as List).cast<String>();

  List<Json> _lista(String key) => (_data[key] as List).cast<Json>();
}
