// Prueba de conectividad con un backend REAL (no simulado).
// Solo corre si se pasa la URL; si no, se omite:
//   flutter test test/integracion_backend_test.dart --dart-define=API_URL=http://localhost:8000
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wawa_qhali/data/cuestionario.dart';
import 'package:wawa_qhali/services/api_client.dart';

const apiUrl = String.fromEnvironment('API_URL');

void main() {
  final omitir = apiUrl.isEmpty ? 'Falta --dart-define=API_URL=...' : null;
  late ApiCliente api;
  late Cuestionario cuestionario;
  final instalacion = _uuid();

  setUpAll(() async {
    api = ApiCliente(baseUrl: apiUrl);
    // Sin binding de Flutter: se lee el mismo archivo que va en el APK.
    final raw = File('assets/preguntas.json').readAsStringSync();
    cuestionario = Cuestionario.desdeJson(jsonDecode(raw) as Map<String, dynamic>);
  });

  Map<String, Object> respuestas({bool riesgo = false}) => {
        for (final p in cuestionario.preguntas)
          if (p.esRiesgo) p.id: false else p.id: p.esSiNo ? false : p.opciones.first.id,
        if (riesgo) 'hinchazon_cara': true,
      };

  test('orientacion: recomendaciones con fuentes para cada severidad', () async {
    for (final severidad in ['leve', 'moderada']) {
      final r = await api.orientacion(
        installationId: instalacion,
        severidad: severidad,
        clase: 'compatible',
        confianza: 0.9,
        versionCuestionario: cuestionario.version,
        respuestas: respuestas(),
      );
      expect(r.recomendaciones, isNotEmpty, reason: severidad);
      expect(r.fuentes, isNotEmpty, reason: severidad);
    }
    final alta = await api.orientacion(
      installationId: instalacion,
      severidad: 'alta',
      clase: 'indeterminado',
      confianza: 0,
      versionCuestionario: cuestionario.version,
      respuestas: {'dificultad_respirar': false, 'hinchazon_cara': true},
    );
    expect(alta.recomendaciones.first.toLowerCase(), contains('emergencia'));
  }, skip: omitir);

  test('orientacion: el backend rechaza una severidad incoherente (422)', () async {
    expect(
      () => api.orientacion(
        installationId: instalacion,
        severidad: 'leve',
        clase: 'compatible',
        confianza: 0.9,
        versionCuestionario: cuestionario.version,
        respuestas: respuestas(riesgo: true),
      ),
      throwsA(isA<ApiExcepcion>().having((e) => e.status, 'status', 422)),
    );
  }, skip: omitir);

  test('autorizar y revocar la donación', () async {
    await api.autorizar(instalacion, 'v1');
    await api.revocar(instalacion);
    await api.revocar(instalacion); // idempotente
  }, skip: omitir);

  test('sin backend, el cliente falla rápido con sin_conexion', () async {
    final caido = ApiCliente(baseUrl: 'http://127.0.0.1:9');
    expect(
      () => caido.autorizar(instalacion, 'v1'),
      throwsA(isA<ApiExcepcion>().having((e) => e.status, 'status', 0)),
    );
  }, skip: omitir);
}

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
