import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/validation_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

/// 06 · Validación automática de la foto (US16) y 06b · con errores.
class ValidacionScreen extends StatefulWidget {
  const ValidacionScreen({super.key});

  @override
  State<ValidacionScreen> createState() => _ValidacionScreenState();
}

class _ValidacionScreenState extends State<ValidacionScreen> {
  final _original = AppState.instance.episodio.fotoOriginal!;
  late final _validacion = ValidacionService.validar(_original);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<ResultadoValidacion>(
        future: _validacion,
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Revisando tu foto…', style: AppText.cuerpo(14, color: AppColors.textoSuave)),
                ],
              ),
            );
          }

          final resultado = snap.data!;
          final checks = resultado.checks;
          final fallas = checks.where((c) => !c.ok && c.bloquea).toList();
          final ok = resultado.aprobada;
          final conRostro = resultado.conRostro;
          // Se muestra el recorte cuadrado sin EXIF: es lo único que se guarda y se dona.
          final vista = resultado.foto?.recorte ?? _original;

          return PantallaScroll(
            children: [
              const EncabezadoPaso(paso: 1, nombre: 'Captura'),
              const SizedBox(height: 18),
              Text(ok ? 'Tu foto se ve bien' : 'Necesitamos otra foto', style: AppText.titulo(28)),
              const SizedBox(height: 6),
              Text(
                ok ? 'Revisamos que sirva para el análisis.' : fallas.map((f) => f.consejo).join(' '),
                style: AppText.cuerpo(13, color: AppColors.textoSuave, height: 1.5),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 230,
                child: Stack(
                  children: [
                    Positioned.fill(child: FotoLesion(bytes: vista, radio: 26)),
                    Positioned(
                      left: 14,
                      top: 14,
                      child: ok
                          ? const Pastilla(
                              texto: 'Foto lista',
                              icono: Icons.check_rounded,
                              fondo: AppColors.verdeFondo,
                              color: AppColors.verde,
                            )
                          : Pastilla(
                              texto: fallas.length > 1 ? '${fallas.length} problemas' : fallas.first.problema,
                              icono: Icons.close_rounded,
                              fondo: AppColors.terracotaFondo,
                              color: AppColors.terracota,
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Tarjeta(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListaConDivisores(children: [for (final c in checks) _FilaCheck(c)]),
              ),
              if (ok && conRostro) ...[
                const SizedBox(height: 12),
                Tarjeta(
                  color: AppColors.ambarFondo,
                  borde: null,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.face_retouching_off_outlined, size: 20, color: AppColors.ambarTexto),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Se ve el rostro de tu wawa. Puedes seguir con el análisis, pero esta foto no se donará.',
                          style: AppText.cuerpo(12.5, color: AppColors.ambarTexto, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              const SizedBox(height: 18),
              if (ok) ...[
                BotonPrincipal(
                  label: 'Usar esta foto',
                  onPressed: () {
                    AppState.instance.episodio
                      ..foto = resultado.foto!.recorte
                      ..fotoOriginal = null
                      ..conRostro = conRostro;
                    Navigator.pushNamed(context, Rutas.cuestionario);
                  },
                ),
                const SizedBox(height: 10),
                BotonSecundario(label: 'Tomar otra foto', onPressed: () => Navigator.pop(context)),
              ] else
                BotonPrincipal(
                  label: 'Tomar foto de nuevo',
                  icono: Icons.photo_camera_outlined,
                  alto: 56,
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FilaCheck extends StatelessWidget {
  const _FilaCheck(this.check);

  final CheckFoto check;

  @override
  Widget build(BuildContext context) {
    final ok = check.ok;
    final aviso = !ok && !check.bloquea;
    final color = ok ? AppColors.verde : (aviso ? AppColors.ambarTexto : AppColors.terracota);
    final fondo = ok ? AppColors.verdeFondo : (aviso ? AppColors.ambarFondo : AppColors.terracotaFondo);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: fondo,
              shape: BoxShape.circle,
            ),
            child: Icon(ok ? Icons.check_rounded : (aviso ? Icons.priority_high_rounded : Icons.close_rounded),
                size: 15, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.label, style: AppText.cuerpo(13.5, weight: FontWeight.w500)),
                if (check.detalle != null)
                  Text(check.detalle!, style: AppText.cuerpo(11, color: AppColors.textoSuave)),
              ],
            ),
          ),
          Text(
            ok ? 'Correcto' : check.problema,
            style: AppText.cuerpo(12, weight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
