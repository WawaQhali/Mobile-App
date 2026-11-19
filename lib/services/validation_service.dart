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

/// Validación automática de la foto (US16, guía sección 5.2): nitidez, luz,
/// resolución, piel y rostro, medidas sobre la foto real.
class ValidacionService {
  static Future<ResultadoValidacion> validar(Uint8List bytes) async {
    final foto = await procesarFoto(bytes);
    final textos = {for (final v in Db.instance.validaciones) v['id'] as String: v};
    if (foto == null) {
      final t = textos['nitidez']!;
      return ResultadoValidacion([
        CheckFoto(
          id: 'lectura',
          label: 'Lectura de la foto',
          ok: false,
          problema: 'No se pudo leer',
          consejo: 'No pudimos abrir la foto. ${t['consejo']}',
        ),
      ], null);
    }

    final u = UmbralesFoto.desdeDb(Db.instance.foto);
    final rostro = await DetectorRostros.instancia.hayRostro(foto.recorte).catchError((Object _) => false);
    String n(double v) => v.toStringAsFixed(v < 10 ? 2 : 0);

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

    final oscura = foto.luminancia < u.luminanciaMinima;
    return ResultadoValidacion([
      check('nitidez', foto.nitidez >= u.nitidezMinima, 'Medido: ${n(foto.nitidez)} · mínimo ${n(u.nitidezMinima)}'),
      check(
        'iluminacion',
        !oscura && foto.luminancia <= u.luminanciaMaxima,
        'Medido: ${n(foto.luminancia)} · entre ${n(u.luminanciaMinima)} y ${n(u.luminanciaMaxima)}',
        problema: oscura ? 'Muy oscura' : 'Demasiada luz',
        consejo: oscura ? null : 'Hay demasiada luz o reflejo: evita el sol directo y el flash.',
      ),
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
