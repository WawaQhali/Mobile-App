import 'package:flutter/material.dart';

import '../data/db.dart';
import '../routes.dart';
import '../services/links.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';
import '../widgets/illustrations.dart';

/// 08 · Derivación a emergencia (US05). Nunca muestra el resultado del modelo.
class EmergenciaScreen extends StatelessWidget {
  const EmergenciaScreen({super.key});

  void _volverAlInicio(BuildContext context) {
    AppState.instance.terminarEpisodio(); // queda como «última evaluación» para el médico
    Navigator.pushNamedAndRemoveUntil(context, Rutas.home, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final samu = Db.instance.app['samu'] as String;
    final marcoAlarma = AppState.instance.actual?.hayAlarma ?? false;
    final centros = Db.instance.centros;
    final cercano = centros.firstWhere((c) => c['tipo'] == 'emergencia', orElse: () => centros.first);
    final pasos = (Db.instance.emergencia['pasos'] as List).cast<String>();

    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 24, 24, 24),
            decoration: const BoxDecoration(
              color: AppColors.terracota,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.sobreAccion.withValues(alpha: .16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_amber_rounded, size: 28, color: AppColors.sobreAccion),
                ),
                const SizedBox(height: 14),
                Text('Acude a emergencia ahora', style: AppText.titulo(31, color: AppColors.sobreAccion)),
                const SizedBox(height: 12),
                Text(
                  marcoAlarma
                      ? 'Marcaste un signo de alarma. Puede ser una reacción grave que necesita atención inmediata.'
                      : 'Si a tu wawa le cuesta respirar, tiene labios, lengua o párpados hinchados, o le cuesta tragar, necesita atención inmediata.',
                  style: AppText.cuerpo(13.5, color: const Color(0xFFFBE9E2), height: 1.5),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: BotonPrincipal(
                    label: 'Llamar al SAMU · $samu',
                    icono: Icons.call_outlined,
                    alto: 56,
                    color: AppColors.sobreAccion,
                    colorTexto: AppColors.terracotaTexto,
                    onPressed: () => llamar(context, samu),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
              children: [
                Tarjeta(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      const SizedBox(height: 104, width: double.infinity, child: CustomPaint(painter: MapaPainter())),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Emergencia más cercana', style: AppText.cuerpo(14, weight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Text('${cercano['nombre']} · ${cercano['distancia']}',
                                      style: AppText.cuerpo(12, color: AppColors.textoSuave)),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 44,
                              child: OutlinedButton(
                                onPressed: () => Navigator.pushNamed(context, Rutas.centros),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.tinta,
                                  side: const BorderSide(color: AppColors.tinta, width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Cómo llegar'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (marcoAlarma) ...[
                  const SizedBox(height: 12),
                  BotonSecundario(
                    label: 'Resumen para el médico',
                    icono: Icons.assignment_outlined,
                    onPressed: () => Navigator.pushNamed(context, Rutas.resumen),
                  ),
                ],
                const SizedBox(height: 18),
                Text('Mientras tanto', style: AppText.titulo(18)),
                const SizedBox(height: 10),
                for (final (i, paso) in pasos.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.arena, shape: BoxShape.circle),
                          child: Text('${i + 1}',
                              style: AppText.cuerpo(12, weight: FontWeight.w700, color: AppColors.carameloOscuro)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(paso, style: AppText.cuerpo(13))),
                      ],
                    ),
                  ),
                if (marcoAlarma) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFC9B48E)),
                    ),
                    child: Text(
                      'Por tu seguridad, cuando hay un signo de alarma no mostramos el análisis de la foto.',
                      style: AppText.cuerpo(11.5, color: const Color(0xFF4E4136), height: 1.5),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                BotonTexto(label: 'Volver al inicio', onPressed: () => _volverAlInicio(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
