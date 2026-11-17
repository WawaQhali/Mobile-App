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
  Json get demo => _data['demo'] as Json;
  Json get emergencia => _data['emergencia'] as Json;

  List<Json> get permisos => _lista('permisos');
  List<Json> get validaciones => _lista('validaciones');
  List<Json> get guias => _lista('guias');
  List<Json> get centros => _lista('centros');

  /// Cuestionario único: primero las preguntas de alarma, luego los síntomas.
  List<Json> get preguntas => ((_data['preguntas'] as Json)['lista'] as List).cast<Json>();
  int get ladoMinimoFotoPx => (_data['foto'] as Json)['ladoMinimoPx'] as int;

  Json resultado(String clase) => (_data['resultados'] as Json)[clase] as Json;
  Json riesgo(String id) => (_data['riesgos'] as Json)[id] as Json;

  /// Opciones de una pregunta; las de alarma siempre son Sí / No.
  List<Json> opciones(Json pregunta) => pregunta['tipo'] == 'alarma'
      ? const [
          {'id': 'si', 'label': 'Sí'},
          {'id': 'no', 'label': 'No'},
        ]
      : (pregunta['opciones'] as List).cast<Json>();

  Json opcion(Json pregunta, String id) => opciones(pregunta).firstWhere((o) => o['id'] == id);

  List<Json> _lista(String key) => (_data[key] as List).cast<Json>();
}
