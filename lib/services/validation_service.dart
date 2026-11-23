import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

import '../data/db.dart';
import 'image_processing.dart';

class CheckFoto {
  const CheckFoto({
    required this.id,
    required this.label,
    required this.ok,
    required this.problema,
    required this.consejo,
    this.detalle,
    this.bloquea = true,
  });

  final String id;
  final String label;
  final bool ok;
  final String problema;
  final String consejo;

  /// Valor medido y umbral, p. ej. "Medido: 12 · mínimo 20". Sirve para calibrar.
  final String? detalle;

  /// false = solo avisa (rostro visible: se puede analizar, pero no se dona).
  final bool bloquea;
}

/// Detección de rostro en el dispositivo (Google ML Kit). La imagen no sale del celular.
abstract class DetectorRostros {
  static DetectorRostros instancia = DetectorRostrosMlKit();

  Future<bool> hayRostro(Uint8List jpeg);
}

class DetectorRostrosMlKit implements DetectorRostros {
  final _detector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate));

  @override
  Future<bool> hayRostro(Uint8List jpeg) async {
    final carpeta = await getTemporaryDirectory();
    final archivo = File('${carpeta.path}/rostro_${DateTime.now().microsecondsSinceEpoch}.jpg');
    try {
      await archivo.writeAsBytes(jpeg, flush: true);
      final caras = await _detector.processImage(InputImage.fromFilePath(archivo.path));
      return caras.isNotEmpty;
    } finally {
      if (await archivo.exists()) await archivo.delete();
    }
  }
}

/// Umbrales de `db.json -> foto`. PROVISIONALES: la guía (sección 13) deja su
/// calibración al equipo de la app; la pantalla muestra el valor medido para ajustarlos.
class UmbralesFoto {
  UmbralesFoto.desdeDb(Map<String, dynamic> j)
      : ladoMinimoPx = j['ladoMinimoPx'] as int,
        nitidezMinima = (j['nitidezMinima'] as num).toDouble(),
        luminanciaMinima = (j['luminanciaMinima'] as num).toDouble(),
        luminanciaMaxima = (j['luminanciaMaxima'] as num).toDouble(),
        pielMinima = (j['proporcionPielMinima'] as num).toDouble();

  final int ladoMinimoPx;
  final double nitidezMinima;
  final double luminanciaMinima;
  final double luminanciaMaxima;
  final double pielMinima;
}

class ResultadoValidacion {
  const ResultadoValidacion(this.checks, this.foto);

  final List<CheckFoto> checks;

  /// null si la imagen no se pudo leer.
  final FotoProcesada? foto;

  bool get aprobada => foto != null && checks.every((c) => c.ok || !c.bloquea);
  bool get conRostro => checks.any((c) => c.id == 'rostro' && !c.ok);
}

/// Problema de luz o de nitidez que se avisa en la cámara (círculo rojo).
class AvisoCaptura {
  const AvisoCaptura({required this.id, required this.problema, required this.mensaje});

  /// `oscura`, `mucha_luz`, `borrosa` o `ilegible`.
  final String id;
  final String problema; // corto, p. ej. «Muy oscura»
  final String mensaje; // qué hacer, p. ej. «Ve a un lugar más iluminado»

  static const ilegible = AvisoCaptura(
    id: 'ilegible',
    problema: 'No se pudo leer',
    mensaje: 'No pudimos abrir la foto. Toma otra o elige una diferente.',
  );
}

/// Validación automática de la foto (US16, guía sección 5.2).
///
/// - Luz y nitidez se revisan EN LA CÁMARA ([revisarCaptura]): en vivo sobre la vista
///   previa (el círculo se pone verde o rojo) y otra vez sobre la foto tomada, antes
///   de pasar a la siguiente pantalla.
/// - La pantalla de validación revisa lo demás ([validar]): resolución, piel y rostro.
class ValidacionService {
  /// null si la luz y la nitidez están dentro de los umbrales de `db.json -> foto`.
  /// Primero la luz: con poca luz la foto también sale borrosa, y lo que hay que
  /// corregir es la luz.
  static AvisoCaptura? revisarCaptura({required double nitidez, required double luminancia}) {
    final u = UmbralesFoto.desdeDb(Db.instance.foto);
    final textos = {for (final v in Db.instance.validaciones) v['id'] as String: v};
    final luz = textos['iluminacion']!, nitida = textos['nitidez']!;
    if (luminancia < u.luminanciaMinima) {
      return AvisoCaptura(id: 'oscura', problema: luz['problema'] as String, mensaje: luz['consejo'] as String);
    }
    if (luminancia > u.luminanciaMaxima) {
      return AvisoCaptura(
        id: 'mucha_luz',
        problema: luz['problemaExceso'] as String,
        mensaje: luz['consejoExceso'] as String,
      );
    }
    if (nitidez < u.nitidezMinima) {
      return AvisoCaptura(id: 'borrosa', problema: nitida['problema'] as String, mensaje: nitida['consejo'] as String);
    }
    return null;
  }

  /// Revisión de una foto ya tomada (la de la cámara o la de la galería).
  static AvisoCaptura? revisarFoto(FotoProcesada? foto) => foto == null
      ? AvisoCaptura.ilegible
      : revisarCaptura(nitidez: foto.nitidez, luminancia: foto.luminancia);

  /// Resolución, piel y rostro. Si la cámara ya procesó la foto, se pasa en
  /// [procesada] para no repetir el trabajo.
  static Future<ResultadoValidacion> validar(Uint8List bytes, {FotoProcesada? procesada}) async {
    final foto = procesada ?? await procesarFoto(bytes);
    final textos = {for (final v in Db.instance.validaciones) v['id'] as String: v};
    if (foto == null) {
      return ResultadoValidacion([
        CheckFoto(
          id: 'lectura',
          label: 'Lectura de la foto',
          ok: false,
          problema: AvisoCaptura.ilegible.problema,
          consejo: AvisoCaptura.ilegible.mensaje,
        ),
      ], null);
    }

    final u = UmbralesFoto.desdeDb(Db.instance.foto);
    final rostro = await DetectorRostros.instancia.hayRostro(foto.recorte).catchError((Object _) => false);

    CheckFoto check(String id, bool ok, String detalle, {String? problema, String? consejo}) {
      final t = textos[id]!;
      return CheckFoto(
        id: id,
        label: t['label'] as String,
        ok: ok,
        problema: problema ?? t['problema'] as String,
        consejo: consejo ?? t['consejo'] as String,
        detalle: detalle,
        bloquea: t['bloquea'] as bool? ?? true,
      );
    }

    return ResultadoValidacion([
      check(
        'resolucion',
        foto.ladoCorto >= u.ladoMinimoPx,
        '${foto.anchoOriginal} × ${foto.altoOriginal} px',
        problema: '${foto.anchoOriginal} × ${foto.altoOriginal} px',
      ),
      check(
        'piel',
        foto.proporcionPiel >= u.pielMinima,
        'Medido: ${(foto.proporcionPiel * 100).round()} % · mínimo ${(u.pielMinima * 100).round()} %',
      ),
      check('rostro', !rostro, rostro ? 'Se detectó un rostro' : 'No se detectó ningún rostro'),
    ], foto);
  }
}
