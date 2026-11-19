import 'package:flutter/material.dart';

import '../data/db.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';
import '../widgets/illustrations.dart';
import '../widgets/recommendations.dart';

/// 04 · Inicio (sin login).
class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key, required this.onIrATab});

  final ValueChanged<int> onIrATab;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final ultimo = AppState.instance.ultimo;
        final guias = Db.instance.guias;

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
          children: [
            const Row(
              children: [Expanded(child: LogoWawa())],
            ),
            const SizedBox(height: 16),
            const _Hero(),
            const SizedBox(height: 16),
            Tarjeta(
              color: AppColors.terracotaFondo,
              borde: null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              onTap: () => Navigator.pushNamed(context, Rutas.emergencia),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(color: AppColors.terracota, shape: BoxShape.circle),
                    child: const Icon(Icons.warning_amber_rounded, size: 21, color: AppColors.sobreAccion),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Signos de alarma',
                            style: AppText.cuerpo(14, weight: FontWeight.w700, color: AppColors.terracotaTexto)),
                        const SizedBox(height: 3),
                        Text(
                          '¿Le cuesta respirar o tiene los labios hinchados? Llama al ${Db.instance.app['samu']}.',
                          style: AppText.cuerpo(12, color: const Color(0xFF4E3A33), height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.terracotaTexto),
                ],
              ),
            ),
            if (ultimo != null && (ultimo.resultado != null || ultimo.hayAlarma)) ...[
              const SizedBox(height: 16),
              _UltimaEvaluacion(ultimo),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: Text('Guías rápidas', style: AppText.titulo(18))),
                TextButton(onPressed: () => onIrATab(1), child: const Text('Ver todas')),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 136,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: guias.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final g = guias[i];
                  return _GuiaMini(
                    titulo: g['titulo'] as String,
                    icono: iconoGuia(g['icono'] as String),
                    alarma: g['alarma'] as bool,
                    onTap: () {
                      AppState.instance.abrirGuia(g['id'] as String);
                      onIrATab(1);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(18, 20, 6, 0),
      decoration: BoxDecoration(color: AppColors.arena, borderRadius: BorderRadius.circular(26)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Notas ronchas en su piel?', style: AppText.titulo(22)),
                  const SizedBox(height: 8),
                  Text('Evalúa la lesión en menos de un minuto.',
                      style: AppText.cuerpo(13, color: const Color(0xFF4E4136))),
                  const SizedBox(height: 16),
                  BotonPrincipal(
                    label: 'Evaluar lesión',
                    icono: Icons.photo_camera_outlined,
                    alto: 46,
                    onPressed: () => Navigator.pushNamed(context, Rutas.camara),
                  ),
                ],
              ),
            ),
          ),
          Transform.translate(offset: const Offset(0, 18), child: const WawaIlustracion(width: 100)),
        ],
      ),
    );
  }
}

class _UltimaEvaluacion extends StatelessWidget {
  const _UltimaEvaluacion(this.episodio);

  final Episodio episodio;

  @override
  Widget build(BuildContext context) {
    final r = episodio.resultado;
    final severidad = episodio.severidad;
    final estado = episodio.hayAlarma || r == null || severidad == null
        ? 'Signo de alarma'
        : 'Severidad ${etiquetaSeveridad(severidad).toLowerCase()}';
    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      onTap: () => Navigator.pushNamed(context, Rutas.resumen),
      child: Row(
        children: [
          SizedBox(width: 48, height: 48, child: FotoLesion(bytes: episodio.foto, radio: 14)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Última evaluación', style: AppText.cuerpo(14, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 12, color: AppColors.textoSuave),
                    const SizedBox(width: 5),
                    Text('${formatoFecha(episodio.fecha)} · $estado',
                        style: AppText.cuerpo(12, color: AppColors.textoSuave)),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _GuiaMini extends StatelessWidget {
  const _GuiaMini({required this.titulo, required this.icono, required this.alarma, required this.onTap});

  final String titulo;
  final IconData icono;
  final bool alarma;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: Tarjeta(
        color: alarma ? AppColors.terracotaFondo : AppColors.superficie,
        borde: alarma ? AppColors.terracotaBorde : AppColors.borde,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: alarma ? AppColors.terracota : AppColors.arena,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, size: 19, color: alarma ? AppColors.sobreAccion : AppColors.caramelo),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: Text(titulo,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cuerpo(13, weight: FontWeight.w600, height: 1.35)),
            ),
          ],
        ),
      ),
    );
  }
}
