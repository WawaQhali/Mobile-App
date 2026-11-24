import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wawa_qhali/data/db.dart';
import 'package:wawa_qhali/services/image_processing.dart';
import 'package:wawa_qhali/services/validation_service.dart';

class RostroFalso implements DetectorRostros {
  RostroFalso(this.hay);
  final bool hay;

  @override
  Future<bool> hayRostro(Uint8List jpeg) async => hay;
}

Uint8List jpeg(img.Image i) => img.encodeJpg(i, quality: 95);

img.Image colorSolido(int lado, int r, int g, int b) {
  final i = img.Image(width: lado, height: lado);
  for (final p in i) {
    p
      ..r = r
      ..g = g
      ..b = b;
  }
  return i;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  usarIsolates = false;

  setUpAll(() async => Db.cargar());
  setUp(() => DetectorRostros.instancia = RostroFalso(false));

  Future<ResultadoValidacion> validar(Uint8List bytes) => ValidacionService.validar(bytes);
  CheckFoto check(ResultadoValidacion r, String id) => r.checks.firstWhere((c) => c.id == id);

  test('una foto nítida de piel, bien iluminada y grande pasa', () async {
    final r = await validar(fotoDeMuestra());
    expect(r.aprobada, isTrue, reason: r.checks.map((c) => '${c.id}: ${c.detalle}').join('\n'));
  });

  test('la validación ya no revisa luz ni nitidez (se revisan en la cámara)', () async {
    final r = await validar(fotoDeMuestra());
    expect(r.checks.map((c) => c.id), ['resolucion', 'piel', 'rostro']);
  });

  // --- Cámara: luz y nitidez de la foto tomada -----------------------------------------

  Future<AvisoCaptura?> revisar(Uint8List bytes) async => ValidacionService.revisarFoto(await procesarFoto(bytes));

  test('una foto nítida y bien iluminada pasa la revisión de la cámara', () async {
    expect(await revisar(fotoDeMuestra()), isNull);
  });

  test('la misma foto desenfocada: aviso de nitidez', () async {
    final borrosa = img.gaussianBlur(img.decodeJpg(fotoDeMuestra())!, radius: 12);
    final aviso = await revisar(jpeg(borrosa));
    expect(aviso?.id, 'borrosa');
    expect(aviso?.mensaje, contains('nítido'));
  });

  test('una foto oscura: aviso de ir a un lugar más iluminado', () async {
    final oscura = img.adjustColor(img.decodeJpg(fotoDeMuestra())!, brightness: 0.2);
    final aviso = await revisar(jpeg(oscura));
    expect(aviso?.id, 'oscura');
    expect(aviso?.problema, 'Muy oscura');
    expect(aviso?.mensaje, contains('lugar más iluminado'));
  });

  test('una foto quemada: aviso de demasiada luz', () async {
    final aviso = await revisar(jpeg(colorSolido(1200, 250, 248, 245)));
    expect(aviso?.id, 'mucha_luz');
  });

  test('umbral de luminosidad: justo en el mínimo pasa, debajo no', () {
    final u = UmbralesFoto.desdeDb(Db.instance.foto);
    expect(ValidacionService.revisarCaptura(nitidez: 999, luminancia: u.luminanciaMinima), isNull);
    expect(ValidacionService.revisarCaptura(nitidez: 999, luminancia: u.luminanciaMinima - 1)?.id, 'oscura');
    expect(ValidacionService.revisarCaptura(nitidez: 999, luminancia: u.luminanciaMaxima + 1)?.id, 'mucha_luz');
    // Con poca luz se avisa la luz, aunque también esté borrosa.
    expect(ValidacionService.revisarCaptura(nitidez: 0, luminancia: 10)?.id, 'oscura');
  });

  test('un archivo que no se puede leer: aviso en la cámara', () async {
    expect((await revisar(Uint8List.fromList([1, 2, 3])))?.id, 'ilegible');
  });

  // --- Cámara: cuadros en vivo (plano Y) ----------------------------------------------

  /// Plano Y de un cuadro de 640 × 480 con relleno al final de cada fila, como en Android.
  Uint8List planoY(int Function(int x, int y) valor, {int ancho = 640, int alto = 480, int fila = 704}) {
    final bytes = Uint8List(fila * alto);
    for (var y = 0; y < alto; y++) {
      for (var x = 0; x < ancho; x++) {
        bytes[y * fila + x] = valor(x, y).clamp(0, 255);
      }
    }
    return bytes;
  }

  AvisoCaptura? enVivo(Uint8List y) {
    final m = metricasDeCuadro(y, ancho: 640, alto: 480, bytesPorFila: 704);
    return ValidacionService.revisarCaptura(nitidez: m.nitidez, luminancia: m.luminancia);
  }

  test('cuadro en vivo con textura y buena luz: círculo verde', () {
    final azar = Random(3);
    expect(enVivo(planoY((x, y) => 150 + azar.nextInt(40) - 20)), isNull);
  });

  test('cuadro en vivo oscuro: círculo rojo por luz', () {
    final azar = Random(3);
    expect(enVivo(planoY((x, y) => 25 + azar.nextInt(20) - 10))?.id, 'oscura');
  });

  test('cuadro en vivo liso (desenfocado): círculo rojo por nitidez', () {
    expect(enVivo(planoY((x, y) => 120 + x ~/ 40))?.id, 'borrosa');
  });

  /// Planos U y V (320 × 240, la mitad del cuadro) de un solo color Cb/Cr.
  Uint8List planoUV(int valor) => Uint8List(320 * 240)..fillRange(0, 320 * 240, valor);

  AvisoCaptura? enVivoConColor(int cb, int cr) {
    final azar = Random(3);
    final m = metricasDeCuadro(
      planoY((x, y) => 150 + azar.nextInt(40) - 20),
      ancho: 640,
      alto: 480,
      bytesPorFila: 704,
      planoU: planoUV(cb),
      planoV: planoUV(cr),
      bytesPorFilaUV: 320,
    );
    return ValidacionService.revisarCaptura(nitidez: m.nitidez, luminancia: m.luminancia, proporcionPiel: m.piel);
  }

  test('cuadro en vivo con piel en el círculo: verde', () {
    expect(enVivoConColor(110, 150), isNull); // Cb/Cr de piel
  });

  test('cuadro en vivo sin piel en el círculo (teclado, pared): rojo «No se ve piel»', () {
    final aviso = enVivoConColor(128, 128); // gris
    expect(aviso?.id, 'sin_piel');
    expect(aviso?.mensaje, contains('No se ve piel'));
  });

  test('la piel se mide solo dentro del círculo', () {
    // Piel solo en los bordes (fuera del 60 % central): no cuenta.
    final u = Uint8List(320 * 240), v = Uint8List(320 * 240);
    for (var y = 0; y < 240; y++) {
      for (var x = 0; x < 320; x++) {
        final borde = x < 60 || x >= 260;
        u[y * 320 + x] = borde ? 110 : 128;
        v[y * 320 + x] = borde ? 150 : 128;
      }
    }
    final m = metricasDeCuadro(planoY((x, y) => 150), ancho: 640, alto: 480, bytesPorFila: 704,
        planoU: u, planoV: v, bytesPorFilaUV: 320);
    expect(m.piel, lessThan(0.05));
  });

  test('sin planos de color no se mide la piel (no se avisa)', () {
    expect(metricasDeCuadro(planoY((x, y) => 150), ancho: 640, alto: 480, bytesPorFila: 704).piel, isNull);
  });

  test('con poca luz se avisa la luz antes que la piel', () {
    expect(ValidacionService.revisarCaptura(nitidez: 999, luminancia: 10, proporcionPiel: 0)?.id, 'oscura');
  });

  test('en vivo se mide solo el cuadrado central', () {
    // Bordes laterales negros: fuera del cuadrado central, no cuentan.
    final azar = Random(3);
    final m = metricasDeCuadro(
      planoY((x, y) => x < 80 || x >= 560 ? 0 : 150 + azar.nextInt(10)),
      ancho: 640,
      alto: 480,
      bytesPorFila: 704,
    );
    expect(m.luminancia, greaterThan(140));
  });

  test('una foto chica falla en resolución', () async {
    final chica = img.copyResize(img.decodeJpg(fotoDeMuestra())!, width: 800, height: 800);
    final r = await validar(jpeg(chica));
    expect(check(r, 'resolucion').ok, isFalse);
    expect(check(r, 'resolucion').problema, '800 × 800 px');
  });

  test('una foto sin piel (una pared azul) falla en piel', () async {
    final r = await validar(jpeg(colorSolido(1200, 60, 90, 200)));
    expect(check(r, 'piel').ok, isFalse, reason: check(r, 'piel').detalle);
  });

  test('si se ve un rostro, avisa pero no bloquea el análisis', () async {
    DetectorRostros.instancia = RostroFalso(true);
    final r = await validar(fotoDeMuestra());
    expect(check(r, 'rostro').ok, isFalse);
    expect(check(r, 'rostro').bloquea, isFalse);
    expect(r.aprobada, isTrue);
    expect(r.conRostro, isTrue);
  });

  test('el recorte que se guarda es cuadrado, de 1024 px y sin EXIF', () async {
    final original = img.decodeJpg(fotoDeMuestra(lado: 1600))!;
    final rectangular = img.copyCrop(original, x: 0, y: 0, width: 1600, height: 1200);
    rectangular.exif.imageIfd['Make'] = 'Celular de prueba';
    final r = await validar(jpeg(rectangular));
    final recorte = img.decodeJpg(r.foto!.recorte)!;
    expect((recorte.width, recorte.height), (1024, 1024));
    expect(recorte.exif.isEmpty, isTrue);
  });

  test('un archivo que no es imagen no se aprueba', () async {
    final r = await validar(Uint8List.fromList([1, 2, 3]));
    expect(r.aprobada, isFalse);
    expect(r.foto, isNull);
  });
}
