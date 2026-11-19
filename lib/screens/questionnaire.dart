import 'package:flutter/material.dart';

import '../data/cuestionario.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

/// 07 · Cuestionario, paso 2 (US04, US05): `assets/preguntas.json` v1, una por pantalla.
/// Primero las 8 de riesgo (antes del modelo): un «Sí» va directo a emergencia.
/// Luego las 6 normales, que deciden la severidad entre leve y moderada.
class CuestionarioScreen extends StatefulWidget {
  const CuestionarioScreen({super.key});

  @override
  State<CuestionarioScreen> createState() => _CuestionarioScreenState();
}

class _CuestionarioScreenState extends State<CuestionarioScreen> {
  final _preguntas = Cuestionario.instancia.preguntas;
  int _i = 0;

  Episodio get _episodio => AppState.instance.episodio;

  void _responder(Pregunta pregunta, Object valor) {
    final id = pregunta.id;
    if (pregunta.esRiesgo && valor == true) {
      AppState.instance.marcarAlarma(id);
      Navigator.pushNamed(context, Rutas.emergencia);
      return;
    }
    if (_episodio.alarma == id) _episodio.alarma = null; // volvió de emergencia y corrigió
    _episodio.respuestas[id] = valor;

    if (_i < _preguntas.length - 1) {
      setState(() => _i++);
    } else {
      Navigator.pushNamed(context, Rutas.analisis);
    }
  }

  void _atras() {
    if (_i > 0) {
      setState(() => _i--);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pregunta = _preguntas[_i];
    final alarma = pregunta.esRiesgo;
    final elegida = _episodio.respuestas[pregunta.id];

    return PopScope(
      canPop: _i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _atras();
      },
      child: Scaffold(
        body: PantallaScroll(
          children: [
            EncabezadoPaso(paso: 2, nombre: 'Preguntas', onVolver: _atras),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pregunta ${_i + 1} de ${_preguntas.length}',
                    style: AppText.cuerpo(12.5, weight: FontWeight.w600, color: AppColors.textoSuave),
                  ),
                ),
                if (alarma)
                  const Pastilla(
                    texto: 'Signo de alarma',
                    icono: Icons.warning_amber_rounded,
                    fondo: AppColors.terracotaFondo,
                    color: AppColors.terracota,
                  )
                else
                  const Pastilla(texto: 'Síntomas', fondo: AppColors.arena, color: AppColors.carameloOscuro),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (_i + 1) / _preguntas.length,
                minHeight: 5,
                backgroundColor: AppColors.borde,
              ),
            ),
            const SizedBox(height: 30),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Column(
                key: ValueKey(_i),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(pregunta.texto, style: AppText.titulo(pregunta.texto.length > 55 ? 23 : 27)),
                  if (alarma) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(Icons.info_outline_rounded, size: 17, color: AppColors.terracota),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Si respondes «Sí», te diremos que vayas a emergencia.',
                            style: AppText.cuerpo(13, color: AppColors.textoSuave),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            const SizedBox(height: 24),
            for (final (label, valor) in pregunta.botones) ...[
              _BotonOpcion(
                label: label,
                elegida: elegida == valor,
                alarma: alarma && valor == true,
                onTap: () => _responder(pregunta, valor),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _BotonOpcion extends StatelessWidget {
  const _BotonOpcion({required this.label, required this.elegida, required this.alarma, required this.onTap});

  final String label;
  final bool elegida;
  final bool alarma;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = elegida
        ? AppColors.sobreAccion
        : alarma
        ? AppColors.terracota
        : AppColors.tinta;
    final borde = elegida
        ? AppColors.tinta
        : alarma
        ? AppColors.terracotaBorde
        : AppColors.borde;

    return SizedBox(
      height: 60,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          backgroundColor: elegida ? AppColors.tinta : AppColors.superficie,
          side: BorderSide(color: borde, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: AppText.cuerpo(16, weight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}
