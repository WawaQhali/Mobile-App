import 'package:flutter/material.dart';

import '../data/db.dart';
import '../services/links.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';
import '../widgets/illustrations.dart';

const _tipos = {'emergencia': 'Emergencia 24 h', 'centro': 'Centro de salud'};

/// 12 · Centros de salud cercanos. La lista sale de db.json; el mapa es un placeholder.
class CentrosScreen extends StatefulWidget {
  const CentrosScreen({super.key, this.conVolver = false});

  final bool conVolver;

  @override
  State<CentrosScreen> createState() => _CentrosScreenState();
}

class _CentrosScreenState extends State<CentrosScreen> {
  String _filtro = 'todos';

  @override
  Widget build(BuildContext context) {
    final filtros = {'todos': 'Todos', ..._tipos};

    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final ubicacion = AppState.instance.permisos['ubicacion'] ?? false;
        final centros = Db.instance.centros.where((c) => _filtro == 'todos' || c['tipo'] == _filtro).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
          children: [
            Row(
              children: [
                if (widget.conVolver) ...[const BotonVolver(), const SizedBox(width: 14)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Centros de salud', style: AppText.titulo(28)),
                      Text('Cerca de ti · ${Db.instance.app['distrito']}',
                          style: AppText.cuerpo(13, color: AppColors.textoSuave)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 170,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borde),
              ),
              child: CustomPaint(
                painter: MapaPainter(
                  pines: const [Offset(.25, .3), Offset(.62, .62), Offset(.84, .25)],
                  usuario: ubicacion ? const Offset(.48, .5) : null,
                ),
              ),
            ),
            if (!ubicacion) ...[
              const SizedBox(height: 12),
              Tarjeta(
                color: AppColors.arena,
                borde: null,
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(
                  children: [
                    const Icon(Icons.location_off_outlined, size: 20, color: AppColors.carameloOscuro),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Activa la ubicación para ver los centros más cercanos a ti.',
                          style: AppText.cuerpo(12.5)),
                    ),
                    TextButton(
                      onPressed: () => AppState.instance.permitir('ubicacion'),
                      child: const Text('Permitir'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final MapEntry(key: id, value: label) in filtros.entries)
                  _Filtro(label: label, activo: _filtro == id, onTap: () => setState(() => _filtro = id)),
              ],
            ),
            const SizedBox(height: 16),
            for (final c in centros) ...[_TarjetaCentro(c), const SizedBox(height: 12)],
            if (centros.isEmpty)
              Text('No hay centros para este filtro.', style: AppText.cuerpo(13, color: AppColors.textoSuave)),
          ],
        );
      },
    );
  }
}

class _Filtro extends StatelessWidget {
  const _Filtro({required this.label, required this.activo, required this.onTap});

  final String label;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: activo ? AppColors.tinta : AppColors.superficie,
          foregroundColor: activo ? AppColors.sobreAccion : AppColors.tinta,
          side: BorderSide(color: activo ? AppColors.tinta : AppColors.borde, width: 1.5),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: AppText.cuerpo(12.5, weight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

class _TarjetaCentro extends StatelessWidget {
  const _TarjetaCentro(this.centro);

  final Json centro;

  @override
  Widget build(BuildContext context) {
    final emergencia = centro['tipo'] == 'emergencia';
    final telefono = centro['telefono'] as String?;

    return Tarjeta(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(centro['nombre'] as String, style: AppText.cuerpo(14.5, weight: FontWeight.w700))),
              const SizedBox(width: 8),
              Text(centro['distancia'] as String, style: AppText.cuerpo(12, color: AppColors.textoSuave)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Pastilla(
                texto: _tipos[centro['tipo']] ?? '',
                fondo: emergencia ? AppColors.terracotaFondo : AppColors.arena,
                color: emergencia ? AppColors.terracota : AppColors.carameloOscuro,
              ),
              const Spacer(),
              IconButton.outlined(
                tooltip: telefono == null ? 'Teléfono no disponible' : 'Llamar',
                onPressed: telefono == null ? null : () => llamar(context, telefono),
                icon: const Icon(Icons.call_outlined, size: 19),
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.tinta,
                  side: const BorderSide(color: AppColors.borde, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  fixedSize: const Size(44, 44),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: () => comoLlegar(
                      context, (centro['lat'] as num).toDouble(), (centro['lng'] as num).toDouble()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.tinta,
                    side: const BorderSide(color: AppColors.tinta, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: AppText.cuerpo(12.5, weight: FontWeight.w600),
                  ),
                  child: const Text('Cómo llegar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
