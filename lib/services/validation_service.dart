import 'dart:typed_data';
import 'dart:ui' as ui;

import '../data/db.dart';

class CheckFoto {
  const CheckFoto({
    required this.id,
    required this.label,
    required this.ok,
    required this.problema,
    required this.consejo,
    this.bloquea = true,
  });

  final String id;
  final String label;
  final bool ok;
  final String problema;
  final String consejo;

  /// false = solo avisa (rostro visible: se puede analizar, pero no se dona).
  final bool bloquea;
}

/// Validación automática de la foto (US16).
///
/// La resolución se mide de verdad: el lado más corto debe tener al menos
/// `db.json -> foto.ladoMinimoPx`. El resto todavía es SIMULADO
/// (`db.json -> demo.validacion`); aquí irán nitidez (varianza del Laplaciano),
/// brillo medio, detección de piel y de rostro.
class ValidacionService {
  static Future<List<CheckFoto>> validar(Uint8List? foto) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final fallan = switch (Db.instance.demo['validacion']) {
      'falla_nitidez' => {'nitidez'},
      'varias_fallas' => {'nitidez', 'iluminacion'},
      'con_rostro' => {'rostro'},
      _ => <String>{},
    };

    final tamano = foto == null ? null : await medir(foto);
    final minimo = Db.instance.ladoMinimoFotoPx;

    return [
      for (final v in Db.instance.validaciones)
        if (v['id'] == 'resolucion' && tamano != null)
          CheckFoto(
            id: 'resolucion',
            label: v['label'] as String,
            ok: tamano.shortestSide >= minimo,
            problema: '${tamano.width.round()} × ${tamano.height.round()} px',
            consejo: 'La foto mide ${tamano.width.round()} × ${tamano.height.round()} px y necesitamos al menos '
                '$minimo px por lado. ${v['consejo']}',
          )
        else
          CheckFoto(
            id: v['id'] as String,
            label: v['label'] as String,
            ok: !fallan.contains(v['id']),
            problema: v['problema'] as String,
            consejo: v['consejo'] as String,
            bloquea: v['bloquea'] as bool? ?? true,
          ),
    ];
  }

  /// Ancho y alto en px sin decodificar toda la imagen.
  static Future<ui.Size> medir(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    descriptor.dispose();
    buffer.dispose();
    return size;
  }
}
