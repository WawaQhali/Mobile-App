import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/db.dart';
import '../routes.dart';
import '../services/image_processing.dart';
import '../services/permissions_service.dart';
import '../services/validation_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';
import '../widgets/illustrations.dart';

/// 05 · Captura, paso 1 (US02, US03, US16).
/// Vista previa en vivo de la cámara trasera: el círculo marca dónde centrar el habón.
/// La luz y la nitidez se revisan aquí, no en la pantalla siguiente:
/// - en vivo, sobre la vista previa: el círculo se pone verde si están bien y rojo si
///   no, con el aviso de qué hacer (p. ej. «ve a un lugar más iluminado»). En vivo
///   también se mide si hay piel dentro del círculo (si no, rojo: «No se ve piel»);
/// - otra vez sobre la foto tomada (o la de la galería): si no pasa, no se avanza.
class CamaraScreen extends StatefulWidget {
  const CamaraScreen({super.key});

  @override
  State<CamaraScreen> createState() => _CamaraScreenState();
}

class _CamaraScreenState extends State<CamaraScreen> with WidgetsBindingObserver {
  bool _abriendo = false;
  CameraController? _camara;
  bool _sinCamara = false; // sin cámara usable (emulador, web): cámara del sistema o foto de muestra

  /// Estado del círculo: null = todavía no se sabe (blanco), true = verde, false = rojo.
  bool? _calidadOk;
  AvisoCaptura? _aviso; // qué corregir cuando el círculo está rojo

  // Análisis en vivo: un cuadro cada [_cadaCuadro], con las métricas suavizadas.
  static const _cadaCuadro = Duration(milliseconds: 400);
  DateTime _ultimoCuadro = DateTime(0);
  double? _nitidezVivo, _luzVivo, _pielVivo;

  /// Después de una foto rechazada, su aviso se mantiene un momento aunque la
  /// vista previa ya se vea bien, para que se alcance a leer.
  DateTime _avisoFotoHasta = DateTime(0);

  /// Mientras se toma la foto o se está en otra pantalla, los cuadros se ignoran.
  /// El análisis NO se apaga y se vuelve a prender: en algunos celulares (Moto G85)
  /// volver a prenderlo pide un flujo más a la cámara y falla con
  /// «No supported surface combination».
  bool _ignorarCuadros = false;

  /// El plugin de cámara de Android es UNO para toda la app: si se abre una cámara
  /// mientras otra todavía se cierra, o dos a la vez, se juntan sus flujos y el
  /// celular falla («No supported surface combination»). Por eso se abre una sola
  /// vez ([_abriendoCamara]) y solo después de que terminó de cerrarse la anterior,
  /// aunque fuera de otra pantalla de cámara ([_cierrePendiente]).
  static Future<void> _cierrePendiente = Future.value();
  bool _abriendoCamara = false;

  void _cerrarCamara(CameraController c) {
    final anterior = _cierrePendiente;
    _cierrePendiente = anterior.then((_) => c.dispose()).catchError((Object _) {});
  }

  bool get _permitido => AppState.instance.permisos['camara'] ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppState.instance.addListener(_alCambiarPermisos);
    _iniciarCamara();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppState.instance.removeListener(_alCambiarPermisos);
    final c = _camara;
    if (c != null) _cerrarCamara(c);
    super.dispose();
  }

  void _alCambiarPermisos() {
    if (_permitido && _camara == null && !_sinCamara) _iniciarCamara();
  }

  /// Vista previa en vivo con la cámara trasera, sin flash y sin zoom (sección 5.1).
  Future<void> _iniciarCamara() async {
    if (!_permitido || _camara != null || _abriendoCamara) return;
    _abriendoCamara = true;
    try {
      await _cierrePendiente;
      if (!mounted) return;
      final camaras = await availableCameras();
      final trasera = camaras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => camaras.first,
      );
      // YUV420: el análisis en vivo usa el plano Y (luminancia). takePicture sigue dando JPEG.
      final c = CameraController(trasera, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted || _camara != null) {
        _cerrarCamara(c);
        return;
      }
      setState(() => _camara = c);
      await _empezarAnalisis(c);
    } catch (_) {
      if (mounted) setState(() => _sinCamara = true);
    } finally {
      _abriendoCamara = false;
    }
  }

  // --- Luz y nitidez en vivo ----------------------------------------------------------

  /// Se llama UNA vez por cámara abierta (ver [_ignorarCuadros]).
  Future<void> _empezarAnalisis(CameraController c) async {
    if (!c.value.isInitialized || c.value.isStreamingImages) return;
    try {
      await c.startImageStream(_alCuadro);
    } catch (_) {
      // Sin cuadros en vivo: el círculo queda blanco y se revisa solo la foto tomada.
    }
  }

  void _alCuadro(CameraImage cuadro) {
    final ahora = DateTime.now();
    if (!mounted || _ignorarCuadros || ahora.difference(_ultimoCuadro) < _cadaCuadro) return;
    _ultimoCuadro = ahora;
    final grupo = cuadro.format.group;
    if (grupo != ImageFormatGroup.yuv420 && grupo != ImageFormatGroup.nv21) return;
    final y = cuadro.planes.first;
    // En YUV420 llegan 3 planos: Y, U (Cb) y V (Cr). Con U y V se mide la piel.
    final uv = grupo == ImageFormatGroup.yuv420 && cuadro.planes.length >= 3;
    final m = metricasDeCuadro(
      y.bytes,
      ancho: cuadro.width,
      alto: cuadro.height,
      bytesPorFila: y.bytesPerRow,
      planoU: uv ? cuadro.planes[1].bytes : null,
      planoV: uv ? cuadro.planes[2].bytes : null,
      bytesPorFilaUV: uv ? cuadro.planes[1].bytesPerRow : 0,
      bytesPorPixelUV: uv ? (cuadro.planes[1].bytesPerPixel ?? 1) : 1,
    );
    // Promedio con el cuadro anterior: evita que el círculo parpadee.
    _nitidezVivo = _nitidezVivo == null ? m.nitidez : (_nitidezVivo! + m.nitidez) / 2;
    _luzVivo = _luzVivo == null ? m.luminancia : (_luzVivo! + m.luminancia) / 2;
    final piel = m.piel;
    if (piel != null) _pielVivo = _pielVivo == null ? piel : (_pielVivo! + piel) / 2;
    if (ahora.isBefore(_avisoFotoHasta)) return;
    final aviso = ValidacionService.revisarCaptura(
      nitidez: _nitidezVivo!,
      luminancia: _luzVivo!,
      proporcionPiel: _pielVivo,
    );
    if (aviso?.id == _aviso?.id && _calidadOk == (aviso == null)) return;
    setState(() {
      _calidadOk = aviso == null;
      _aviso = aviso;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    final c = _camara;
    if (estado == AppLifecycleState.inactive || estado == AppLifecycleState.paused) {
      if (c != null) {
        setState(() {
          _camara = null;
          _calidadOk = null;
          _aviso = null;
          _nitidezVivo = _luzVivo = _pielVivo = null;
        });
        _cerrarCamara(c);
      }
    } else if (estado == AppLifecycleState.resumed) {
      _iniciarCamara();
    }
  }

  /// Revisa la luz y la nitidez de la foto tomada. Si no pasan, se queda aquí con el
  /// círculo en rojo y el aviso; si pasan, sigue a la validación (resolución, piel, rostro).
  Future<void> _seguir(Uint8List bytes) async {
    final messenger = ScaffoldMessenger.of(context);
    final foto = await procesarFoto(bytes);
    final aviso = ValidacionService.revisarFoto(foto);
    if (!mounted) return;
    if (aviso != null) {
      setState(() {
        _calidadOk = false;
        _aviso = aviso;
        _avisoFotoHasta = DateTime.now().add(const Duration(seconds: 4));
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${aviso.problema}. ${aviso.mensaje}')));
      return;
    }
    AppState.instance.nuevoEpisodio(bytes, procesada: foto);
    final c = _camara;
    if (c != null) await c.pausePreview();
    if (!mounted) return;
    setState(() => _abriendo = false);
    _ignorarCuadros = true;
    await Navigator.pushNamed(context, Rutas.validacion);
    _ignorarCuadros = false;
    if (c != null && identical(c, _camara)) await c.resumePreview();
  }

  /// Botón redondo: toma la foto con la vista previa. Sin cámara, usa la del sistema.
  Future<void> _tomarFoto() async {
    final c = _camara;
    if (c == null || !c.value.isInitialized) return _capturar(ImageSource.camera);
    if (_abriendo || c.value.isTakingPicture) return;
    setState(() => _abriendo = true);
    final messenger = ScaffoldMessenger.of(context);
    _ignorarCuadros = true; // el análisis sigue prendido; solo no se usan estos cuadros
    try {
      final archivo = await c.takePicture();
      _ignorarCuadros = false;
      await _seguir(await archivo.readAsBytes());
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo tomar la foto. Inténtalo de nuevo.')));
    } finally {
      _ignorarCuadros = false;
      if (mounted && _abriendo) setState(() => _abriendo = false);
    }
  }

  /// Galería, o la cámara del sistema si no hay vista previa.
  Future<void> _capturar(ImageSource fuente) async {
    if (_abriendo) return;
    setState(() => _abriendo = true);
    final messenger = ScaffoldMessenger.of(context);

    Uint8List? bytes;
    try {
      final foto = await ImagePicker().pickImage(source: fuente, maxWidth: 2160, maxHeight: 2160, imageQuality: 95);
      if (foto != null) bytes = await foto.readAsBytes();
    } catch (_) {
      // Sin cámara (emulador, pruebas): una foto de muestra generada en el celular.
      messenger.showSnackBar(const SnackBar(content: Text('No hay cámara disponible. Usamos una foto de muestra.')));
      bytes = await generarFotoDeMuestra();
    }

    if (!mounted) return;
    if (bytes != null) await _seguir(bytes);
    if (mounted) setState(() => _abriendo = false);
  }

  void _ayuda() {
    final guia = Db.instance.guias.firstWhere((g) => g['id'] == 'foto');
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.crema,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(guia['titulo'] as String, style: AppText.titulo(22)),
            const SizedBox(height: 14),
            for (final p in (guia['puntos'] as List).cast<String>())
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 20, color: AppColors.verde),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p, style: AppText.cuerpo(14))),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            BotonPrincipal(label: 'Entendido', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final permitido = AppState.instance.permisos['camara'] ?? false;
        return Scaffold(
          backgroundColor: permitido ? const Color(0xFF1F1914) : AppColors.crema,
          body: permitido ? _visor() : _sinPermiso(),
        );
      },
    );
  }

  Widget _vistaPrevia() {
    final c = _camara;
    if (c == null || !c.value.isInitialized) {
      return const Opacity(opacity: .55, child: CustomPaint(painter: LesionMuestraPainter()));
    }
    final tamano = c.value.previewSize!; // viene en horizontal
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: tamano.height, height: tamano.width, child: CameraPreview(c)),
      ),
    );
  }

  /// Color del círculo: blanco mientras no se sabe, verde si la luz y la nitidez
  /// están bien, rojo si no.
  Color get _colorCirculo => switch (_calidadOk) {
    null => AppColors.sobreAccion,
    true => AppColors.capturaBien,
    false => AppColors.capturaMal,
  };

  /// Texto bajo el círculo: qué hacer.
  Widget _mensajeCirculo() {
    final aviso = _aviso;
    if (_calidadOk == false && aviso != null) {
      final icono = switch (aviso.id) {
        'oscura' => Icons.wb_sunny_outlined,
        'mucha_luz' => Icons.wb_shade_outlined,
        'borrosa' => Icons.blur_on_rounded,
        'sin_piel' => Icons.back_hand_outlined,
        _ => Icons.error_outline_rounded,
      };
      return Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: AppColors.capturaMal, borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                aviso.mensaje,
                textAlign: TextAlign.center,
                style: AppText.cuerpo(12.5, weight: FontWeight.w600, color: Colors.white, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }
    return Text(
      _calidadOk == true ? 'Buena luz y nitidez: toma la foto' : 'Centra la lesión en el círculo',
      style: AppText.cuerpo(13, weight: FontWeight.w600, color: AppColors.sobreAccion),
    );
  }

  Widget _visor() {
    const consejos = [
      (Icons.wb_sunny_outlined, 'Luz natural'),
      (Icons.flash_off_rounded, 'Sin flash'),
      (Icons.checkroom_outlined, 'Piel sin ropa'),
      (Icons.face_retouching_off_outlined, 'Sin su rostro'),
    ];

    Widget consejo((IconData, String) c) => Expanded(
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: AppColors.arena, borderRadius: BorderRadius.circular(10)),
                child: Icon(c.$1, size: 17, color: AppColors.caramelo),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(c.$2, style: AppText.cuerpo(12.5, weight: FontWeight.w600))),
            ],
          ),
        );

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _vistaPrevia(),
              if (_camara != null) const CustomPaint(painter: _MascaraCirculo(radio: 115, desplazamiento: 7)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Pastilla(
                      texto: 'Mantén 15–30 cm',
                      icono: Icons.straighten_rounded,
                      fondo: Color(0xCC1F1914),
                      color: AppColors.sobreAccion,
                    ),
                    const SizedBox(height: 16),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _colorCirculo, width: _calidadOk == null ? 2.5 : 4),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(liveRegion: true, child: _mensajeCirculo()),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BotonVolver(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text('Paso 1 de 4 · Captura',
                              style: AppText.cuerpo(13, weight: FontWeight.w600, color: AppColors.sobreAccion)),
                        ),
                      ),
                      const Pastilla(
                        texto: 'Sin flash',
                        icono: Icons.flash_off_rounded,
                        fondo: Color(0xCC1F1914),
                        color: AppColors.sobreAccion,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.crema,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [consejo(consejos[0]), const SizedBox(width: 12), consejo(consejos[1])]),
                const SizedBox(height: 12),
                Row(children: [consejo(consejos[2]), const SizedBox(width: 12), consejo(consejos[3])]),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => _capturar(ImageSource.gallery),
                        style: TextButton.styleFrom(foregroundColor: AppColors.tinta),
                        child: Column(
                          children: [
                            const Icon(Icons.photo_library_outlined),
                            const SizedBox(height: 4),
                            Text('Subir de galería', style: AppText.cuerpo(11.5, weight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Tomar foto',
                      child: Material(
                        color: AppColors.superficie,
                        shape: const CircleBorder(side: BorderSide(color: AppColors.caramelo, width: 4)),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _tomarFoto,
                          child: SizedBox(
                            width: 76,
                            height: 76,
                            child: Center(
                              child: _abriendo
                                  ? const CircularProgressIndicator()
                                  : Container(
                                      width: 58,
                                      height: 58,
                                      decoration: const BoxDecoration(color: AppColors.caramelo, shape: BoxShape.circle),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: IconButton(
                          onPressed: _ayuda,
                          tooltip: 'Ayuda para tomar la foto',
                          icon: const Icon(Icons.help_outline_rounded),
                          style: IconButton.styleFrom(
                            fixedSize: const Size(48, 48),
                            side: const BorderSide(color: AppColors.borde),
                            backgroundColor: AppColors.superficie,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sinPermiso() {
    return PantallaScroll(
      children: [
        const EncabezadoPaso(paso: 1, nombre: 'Captura'),
        const Spacer(),
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(color: AppColors.arena, shape: BoxShape.circle),
            child: const Icon(Icons.no_photography_outlined, size: 52, color: AppColors.caramelo),
          ),
        ),
        const SizedBox(height: 22),
        Text('Necesitamos acceso a la cámara', textAlign: TextAlign.center, style: AppText.titulo(26)),
        const SizedBox(height: 10),
        Text(
          'Sin el permiso no podemos tomar la foto de la lesión. También puedes usar una foto que ya tengas en tu galería.',
          textAlign: TextAlign.center,
          style: AppText.cuerpo(13.5, color: AppColors.textoSuave, height: 1.5),
        ),
        const Spacer(),
        const SizedBox(height: 18),
        BotonPrincipal(label: 'Permitir cámara', onPressed: () => pedirPermiso(context, 'camara')),
        const SizedBox(height: 10),
        BotonSecundario(label: 'Elegir de la galería', onPressed: () => _capturar(ImageSource.gallery)),
        const SizedBox(height: 10),
        Text('Puedes cambiar el permiso luego en los ajustes del celular.',
            textAlign: TextAlign.center, style: AppText.cuerpo(11.5, color: AppColors.textoSuave)),
      ],
    );
  }
}

/// Oscurece todo menos el círculo, para que se note dónde va el habón.
class _MascaraCirculo extends CustomPainter {
  const _MascaraCirculo({required this.radio, this.desplazamiento = 0});

  final double radio;
  final double desplazamiento;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset(0, desplazamiento));
    final fondo = Path()..addRect(Offset.zero & size);
    final hueco = Path()..addOval(Rect.fromCircle(center: centro, radius: radio));
    canvas.drawPath(
      Path.combine(PathOperation.difference, fondo, hueco),
      Paint()..color = const Color(0x8C1F1914),
    );
  }

  @override
  bool shouldRepaint(_MascaraCirculo old) => old.radio != radio || old.desplazamiento != desplazamiento;
}

