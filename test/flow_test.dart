import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wawa_qhali/app.dart';
import 'package:wawa_qhali/data/cuestionario.dart';
import 'package:wawa_qhali/data/db.dart';
import 'package:wawa_qhali/screens/child_data.dart';
import 'package:wawa_qhali/services/api_client.dart';
import 'package:wawa_qhali/services/classifier_service.dart';
import 'package:wawa_qhali/services/image_processing.dart';
import 'package:wawa_qhali/services/local_storage.dart';
import 'package:wawa_qhali/services/permissions_service.dart';
import 'package:wawa_qhali/services/recommendation_service.dart';
import 'package:wawa_qhali/services/validation_service.dart';
import 'package:wawa_qhali/state/app_state.dart';

Future<void> tocar(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> esperar(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Onboarding completo hasta Inicio y el flujo hasta la pantalla de preguntas.
Future<void> hastaCuestionario(WidgetTester tester) async {
  await tester.pumpWidget(const WawaQhaliApp());
  await tester.pumpAndSettle();

  await tocar(tester, find.text('Comenzar'));
  await tocar(tester, find.byType(Checkbox));
  await tocar(tester, find.text('Continuar'));
  expect(find.text('¿Nos ayudas a mejorar Wawa Qhali?'), findsOneWidget);

  await tocar(tester, find.text('Ahora no'));
  await tocar(tester, find.text('Permitir').first);
  await tocar(tester, find.text('Continuar'));
  expect(find.text('Guías rápidas'), findsOneWidget);

  await tocar(tester, find.byTooltip('Evaluar lesión'));
  expect(find.text('Centra la lesión en el círculo'), findsOneWidget);

  // En el test no hay cámara: se usa la foto de muestra.
  await tocar(tester, find.bySemanticsLabel('Tomar foto'));
  await esperar(tester, 1000);
  expect(find.text('Tu foto se ve bien'), findsOneWidget);

  await tocar(tester, find.text('Usar esta foto'));
  tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
  await tester.pumpAndSettle();

  // Antes del cuestionario: sexo y edad de la wawa (solo 1 a 4 años).
  expect(find.text('Cuéntanos sobre tu wawa'), findsOneWidget);
  await responderDatosNino(tester);
  expect(find.text('Pregunta 1 de 15'), findsOneWidget);
}

/// Niña de 3 años: la rueda empieza en «1 año» y se baja dos posiciones.
Future<void> responderDatosNino(WidgetTester tester) async {
  final continuar = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar'));
  expect(continuar.onPressed, isNull, reason: 'sin elegir niña o niño no se puede seguir');
  await tocar(tester, find.text('Niña'));
  await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -96));
  await tester.pumpAndSettle();
  await tocar(tester, find.text('Continuar'));
  await tester.pumpAndSettle();
}

/// Las 8 de riesgo con «No», las 6 normales (severidad leve) y «¿Ves ronchas?» (D42).
Future<void> responderSinAlarma(WidgetTester tester, {String veRonchas = 'Sí'}) async {
  for (var i = 0; i < 8; i++) {
    await tocar(tester, find.text('No'));
  }
  for (final r in ['Sí', 'Sí', 'Menos de un día', 'En una sola parte del cuerpo', 'No sé', 'No', veRonchas]) {
    await tocar(tester, find.text(r));
  }
}

/// Backend simulado: guarda las peticiones y responde lo que diga `orientacion`.
class BackendFalso {
  final peticiones = <http.Request>[];
  Map<String, dynamic> clavePublica = const {};
  http.Response orientacion = http.Response(
    jsonEncode({
      'recomendaciones': ['Recomendación del RAG de prueba.', 'Si empeora, acude a emergencia.'],
      'fuentes': ['guia-de-prueba#2'],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  MockClient get cliente => MockClient((r) async {
        peticiones.add(r);
        if (r.url.path == '/v1/orientacion') return orientacion;
        if (r.url.path == '/v1/autorizaciones') return http.Response('{}', 201);
        if (r.url.path == '/v1/claves/publica') return http.Response(jsonEncode(clavePublica), 200);
        if (r.url.path == '/v1/donaciones') return http.Response('{"id":"x","estado":"en_cuarentena"}', 202);
        return http.Response('{}', 204);
      });

  Map<String, dynamic> cuerpo(String ruta) =>
      jsonDecode(peticiones.lastWhere((p) => p.url.path == ruta).body) as Map<String, dynamic>;
}

/// El modelo TFLite no corre en las pruebas de la computadora: responde lo que se le diga.
class ClasificadorFalso implements Clasificador {
  Prediccion prediccion = const Prediccion('compatible', 0.91);

  @override
  String get versionModelo => 'prueba';

  @override
  bool get modeloDelApk => false;

  @override
  Future<Prediccion> clasificar(Uint8List jpeg) async => prediccion;
}

class SinRostro implements DetectorRostros {
  @override
  Future<bool> hayRostro(Uint8List jpeg) async => false;
}

/// Simula el diálogo de Android: responde lo que diga `respuesta`.
class PermisosFalsos implements Permisos {
  ResultadoPermiso respuesta = ResultadoPermiso.concedido;
  final pedidos = <String>[];
  bool ajustesAbiertos = false;

  @override
  Future<bool> concedido(String id) async => false;

  @override
  Future<ResultadoPermiso> solicitar(String id) async {
    pedidos.add(id);
    return respuesta;
  }

  @override
  Future<void> abrirAjustes() async => ajustesAbiertos = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/image_picker'),
    (_) async => throw PlatformException(code: 'no_camera'),
  );

  late BackendFalso backend;
  late AlmacenMemoria almacen;
  late PermisosFalsos permisos;
  late ClasificadorFalso clasificador;

  setUp(() async {
    await Db.cargar();
    await Cuestionario.cargar();
    backend = BackendFalso();
    ApiCliente.instancia = ApiCliente(baseUrl: 'http://backend', cliente: backend.cliente);
    usarIsolates = false; // en pruebas de widgets los isolates no avanzan
    clasificador = ClasificadorFalso();
    Clasificador.instancia = clasificador;
    DetectorRostros.instancia = SinRostro();
    permisos = PermisosFalsos();
    Permisos.instancia = permisos;
    almacen = AlmacenMemoria();
    final s = AppState.instance..almacen = almacen;
    await s.cargar();
    s.permisos.updateAll((_, _) => false);
  });

  testWidgets('flujo completo: recomendaciones del RAG y resumen guardado', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await hastaCuestionario(tester);
    await responderSinAlarma(tester);

    await esperar(tester, 3000);
    expect(find.text('Análisis listo'), findsOneWidget);

    // Lo que se mandó al backend: severidad calculada en la app y respuestas v1.
    final enviado = backend.cuerpo('/v1/orientacion');
    expect(enviado['severidad'], 'leve');
    expect(enviado['version_cuestionario'], 'v1');
    expect(enviado['respuestas']['dificultad_respirar'], false);
    expect(enviado['respuestas']['tiempo_evolucion'], 'menos_24h');
    expect(enviado['edad_anios'], 3);
    expect(enviado['sexo'], 'femenino');
    expect(backend.peticiones.last.headers['X-Installation-Id'], AppState.instance.installationId);

    await tocar(tester, find.text('Ver resultado'));
    expect(find.text('Sí, compatible'), findsOneWidget);
    expect(find.text('Leve'), findsOneWidget);
    expect(find.text('Recomendación del RAG de prueba.'), findsOneWidget);
    expect(find.textContaining('Según guías clínicas validadas: guia de prueba'), findsOneWidget);
    // Qué modelo dio el resultado y con qué confianza.
    expect(find.text('Modelo prueba · 91 %'), findsOneWidget);

    await tocar(tester, find.text('Resumen para el médico'));
    expect(find.text('Niña · 3 años'), findsOneWidget);
    // Una sola lista de respuestas, sin separar signos de alarma de síntomas.
    expect(find.text('Respuestas'), findsOneWidget);
    expect(find.text('Signos de alarma'), findsNothing);
    expect(find.text('Síntomas'), findsNothing);
    expect(find.text('¿Dónde están las ronchas?'), findsOneWidget);
    expect(find.text('En una sola parte del cuerpo'), findsOneWidget);
    // El resumen también muestra las recomendaciones (la pantalla de resultado sigue debajo).
    expect(find.text('Recomendación del RAG de prueba.'), findsNWidgets(2));

    // Quedó guardada en el celular: al reabrir la app se recupera tal cual.
    // Se guardó el recorte de 1024 px de la foto (en la prueba, la foto de muestra).
    expect(almacen.archivos.keys, containsAll(['config.json', 'ultima_evaluacion.json', 'ultima_foto.jpg']));
    await AppState.instance.cargar();
    final ultimo = AppState.instance.ultimo!;
    expect(ultimo.severidad, 'leve');
    expect(ultimo.orientacion!.fuentes, ['guia-de-prueba#2']);
    expect(ultimo.respuestas['extension'], 'una_zona');
    expect(ultimo.foto, isNotNull);
    expect(ultimo.resultado!.modelo, 'prueba');
  });

  testWidgets('las preguntas no dicen si son signo de alarma o síntoma', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await hastaCuestionario(tester);
    for (var i = 0; i < 14; i++) {
      expect(find.text('Signo de alarma'), findsNothing);
      expect(find.text('Síntomas'), findsNothing);
      expect(find.textContaining('te diremos que vayas a emergencia'), findsNothing);
      if (i < 13) await tocar(tester, find.text(i < 8 || i == 13 ? 'No' : Cuestionario.instancia.preguntas[i].botones.first.$1));
    }
  });

  testWidgets('la rueda de edad solo tiene de 1 a 4 años', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(home: const DatosNinoScreen(), routes: {'/cuestionario': (_) => const SizedBox()}));
    await tester.pumpAndSettle();
    // Se intenta pasar de 4 y de 1: la rueda se detiene en los extremos.
    await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Niño'));
    await tocar(tester, find.text('Continuar'));
    expect(AppState.instance.episodio.edadAnios, 4);
    expect(AppState.instance.episodio.sexo, 'masculino');
    final rueda = tester.widget<ListWheelScrollView>(find.byType(ListWheelScrollView));
    expect((rueda.childDelegate as ListWheelChildListDelegate).children, hasLength(4));
  });

  testWidgets('si el modelo no está seguro: indeterminado, severidad moderada y el porqué', (tester) async {
    clasificador.prediccion = const Prediccion('indeterminado', 0, salidaValida: false);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await hastaCuestionario(tester);
    await responderSinAlarma(tester);
    await esperar(tester, 3000);
    await tocar(tester, find.text('Ver resultado'));
    expect(find.text('No pudimos determinarlo'), findsOneWidget);
    expect(find.text('Moderada'), findsOneWidget);
    expect(find.textContaining('Por qué: El análisis de la foto no fue concluyente.'), findsOneWidget);
  });

  testWidgets('D42: si no ve ronchas, el modelo no puede decir urticaria', (tester) async {
    clasificador.prediccion = const Prediccion('compatible', 0.76);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await hastaCuestionario(tester);
    expect(find.text('¿Ves ronchas o manchas rojas en la piel de tu wawa?'), findsNothing);
    await responderSinAlarma(tester, veRonchas: 'No');
    await esperar(tester, 3000);

    // Al backend va «no compatible» con moderada, y la respuesta de ronchas NO va en `respuestas`.
    final enviado = backend.cuerpo('/v1/orientacion');
    expect(enviado['clase'], 'no_compatible');
    expect(enviado['severidad'], 'moderada');
    expect((enviado['respuestas'] as Map).containsKey('ve_ronchas'), isFalse);

    await tocar(tester, find.text('Ver resultado'));
    expect(find.text('Sí, compatible'), findsNothing);
    expect(find.text('Moderada'), findsOneWidget);
    expect(find.byKey(const Key('resultado-corregido')), findsOneWidget);
    expect(find.textContaining('Indicaste que no ves ronchas en la piel'), findsOneWidget);
    expect(AppState.instance.ultimo!.resultado!.claseModelo, 'compatible');
  });

  testWidgets('D42: con «No estoy seguro» manda el modelo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await hastaCuestionario(tester);
    await responderSinAlarma(tester, veRonchas: 'No estoy seguro');
    await esperar(tester, 3000);
    expect(backend.cuerpo('/v1/orientacion')['clase'], 'compatible');
    await tocar(tester, find.text('Ver resultado'));
    expect(find.text('Sí, compatible'), findsOneWidget);
    expect(find.byKey(const Key('resultado-corregido')), findsNothing);
  });

  test('D42: claseFinal solo corrige cuando no se ven ronchas', () {
    expect(claseFinal('compatible', 'no'), 'no_compatible');
    expect(claseFinal('indeterminado', 'no'), 'no_compatible');
    expect(claseFinal('no_compatible', 'no'), 'no_compatible');
    expect(claseFinal('compatible', 'si'), 'compatible');
    expect(claseFinal('compatible', 'no_se'), 'compatible');
    expect(claseFinal('no_compatible', 'si'), 'no_compatible');
    expect(claseFinal('indeterminado', null), 'indeterminado');
  });

  testWidgets('si dona fotos, la foto se cifra y se envía al terminar el análisis', (tester) async {
    backend.clavePublica = jsonDecode(File('test/fixtures/clave_rsa_prueba.json').readAsStringSync()) as Map<String, dynamic>;
    await AppState.instance.setDonarFotos(true);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await hastaCuestionario(tester);
    await responderSinAlarma(tester);
    await esperar(tester, 3000);
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2))); // RSA en Dart
    await tester.pump();

    final paquete = backend.cuerpo('/v1/donaciones');
    expect(paquete['alg'], 'RSA-OAEP-256+A256GCM');
    expect(base64.decode(paquete['clave_cifrada'] as String), hasLength(384));
    expect(paquete.containsKey('imagen_jpeg'), isFalse); // nada en claro
    expect(AppState.instance.ultimo!.donacion, 'enviada');
  });

  test('la última foto se guarda en el celular, se reemplaza y se puede borrar', () async {
    final s = AppState.instance;
    const local = Orientacion(severidad: 'leve', recomendaciones: ['x'], origen: 'local');
    const resultado = ResultadoAnalisis(clase: 'compatible', confianza: 0.9);

    s.nuevoEpisodio(Uint8List.fromList([1, 2, 3]));
    s.episodio.foto = Uint8List.fromList([1, 2, 3]);
    await s.guardarResultado(resultado, local);
    expect(almacen.archivos['ultima_foto.jpg'], [1, 2, 3]);

    s.terminarEpisodio();
    s.nuevoEpisodio(Uint8List.fromList([9, 9]));
    s.episodio.foto = Uint8List.fromList([9, 9]);
    await s.guardarResultado(resultado, local);
    expect(almacen.archivos['ultima_foto.jpg'], [9, 9]); // solo la última

    s.setGuardarFoto(false);
    await Future<void>.delayed(Duration.zero);
    expect(almacen.archivos.containsKey('ultima_foto.jpg'), isFalse);
    expect(almacen.archivos.containsKey('ultima_evaluacion.json'), isTrue); // el resto queda
  });

  testWidgets('si el backend responde 503, usa las recomendaciones locales', (tester) async {
    backend.orientacion = http.Response('{"error":{"codigo":"orientacion_no_disponible"}}', 503);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await hastaCuestionario(tester);
    await responderSinAlarma(tester);
    await esperar(tester, 3000);
    await tocar(tester, find.text('Ver resultado'));

    expect(find.text(Db.instance.recomendacionesLocales('leve').first), findsOneWidget);
    expect(find.textContaining('no pudimos conectarnos con el servidor'), findsOneWidget);
    expect(AppState.instance.ultimo!.orientacion!.origen, 'local');
  });

  testWidgets('un «Sí» de riesgo deriva a emergencia sin análisis y deja el resumen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await hastaCuestionario(tester);

    await tocar(tester, find.text('No')); // 1: dificultad para respirar
    await tocar(tester, find.text('Sí')); // 2: labios morados
    expect(find.text('Acude a emergencia ahora'), findsOneWidget);
    expect(find.text(Cuestionario.instancia.mensajeEmergencia), findsOneWidget);
    expect(AppState.instance.actual?.resultado, isNull);

    // Las recomendaciones del backend (severidad alta) aparecen debajo, no en lugar del aviso.
    await esperar(tester, 500);
    expect(backend.cuerpo('/v1/orientacion')['severidad'], 'alta');
    expect(AppState.instance.actual!.orientacion!.delBackend, isTrue);
    await tester.scrollUntilVisible(find.text('Además'), 150, scrollable: find.byType(Scrollable).last);
    expect(find.text('Recomendación del RAG de prueba.'), findsOneWidget);

    await tocar(tester, find.text('Resumen para el médico'));
    expect(find.text('No analizado: signo de alarma'), findsOneWidget);
    expect(find.text('¿Se le ponen morados los labios o la cara?'), findsOneWidget);
    expect(find.text('¿Las ronchas le pican?'), findsNothing); // el cuestionario se cortó
    expect(AppState.instance.ultimo!.severidad, 'alta');
  });

  test('la etiqueta del modelo avisa si es el respaldo del APK', () {
    expect(etiquetaModelo('1.1.1', delApk: false), '1.1.1');
    expect(etiquetaModelo('1.0.0', delApk: true), '1.0.0 (respaldo del APK)');
  });

  test('la severidad sigue las reglas del cuestionario v1', () {
    final c = Cuestionario.instancia;
    final base = <String, Object>{'tiempo_evolucion': 'menos_24h', 'extension': 'una_zona', 'muy_alergico': false};
    expect(c.severidad(base, 'compatible'), 'leve');
    expect(c.severidad({...base, 'extension': 'varias_zonas'}, 'compatible'), 'moderada');
    expect(c.severidad({...base, 'muy_alergico': true}, 'compatible'), 'moderada');
    expect(c.severidad({...base, 'tiempo_evolucion': 'mas_3_dias'}, 'no_compatible'), 'moderada');
    expect(c.severidad(base, 'indeterminado'), 'moderada');
    expect(c.severidad(base, 'no_compatible'), 'moderada'); // D41
    expect(c.severidad({...base, 'tos_repentina': true}, 'compatible'), 'alta');
    expect(c.severidad({...base, 'tos_repentina': true}, 'no_compatible'), 'alta');
  });

  test('D41: el respaldo local con foto no compatible no habla de cuidados de urticaria', () {
    final noCompatible = RecomendacionService.local('moderada', clase: 'no_compatible');
    expect(noCompatible.recomendaciones.first, startsWith('La foto no muestra lesiones compatibles con urticaria'));
    expect(noCompatible.severidad, 'moderada');
    expect(RecomendacionService.local('moderada', clase: 'compatible').recomendaciones,
        Db.instance.recomendacionesLocales('moderada'));
    // Con un signo de alarma manda la emergencia.
    expect(RecomendacionService.local('alta', clase: 'no_compatible').recomendaciones,
        Db.instance.recomendacionesLocales('alta'));
  });

  test('donar registra la autorización en el backend y quitarla la revoca', () async {
    final s = AppState.instance;
    expect(await s.setDonarFotos(true), isNull);
    expect(s.donarFotos, isTrue);
    expect(backend.cuerpo('/v1/autorizaciones'),
        {'installation_id': s.installationId, 'version_texto': AppState.versionTextoDonacion});

    expect(await s.setDonarFotos(false), isNull);
    expect(backend.peticiones.last.method, 'DELETE');
    expect(backend.peticiones.last.url.path, '/v1/autorizaciones/${s.installationId}');
    expect(s.donarFotos, isFalse);
  });

  test('si el backend no responde, el permiso de donar no cambia', () async {
    ApiCliente.instancia = ApiCliente(
      baseUrl: 'http://backend',
      cliente: MockClient((_) async => throw const SocketExceptionFalsa()),
    );
    final error = await AppState.instance.setDonarFotos(true);
    expect(error, isNotNull);
    expect(AppState.instance.donarFotos, isFalse);
  });

  testWidgets('«Permitir» pide el permiso real y, si está bloqueado, ofrece abrir ajustes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(const WawaQhaliApp());
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Comenzar'));
    await tocar(tester, find.byType(Checkbox));
    await tocar(tester, find.text('Continuar'));
    await tocar(tester, find.text('Ahora no'));
    expect(find.text('Permitir'), findsNWidgets(3));

    await tocar(tester, find.text('Permitir').first); // cámara: concedido
    expect(permisos.pedidos, ['camara']);
    expect(AppState.instance.permisos['camara'], isTrue);
    expect(find.text('Permitir'), findsNWidgets(2));

    permisos.respuesta = ResultadoPermiso.denegado;
    await tocar(tester, find.text('Permitir').first); // teléfono: denegado
    expect(AppState.instance.permisos['telefono'], isFalse);
    expect(find.textContaining('No diste el permiso'), findsOneWidget);

    permisos.respuesta = ResultadoPermiso.bloqueado;
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await tester.pumpAndSettle();
    await tocar(tester, find.text('Permitir').last); // ubicación: bloqueado
    expect(find.textContaining('El permiso está bloqueado'), findsOneWidget);
    await tester.tap(find.text('Abrir ajustes'));
    expect(permisos.ajustesAbiertos, isTrue);
  });

  test('el installation_id se crea una vez y se conserva', () async {
    final id = AppState.instance.installationId;
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
    await AppState.instance.cargar();
    expect(AppState.instance.installationId, id);
  });
}

class SocketExceptionFalsa implements Exception {
  const SocketExceptionFalsa();
}
