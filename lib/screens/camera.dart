import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/db.dart';
import '../routes.dart';
import '../services/image_processing.dart';
import '../services/permissions_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';
import '../widgets/illustrations.dart';

/// 05 · Captura, paso 1 (US02, US03).
/// Vista previa en vivo de la cámara trasera: el círculo marca dónde centrar el habón.
class CamaraScreen extends StatefulWidget {
  const CamaraScreen({super.key});

  @override
  State<CamaraScreen> createState() => _CamaraScreenState();
}

class _CamaraScreenState extends State<CamaraScreen> with WidgetsBindingObserver {
  bool _abriendo = false;
  CameraController? _camara;
  bool _sinCamara = false; // sin cámara usable (emulador, web): cámara del sistema o foto de muestra

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
    _camara?.dispose();
    super.dispose();
  }

  void _alCambiarPermisos() {
    if (_permitido && _camara == null && !_sinCamara) _iniciarCamara();
  }

  /// Vista previa en vivo con la cámara trasera, sin flash y sin zoom (sección 5.1).
  Future<void> _iniciarCamara() async {
    if (!_permitido || _camara != null) return;
    try {
      final camaras = await availableCameras();
      final trasera = camaras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => camaras.first,
      );
      final c = CameraController(trasera, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted || _camara != null) {
        await c.dispose();
        return;
      }
      setState(() => _camara = c);
    } catch (_) {
      if (mounted) setState(() => _sinCamara = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    final c = _camara;
    if (estado == AppLifecycleState.inactive || estado == AppLifecycleState.paused) {
      if (c != null) {
        setState(() => _camara = null);
        c.dispose();
      }
    } else if (estado == AppLifecycleState.resumed) {
      _iniciarCamara();
    }
  }

  Future<void> _seguir(Uint8List bytes) async {
    AppState.instance.nuevoEpisodio(bytes);
    final c = _camara;
    if (c != null) await c.pausePreview();
    if (!mounted) return;
    await Navigator.pushNamed(context, Rutas.validacion);
    if (c != null && identical(c, _camara)) await c.resumePreview();
  }

  /// Botón redondo: toma la foto con la vista previa. Sin cámara, usa la del sistema.
  Future<void> _tomarFoto() async {
    final c = _camara;
    if (c == null || !c.value.isInitialized) return _capturar(ImageSource.camera);
    if (_abriendo || c.value.isTakingPicture) return;
    setState(() => _abriendo = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final archivo = await c.takePicture();
      final bytes = await archivo.readAsBytes();
      if (mounted) setState(() => _abriendo = false);
      await _seguir(bytes);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo tomar la foto. Inténtalo de nuevo.')));
    } finally {
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
    setState(() => _abriendo = false);
    if (bytes != null) await _seguir(bytes);
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
                    Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.sobreAccion, width: 2.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Centra la lesión en el círculo',
                        style: AppText.cuerpo(13, weight: FontWeight.w600, color: AppColors.sobreAccion)),
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

