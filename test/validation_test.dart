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

  test('la misma foto desenfocada falla en nitidez', () async {
    final borrosa = img.gaussianBlur(img.decodeJpg(fotoDeMuestra())!, radius: 12);
    final r = await validar(jpeg(borrosa));
    expect(check(r, 'nitidez').ok, isFalse, reason: check(r, 'nitidez').detalle);
    expect(r.aprobada, isFalse);
  });

  test('una foto oscura falla en iluminación', () async {
    final oscura = img.adjustColor(img.decodeJpg(fotoDeMuestra())!, brightness: 0.2);
    final r = await validar(jpeg(oscura));
    expect(check(r, 'iluminacion').ok, isFalse, reason: check(r, 'iluminacion').detalle);
    expect(check(r, 'iluminacion').problema, 'Muy oscura');
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
