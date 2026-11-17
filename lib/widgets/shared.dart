import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../theme/app_theme.dart';
import 'illustrations.dart';

/// Pantalla con scroll que igual permite usar [Spacer] cuando el contenido cabe.
/// No meter ListView ni GridView dentro (usa IntrinsicHeight).
class PantallaScroll extends StatelessWidget {
  const PantallaScroll({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(22, 20, 22, 24),
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - padding.vertical),
            child: IntrinsicHeight(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

class BotonPrincipal extends StatelessWidget {
  const BotonPrincipal({
    super.key,
    required this.label,
    required this.onPressed,
    this.icono,
    this.iconoFinal,
    this.alto = 54,
    this.color = AppColors.caramelo,
    this.colorTexto = AppColors.sobreAccion,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icono;
  final IconData? iconoFinal;
  final double alto;
  final Color color;
  final Color colorTexto;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: alto,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: colorTexto,
          disabledBackgroundColor: AppColors.deshabilitado,
          disabledForegroundColor: AppColors.deshabilitadoTexto,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: AppText.cuerpo(15, weight: FontWeight.w600),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[Icon(icono, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
            if (iconoFinal != null) ...[const SizedBox(width: 8), Icon(iconoFinal, size: 18)],
          ],
        ),
      ),
    );
  }
}

class BotonSecundario extends StatelessWidget {
  const BotonSecundario({
    super.key,
    required this.label,
    required this.onPressed,
    this.icono,
    this.alto = 50,
    this.color = AppColors.caramelo,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icono;
  final double alto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: alto,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: onPressed == null ? AppColors.borde : color, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: AppText.cuerpo(14, weight: FontWeight.w600),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[Icon(icono, size: 19), const SizedBox(width: 8)],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

class BotonTexto extends StatelessWidget {
  const BotonTexto({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.carameloOscuro,
          textStyle: AppText.cuerpo(13.5, weight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Botón redondo de 44 px para volver o cerrar.
class BotonVolver extends StatelessWidget {
  const BotonVolver({super.key, this.onPressed, this.icono = Icons.arrow_back_ios_new_rounded, this.tooltip = 'Volver'});

  final VoidCallback? onPressed;
  final IconData icono;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      tooltip: tooltip,
      icon: Icon(icono, size: 18),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        minimumSize: const Size(44, 44),
        backgroundColor: AppColors.superficie,
        foregroundColor: AppColors.tinta,
        side: const BorderSide(color: AppColors.borde),
      ),
    );
  }
}

class Tarjeta extends StatelessWidget {
  const Tarjeta({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.superficie,
    this.borde = AppColors.borde,
    this.radio = 20,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color? borde;
  final double radio;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radio),
        side: borde == null ? BorderSide.none : BorderSide(color: borde!),
      ),
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class ListaConDivisores extends StatelessWidget {
  const ListaConDivisores({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) const Divider(height: 1, thickness: 1, color: AppColors.divisor),
        ],
      ],
    );
  }
}

class Pastilla extends StatelessWidget {
  const Pastilla({super.key, required this.texto, required this.fondo, required this.color, this.icono});

  final String texto;
  final Color fondo;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[Icon(icono, size: 14, color: color), const SizedBox(width: 5)],
          Flexible(
            child: Text(texto,
                overflow: TextOverflow.ellipsis,
                style: AppText.cuerpo(12, weight: FontWeight.w700, color: color, height: 1.1)),
          ),
        ],
      ),
    );
  }
}

/// «Paso X de 4 · nombre» con la barra de progreso del flujo de evaluación.
class EncabezadoPaso extends StatelessWidget {
  const EncabezadoPaso({
    super.key,
    required this.paso,
    required this.nombre,
    this.volver = true,
    this.iconoVolver = Icons.arrow_back_ios_new_rounded,
    this.onVolver,
  });

  final int paso;
  final String nombre;
  final bool volver;
  final IconData iconoVolver;
  final VoidCallback? onVolver;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (volver)
          BotonVolver(icono: iconoVolver, onPressed: onVolver, tooltip: iconoVolver == Icons.close_rounded ? 'Cerrar' : 'Volver')
        else
          const SizedBox(width: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Paso $paso de 4 · $nombre',
                  style: AppText.cuerpo(12, weight: FontWeight.w600, color: AppColors.textoSuave)),
              const SizedBox(height: 7),
              Row(
                children: [
                  for (var i = 1; i <= 4; i++) ...[
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: i <= paso ? AppColors.caramelo : AppColors.borde,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    if (i < 4) const SizedBox(width: 5),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Las tres rayitas del onboarding (aceptación, donación, permisos).
class IndicadorOnboarding extends StatelessWidget {
  const IndicadorOnboarding({super.key, required this.actual});

  final int actual;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 24,
            height: 5,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: i == actual ? AppColors.caramelo : AppColors.tostado,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class LogoWawa extends StatelessWidget {
  const LogoWawa({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 40, height: 28, child: CustomPaint(painter: LogoPainter())),
        const SizedBox(width: 10),
        Flexible(
          child: Text('Wawa Qhali',
              overflow: TextOverflow.ellipsis, style: AppText.titulo(22, weight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class AvisoLegal extends StatelessWidget {
  const AvisoLegal({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.arena, borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.carameloOscuro),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              const TextSpan(children: [
                TextSpan(text: 'Wawa Qhali '),
                TextSpan(text: 'no emite diagnósticos', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' ni reemplaza al médico. Ante cualquier duda, acude a un establecimiento de salud.'),
              ]),
              style: AppText.cuerpo(12.5, color: const Color(0xFF3E3229)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Foto tomada por el usuario o, si no hay, una lesión de muestra.
class FotoLesion extends StatelessWidget {
  const FotoLesion({super.key, this.bytes, this.radio = 0});

  final Uint8List? bytes;
  final double radio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: bytes != null
          ? Image.memory(bytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity, gaplessPlayback: true)
          : const CustomPaint(painter: LesionMuestraPainter(), child: SizedBox.expand()),
    );
  }
}

Future<void> mostrarAvisoLegal(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.crema,
      title: Text('Aviso legal', style: AppText.titulo(22)),
      content: Text(Db.instance.app['avisoLegal'] as String, style: AppText.cuerpo(14)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
    ),
  );
}

IconData iconoPermiso(String id) => switch (id) {
      'camara' => Icons.photo_camera_outlined,
      'telefono' => Icons.call_outlined,
      _ => Icons.location_on_outlined,
    };

IconData iconoGuia(String id) => switch (id) {
      'foto' => Icons.wb_sunny_outlined,
      'libro' => Icons.menu_book_outlined,
      'alarma' => Icons.warning_amber_rounded,
      _ => Icons.favorite_border_rounded,
    };

String etiquetaConfianza(double c) => c >= 0.8
    ? 'Confianza alta'
    : c >= 0.6
        ? 'Confianza media'
        : 'Confianza baja';

String _dos(int n) => n.toString().padLeft(2, '0');
String formatoFecha(DateTime d) => '${_dos(d.day)}/${_dos(d.month)}/${d.year}';
String formatoHora(DateTime d) => '${_dos(d.hour)}:${_dos(d.minute)}';
