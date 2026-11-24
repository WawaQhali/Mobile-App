import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';
import 'package:wawa_qhali/data/cuestionario.dart';
import 'package:wawa_qhali/services/classifier_service.dart';
import 'package:wawa_qhali/services/donation_service.dart';
import 'package:wawa_qhali/services/location_service.dart';

Map<String, dynamic> claveDePrueba() =>
    jsonDecode(File('test/fixtures/clave_rsa_prueba.json').readAsStringSync()) as Map<String, dynamic>;

BigInt entero(String b64url) =>
    base64Url.decode(base64Url.normalize(b64url)).fold(BigInt.zero, (a, b) => (a << 8) | BigInt.from(b));

/// Lo que hace el servicio de reentrenamiento (sección 6.4), con la clave de prueba.
Map<String, dynamic> descifrar(Map<String, dynamic> paquete, String installationId) {
  final k = claveDePrueba();
  final privada = RSAPrivateKey(entero(k['n'] as String), entero(k['d'] as String), entero(k['p'] as String),
      entero(k['q'] as String));
  final oaep = OAEPEncoding.withSHA256(RSAEngine())..init(false, PrivateKeyParameter<RSAPrivateKey>(privada));
  final claveAes = oaep.process(base64.decode(paquete['clave_cifrada'] as String));
  final gcm = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(claveAes), 128, base64.decode(paquete['nonce'] as String),
          Uint8List.fromList(utf8.encode(installationId))),
    );
  return jsonDecode(utf8.decode(gcm.process(base64.decode(paquete['datos'] as String)))) as Map<String, dynamic>;
}

void main() {
  group('cifrado de la donación (sección 6)', () {
    const instalacion = '3f2c1d7e-8a4b-4c1e-9f0a-2b6d5e4c3a21';
    final contenido = {
      'imagen_jpeg': base64.encode([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9]),
      'etiqueta_preliminar': {'clase': 'compatible', 'confianza': 0.91},
    };

    Map<String, dynamic> cifrar() => cifrarDonacion(
          clave: ClavePublicaJwk.desdeJson(claveDePrueba()),
          installationId: instalacion,
          contenido: contenido,
        );

    test('el paquete tiene el formato que valida el backend', () {
      final p = cifrar();
      expect(p['v'], 1);
      expect(p['alg'], 'RSA-OAEP-256+A256GCM');
      expect(p['kid'], claveDePrueba()['kid']);
      expect(base64.decode(p['clave_cifrada'] as String).length, 384);
      expect(base64.decode(p['nonce'] as String).length, 12);
      expect(base64.decode(p['datos'] as String).length, greaterThanOrEqualTo(16));
    });

    test('ida y vuelta: se descifra igual con la clave privada', () {
      expect(descifrar(cifrar(), instalacion), contenido);
    });

    test('con otro installation_id el descifrado falla (AAD)', () {
      expect(() => descifrar(cifrar(), '00000000-0000-4000-8000-000000000000'), throwsA(anything));
    });

    test('cada donación usa una clave y un nonce nuevos', () {
      final a = cifrar(), b = cifrar();
      expect(a['nonce'], isNot(b['nonce']));
      expect(a['clave_cifrada'], isNot(b['clave_cifrada']));
    });
  });

  group('salida del modelo', () {
    final contrato = ContratoModelo.desdeJson({
      'version': 'x',
      'entrada': {'ancho': 224, 'alto': 224, 'canales': 3, 'normalizacion': '0_255'},
      'clases': ['compatible', 'no_compatible'],
      'umbral_confianza': 0.6,
    });

    test('NaN (el modelo actual dañado) da indeterminado y salida inválida', () {
      final p = interpretarSalida([double.nan, double.nan], contrato);
      expect((p.clase, p.salidaValida), ('indeterminado', false));
    });

    test('sin seguridad suficiente da indeterminado', () {
      final p = interpretarSalida([0.4996, 0.5004], contrato);
      expect((p.clase, p.salidaValida), ('indeterminado', true));
      expect(p.confianza, closeTo(0.5004, 1e-9));
    });

    test('con seguridad, la clase según el orden del contrato', () {
      expect(interpretarSalida([0.9, 0.1], contrato).clase, 'compatible');
      expect(interpretarSalida([0.2, 0.8], contrato).clase, 'no_compatible');
    });

    test('la normalización sale del contrato', () {
      ContratoModelo con(String n) => ContratoModelo.desdeJson({
            'version': 'x',
            'entrada': {'ancho': 1, 'alto': 1, 'normalizacion': n},
            'clases': ['a', 'b'],
            'umbral_confianza': 0.5,
          });
      expect(con('0_255').normalizar(255), 255);
      expect(con('0_1').normalizar(255), 1);
      expect(con('-1_1').normalizar(0), -1);
    });
  });

  group('centros de salud (OpenStreetMap)', () {
    const aqui = (lat: -12.0800, lng: -76.9400);
    final respuesta = {
      'elements': [
        {'type': 'node', 'lat': -12.0900, 'lon': -76.9400, 'tags': {'amenity': 'clinic', 'name': 'Clínica B'}},
        {
          'type': 'way',
          'center': {'lat': -12.0810, 'lon': -76.9400},
          'tags': {'amenity': 'hospital', 'name': 'Hospital A', 'phone': '+51 1 000 0000'},
        },
        {'type': 'node', 'lat': -12.0850, 'lon': -76.9400, 'tags': {'amenity': 'doctors'}}, // sin nombre
        {'type': 'node', 'lat': -12.0811, 'lon': -76.9400, 'tags': {'healthcare': 'hospital', 'name': 'hospital a'}},
        {
          'type': 'node',
          'lat': -12.1000,
          'lon': -76.9400,
          'tags': {'amenity': 'hospital', 'emergency': 'no', 'name': 'Hospital sin emergencia'},
        },
      ],
    };

    test('ordena por distancia, quita repetidos y los sin nombre, y clasifica', () {
      final centros = CentrosService.interpretar(respuesta, aqui);
      expect(centros.map((c) => c.nombre), ['Hospital A', 'Clínica B', 'Hospital sin emergencia']);
      expect(centros.map((c) => c.tipo), ['emergencia', 'centro', 'centro']);
      expect(centros.first.telefono, '+51 1 000 0000');
      expect(centros.first.distanciaTexto, '111 m');
      expect(centros[1].distanciaTexto, '1,1 km');
    });

    test('los hospitales se piden aparte y sin tope (el tope dejaba fuera al más cercano)', () {
      final q = CentrosService.consulta(-12.08, -76.941);
      final salidas = q.split('out center tags');
      expect(salidas, hasLength(3)); // dos salidas
      expect(salidas[0], contains('amenity=hospital'));
      expect(salidas[0], isNot(contains('amenity=doctors')));
      expect(salidas[1], startsWith(';')); // la de hospitales, sin número de tope
    });

    test('una clínica con emergency=yes cuenta como emergencia', () {
      final centros = CentrosService.interpretar({
        'elements': [
          {'lat': -12.0810, 'lon': -76.9400, 'tags': {'amenity': 'clinic', 'emergency': 'yes', 'name': 'Clínica con emergencia'}},
          {'lat': -12.0820, 'lon': -76.9400, 'tags': {'amenity': 'clinic', 'name': 'Clínica sin emergencia'}},
        ],
      }, aqui);
      expect(centros.map((c) => c.tipo), ['emergencia', 'centro']);
    });

    test('la consulta redondea la ubicación (~100 m) antes de enviarla', () async {
      late String enviado;
      final servicio = CentrosService(
        servidores: ['https://prueba.invalid/api/interpreter'],
        cliente: MockClient((r) async {
          enviado = Uri.decodeQueryComponent(r.body);
          return http.Response.bytes(utf8.encode(jsonEncode(respuesta)), 200);
        }),
      );
      final centros = await servicio.cercanos((lat: -12.0801234, lng: -76.9406789));
      expect(enviado, contains('-12.08,-76.941'));
      expect(enviado, isNot(contains('0801234')));
      expect(centros, hasLength(3));
    });
  });

  test('si Overpass falla, usa el buscador de OpenStreetMap (Nominatim)', () async {
    final pedidos = <Uri>[];
    final servicio = CentrosService(
      servidores: ['https://overpass.invalid/api/interpreter'],
      cliente: MockClient((r) async {
        pedidos.add(r.url);
        if (r.url.host == 'overpass.invalid') return http.Response('saturado', 504);
        final q = r.url.queryParameters['q'];
        final lista = q == 'hospital'
            ? [
                {'name': 'Hospital A', 'lat': '-12.0810', 'lon': '-76.9400', 'category': 'amenity', 'type': 'hospital'},
                {'name': 'Parque', 'lat': '-12.0810', 'lon': '-76.9400', 'category': 'leisure', 'type': 'park'},
              ]
            : [
                {'name': 'Clínica B', 'lat': '-12.0900', 'lon': '-76.9400', 'category': 'amenity', 'type': 'clinic'},
              ];
        return http.Response.bytes(utf8.encode(jsonEncode(lista)), 200);
      }),
    );
    final centros = await servicio.cercanos((lat: -12.0800, lng: -76.9400));
    expect(centros.map((c) => (c.nombre, c.tipo)), [('Hospital A', 'emergencia'), ('Clínica B', 'centro')]);
    expect(pedidos.where((u) => u.host == 'nominatim.openstreetmap.org').first.queryParameters['bounded'], '1');
  });

  test('el «por qué» de la severidad sale de las reglas del cuestionario', () {
    final c = Cuestionario.desdeJson(jsonDecode(File('assets/preguntas.json').readAsStringSync()) as Map<String, dynamic>);
    final base = <String, Object>{'tiempo_evolucion': 'menos_24h', 'extension': 'una_zona', 'muy_alergico': false};
    expect(c.motivosSeveridad(base, 'compatible'), isEmpty);
    expect(c.motivosSeveridad({...base, 'extension': 'varias_zonas'}, 'compatible'),
        ['¿Dónde están las ronchas? En varias partes del cuerpo']);
    expect(c.motivosSeveridad(base, 'indeterminado'), ['El análisis de la foto no fue concluyente.']);
    expect(c.motivosSeveridad(base, 'no_compatible').single, startsWith('La foto no muestra lesiones compatibles'));
    expect(c.motivosSeveridad({...base, 'angustia': true}, 'compatible').single, startsWith('Signo de alarma'));
  });
}
