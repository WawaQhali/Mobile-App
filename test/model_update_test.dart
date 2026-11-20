import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wawa_qhali/services/api_client.dart';
import 'package:wawa_qhali/services/classifier_service.dart';
import 'package:wawa_qhali/services/local_storage.dart';
import 'package:wawa_qhali/services/model_update_service.dart';

const instalacion = '3f2c1d7e-8a4b-4c1e-9f0a-2b6d5e4c3a21';
final modelo = Uint8List.fromList(List.generate(4096, (i) => i % 251));

Map<String, dynamic> manifiesto({String version = '1.1.0', String? sha, int? tamano, Map? entrada}) => {
      'version': version,
      'sha256': sha ?? sha256Hex(modelo),
      'tamano': tamano ?? modelo.length,
      'url': 'https://almacen.blob/modelos/1.1.0/modelo.tflite?sas',
      'entrada': entrada ?? {'ancho': 224, 'alto': 224, 'canales': 3, 'normalizacion': '0_255'},
      'clases': ['compatible', 'no_compatible'],
      'umbral_confianza': 0.6,
    };

class Escenario {
  Map<String, dynamic>? publicado = manifiesto();
  bool sinConexion = false;
  bool modeloSano = true;
  final descargas = <Uri>[];
  final almacen = AlmacenMemoria();

  ActualizadorModelo get actualizador => ActualizadorModelo(
        api: ApiCliente(
          baseUrl: 'http://backend',
          cliente: MockClient((r) async {
            if (sinConexion) throw Exception('sin red');
            if (r.url.path == '/v1/modelos/manifiesto') {
              expect(r.headers['X-Installation-Id'], instalacion);
              return publicado == null
                  ? http.Response('{"error":{"codigo":"sin_modelo","mensaje":"x"}}', 404)
                  : http.Response(jsonEncode(publicado), 200);
            }
            descargas.add(r.url);
            return http.Response.bytes(modelo, 200);
          }),
        ),
        almacen: almacen,
        probar: (bytes, contrato) async => modeloSano,
        versionDelApk: () async => '2026-11-14-mobilenetv3',
      );

  Future<ResultadoActualizacion> revisar() => actualizador.revisar(instalacion);
}

void main() {
  test('sin modelo publicado (404) sigue el del APK', () async {
    final e = Escenario()..publicado = null;
    expect(await e.revisar(), ResultadoActualizacion.sinModelo);
    expect(e.almacen.archivos, isEmpty);
  });

  test('un modelo nuevo se descarga, se verifica y se instala con su contrato', () async {
    final e = Escenario();
    expect(await e.revisar(), ResultadoActualizacion.actualizado);
    expect(e.almacen.archivos[ActualizadorModelo.archivoModelo], modelo);
    final contrato = ContratoModelo.desdeJson((await e.almacen.leerJson(ActualizadorModelo.archivoContrato))!);
    expect(contrato.version, '1.1.0');
    expect(contrato.clases, ['compatible', 'no_compatible']);
    expect(await e.actualizador.versionInstalada(), '1.1.0');
  });

  test('si ya tiene esa versión no descarga nada', () async {
    final e = Escenario();
    await e.revisar();
    e.descargas.clear();
    expect(await e.revisar(), ResultadoActualizacion.alDia);
    expect(e.descargas, isEmpty);
  });

  test('si el sha256 o el tamaño no coinciden, no se instala', () async {
    for (final m in [manifiesto(sha: 'a' * 64), manifiesto(tamano: 10)]) {
      final e = Escenario()..publicado = m;
      expect(await e.revisar(), ResultadoActualizacion.rechazado);
      expect(e.almacen.archivos, isEmpty);
    }
  });

  test('un modelo dañado (NaN) no reemplaza al que funciona', () async {
    final e = Escenario();
    await e.revisar(); // instala 1.1.0
    e
      ..publicado = manifiesto(version: '1.2.0')
      ..modeloSano = false;
    expect(await e.revisar(), ResultadoActualizacion.rechazado);
    expect(await e.actualizador.versionInstalada(), '1.1.0');
  });

  test('un contrato que la app no sabe usar se rechaza sin descargar', () async {
    for (final entrada in [
      {'ancho': 224, 'alto': 224, 'canales': 1, 'normalizacion': '0_255'},
      {'ancho': 224, 'alto': 224, 'canales': 3, 'normalizacion': 'z_score'},
      {'ancho': 4096, 'alto': 224, 'canales': 3, 'normalizacion': '0_1'},
    ]) {
      final e = Escenario()..publicado = manifiesto(entrada: entrada);
      expect(await e.revisar(), ResultadoActualizacion.rechazado);
      expect(e.descargas, isEmpty);
    }
  });

  test('sin conexión no cambia nada', () async {
    final e = Escenario()..sinConexion = true;
    expect(await e.revisar(), ResultadoActualizacion.sinConexion);
    expect(e.almacen.archivos, isEmpty);
  });
}
