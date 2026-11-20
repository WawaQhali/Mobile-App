import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wawa_qhali/data/cuestionario.dart';
import 'package:wawa_qhali/services/api_client.dart';
import 'package:wawa_qhali/services/donation_service.dart';
import 'package:wawa_qhali/services/local_storage.dart';
import 'package:wawa_qhali/state/app_state.dart';

const instalacion = '3f2c1d7e-8a4b-4c1e-9f0a-2b6d5e4c3a21';

/// Backend simulado para las donaciones: `respuesta` es el código que da `/v1/donaciones`
/// (0 = sin conexión).
class Backend {
  int respuesta = 202;
  final donaciones = <Map<String, dynamic>>[];
  final clave = jsonDecode(File('test/fixtures/clave_rsa_prueba.json').readAsStringSync()) as Map<String, dynamic>;

  ApiCliente get api => ApiCliente(
        baseUrl: 'http://backend',
        cliente: MockClient((r) async {
          if (respuesta == 0) throw Exception('sin red');
          if (r.url.path == '/v1/claves/publica') return http.Response(jsonEncode(clave), 200);
          if (r.url.path == '/v1/donaciones') {
            if (respuesta == 202) donaciones.add(jsonDecode(r.body) as Map<String, dynamic>);
            return http.Response('{"error":{"codigo":"x","mensaje":"x"}}', respuesta);
          }
          return http.Response('{}', 201);
        }),
      );
}

Map<String, dynamic> paquete(int n) => {'v': 1, 'n': n};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cola de donaciones', () {
    late AlmacenMemoria almacen;
    late ColaDonaciones cola;
    late Backend backend;

    setUp(() {
      almacen = AlmacenMemoria();
      cola = ColaDonaciones(almacen);
      backend = Backend();
    });

    test('sin conexión queda guardada y sale cuando vuelve la conexión', () async {
      backend.respuesta = 0;
      final id = await cola.agregar(paquete(1));
      final r1 = await cola.enviar(backend.api, instalacion);
      expect(r1.enviadas, isEmpty);
      expect(await cola.ids(), [id]);

      backend.respuesta = 202;
      final r2 = await cola.enviar(backend.api, instalacion);
      expect(r2.enviadas, {id});
      expect(await cola.ids(), isEmpty);
      expect(backend.donaciones, [paquete(1)]);
      expect(almacen.archivos.keys.where((k) => k.startsWith('donacion_')), isEmpty);
    });

    test('con el servidor caído (503) o 429 se reintenta después', () async {
      for (final codigo in [503, 429]) {
        backend.respuesta = codigo;
        await cola.agregar(paquete(codigo));
        await cola.enviar(backend.api, instalacion);
        expect(await cola.ids(), isNotEmpty);
        await cola.vaciar();
      }
    });

    test('un rechazo definitivo (403, 422) se descarta y no bloquea a las demás', () async {
      backend.respuesta = 422;
      final malo = await cola.agregar(paquete(1));
      final r = await cola.enviar(backend.api, instalacion);
      expect(r.descartadas, {malo});
      expect(await cola.ids(), isEmpty);
    });

    test('guarda como mucho 10: se descartan las más antiguas', () async {
      final ids = [for (var i = 0; i < 12; i++) await cola.agregar(paquete(i))];
      expect(await cola.ids(), ids.sublist(2));
      expect(await almacen.leerJson('donacion_${ids.first}.json'), isNull);
    });

    test('vaciar borra todo (al revocar el permiso)', () async {
      await cola.agregar(paquete(1));
      await cola.agregar(paquete(2));
      await cola.vaciar();
      expect(await cola.ids(), isEmpty);
      expect(almacen.archivos, isEmpty);
    });
  });

  group('donar sin conexión', () {
    late Backend backend;

    setUp(() async {
      await Cuestionario.cargar();
      backend = Backend();
      ApiCliente.instancia = backend.api;
      AppState.instance
        ..almacen = AlmacenMemoria()
        ..installationId = instalacion
        ..donarFotos = true;
    });

    Episodio episodio() => Episodio(foto: Uint8List.fromList([0xff, 0xd8, 1, 2, 0xff, 0xd9]))
      ..resultado = const ResultadoAnalisis(clase: 'compatible', confianza: 0.9);

    test('con la clave guardada, cifra igual, queda pendiente y se envía al volver', () async {
      await DonacionService.clavePublica(); // se guardó al autorizar
      backend.respuesta = 0;
      final e = episodio();
      AppState.instance.ultimo = e;

      await DonacionService.donarSiCorresponde(e);
      expect(e.donacion, 'pendiente');
      // En el celular solo queda el paquete cifrado: la foto no aparece en claro.
      final archivos = (AppState.instance.almacen as AlmacenMemoria).archivos;
      final guardado = utf8.decode(archivos.entries.firstWhere((a) => a.key.startsWith('donacion_')).value);
      expect(guardado, contains('"alg":"RSA-OAEP-256+A256GCM"'));
      expect(guardado, isNot(contains(base64.encode(e.foto!))));

      backend.respuesta = 202;
      await DonacionService.reintentarPendientes();
      expect(e.donacion, 'enviada');
      expect(backend.donaciones, hasLength(1));
    });

    test('sin clave guardada y sin conexión, no se puede cifrar: fallo', () async {
      backend.respuesta = 0;
      final e = episodio();
      await DonacionService.donarSiCorresponde(e);
      expect(e.donacion, 'fallo');
    });
  });
}
