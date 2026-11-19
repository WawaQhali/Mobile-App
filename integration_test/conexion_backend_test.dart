// Conectividad real desde Android: la app (sus servicios, sin la UI) habla con el
// backend local y guarda la última evaluación en los archivos del celular.
//
// 1. Backend: `docker compose up -d`, `uv run python -m scripts.sembrar_demo` y
//    `uv run uvicorn app.main:app --host 0.0.0.0 --port 8000`
// 2. App:     flutter test integration_test/conexion_backend_test.dart -d emulator-5554
//
// El emulador ve el localhost de la computadora como 10.0.2.2 (URL por defecto).
// La UI completa se prueba en test/flow_test.dart con un backend simulado.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wawa_qhali/data/cuestionario.dart';
import 'package:wawa_qhali/data/db.dart';
import 'package:wawa_qhali/services/api_client.dart';
import 'package:wawa_qhali/services/classifier_service.dart';
import 'package:wawa_qhali/services/donation_service.dart';
import 'package:wawa_qhali/services/image_processing.dart';
import 'package:wawa_qhali/services/location_service.dart';
import 'package:wawa_qhali/services/validation_service.dart';
import 'package:wawa_qhali/services/local_storage.dart';
import 'package:wawa_qhali/services/recommendation_service.dart';
import 'package:wawa_qhali/state/app_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AlmacenArchivos almacen;

  setUpAll(() async {
    await Db.cargar();
    await Cuestionario.cargar();
    almacen = AlmacenArchivos(); // archivos reales del celular
    AppState.instance.almacen = almacen;
    await almacen.borrar('ultima_evaluacion.json');
    await AppState.instance.cargar();
  });

  testWidgets('autorizar y revocar la donación contra el backend', (_) async {
    final s = AppState.instance;
    expect(await s.setDonarFotos(true), isNull, reason: 'POST /v1/autorizaciones falló');
    expect(await s.setDonarFotos(false), isNull, reason: 'DELETE /v1/autorizaciones falló');
  });

  testWidgets('recomendaciones del backend (LLM + RAG) y última evaluación guardada', (_) async {
    final s = AppState.instance;
    s.actual = Episodio();
    final e = s.episodio;
    for (final p in Cuestionario.instancia.preguntas) {
      e.respuestas[p.id] = p.esSiNo ? false : p.opciones.first.id;
    }
    e.respuestas['extension'] = 'varias_zonas'; // regla moderada

    const resultado = ResultadoAnalisis(clase: 'compatible', confianza: 0.91);
    final o = await RecomendacionService.orientar(e, resultado: resultado);

    expect(o.origen, 'rag', reason: 'No llegó /v1/orientacion desde ${ApiCliente.instancia.baseUrl}');
    expect(o.severidad, 'moderada');
    expect(o.recomendaciones, isNotEmpty);
    expect(o.fuentes, isNotEmpty);

    await s.guardarResultado(resultado, o);
    final guardada = await almacen.leerJson('ultima_evaluacion.json');
    expect(guardada!['orientacion']['origen'], 'rag');
    expect(guardada['respuestas']['extension'], 'varias_zonas');

    // Al "reabrir" la app se recupera la misma evaluación.
    await s.cargar();
    expect(s.ultimo!.orientacion!.fuentes, o.fuentes);
  });

  testWidgets('en el celular: foto procesada, modelo TFLite y ML Kit', (_) async {
    final validacion = await ValidacionService.validar(await generarFotoDeMuestra());
    debugPrint('VALIDACION: ${validacion.checks.map((c) => '${c.id}=${c.ok} (${c.detalle})').join(' | ')}');
    expect(validacion.aprobada, isTrue);
    expect(validacion.conRostro, isFalse, reason: 'ML Kit vio un rostro en la foto de muestra');

    final p = await Clasificador.instancia.clasificar(validacion.foto!.recorte);
    debugPrint('MODELO ${Clasificador.instancia.versionModelo}: ${p.clase} ${p.confianza} valida=${p.salidaValida}');
    expect(['compatible', 'no_compatible', 'indeterminado'], contains(p.clase));
  });

  testWidgets('en el celular: GPS + centros de salud de OpenStreetMap', (_) async {
    final aqui = await Ubicacion.instancia.actual();
    final centros = await CentrosService.instancia.cercanos(aqui);
    debugPrint('UBICACION (coordenadas ocultas): ${centros.length} centros. '
        'Cercanos: ${centros.take(3).map((c) => '${c.nombre} (${c.tipo}, ${c.distanciaTexto})').join('; ')}');
    expect(centros, isNotEmpty);
  });

  testWidgets('en el celular: donación cifrada al backend', (_) async {
    final s = AppState.instance;
    expect(await s.setDonarFotos(true), isNull);
    final validacion = await ValidacionService.validar(await generarFotoDeMuestra());
    s.actual = Episodio()..foto = validacion.foto!.recorte;
    final e = s.episodio;
    for (final p in Cuestionario.instancia.preguntas) {
      e.respuestas[p.id] = p.esSiNo ? false : p.opciones.first.id;
    }
    e.resultado = const ResultadoAnalisis(clase: 'compatible', confianza: 0.91);
    await DonacionService.donarSiCorresponde(e);
    expect(e.donacion, 'enviada', reason: 'POST /v1/donaciones no respondió 202');
    await s.setDonarFotos(false);
  });
}
