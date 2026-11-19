import 'package:flutter/material.dart';

import '../data/db.dart';
import '../routes.dart';
import '../services/permissions_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

/// 03 · Permisos: cámara, teléfono y ubicación.
class PermisosScreen extends StatelessWidget {
  const PermisosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    return Scaffold(
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => PantallaScroll(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          children: [
            const Align(alignment: Alignment.centerLeft, child: IndicadorOnboarding(actual: 2)),
            const SizedBox(height: 22),
            Text('Permisos', style: AppText.titulo(32)),
            const SizedBox(height: 10),
            Text('Para ayudarte en el momento necesitamos acceso a:',
                style: AppText.cuerpo(14, color: AppColors.textoSuave, height: 1.5)),
            const SizedBox(height: 22),
            for (final p in Db.instance.permisos) ...[
              _TarjetaPermiso(
                id: p['id'] as String,
                nombre: p['nombre'] as String,
                motivo: p['motivo'] as String,
                permitido: state.permisos[p['id']] ?? false,
              ),
              const SizedBox(height: 12),
            ],
            const Spacer(),
            const SizedBox(height: 18),
            BotonPrincipal(
              label: 'Continuar',
              onPressed: () => Navigator.pushNamedAndRemoveUntil(context, Rutas.home, (_) => false),
            ),
            const SizedBox(height: 10),
            Text('Puedes cambiarlos luego en Ajustes.',
                textAlign: TextAlign.center, style: AppText.cuerpo(12, color: AppColors.textoSuave)),
          ],
        ),
      ),
    );
  }
}

class _TarjetaPermiso extends StatelessWidget {
  const _TarjetaPermiso({required this.id, required this.nombre, required this.motivo, required this.permitido});

  final String id;
  final String nombre;
  final String motivo;
  final bool permitido;

  @override
  Widget build(BuildContext context) {
    return Tarjeta(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: AppColors.arena, borderRadius: BorderRadius.circular(14)),
            child: Icon(iconoPermiso(id), size: 22, color: AppColors.caramelo),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: AppText.cuerpo(15, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(motivo, style: AppText.cuerpo(12.5, color: AppColors.textoSuave, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (permitido)
            const Pastilla(texto: 'Listo', icono: Icons.check_rounded, fondo: AppColors.verdeFondo, color: AppColors.verde)
          else
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: () => pedirPermiso(context, id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.caramelo,
                  side: const BorderSide(color: AppColors.caramelo, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text('Permitir'),
              ),
            ),
        ],
      ),
    );
  }
}
