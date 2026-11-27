import 'package:flutter/material.dart';

import '../data/cuestionario.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

/// 07 · Cuestionario, paso 2 (US04, US05): `assets/preguntas.json` v1, una por pantalla.
/// Primero las 8 de riesgo (antes del modelo): un «Sí» va directo a emergencia.
/// Luego las 6 normales, que deciden la severidad entre leve y moderada.
/// En pantalla NO se distingue el tipo (sin «Signo de alarma» ni «Síntomas», y el «Sí»
/// se ve igual en todas): leerlo puede asustar al papá o la mamá. El tipo solo se usa
/// por dentro, para mandar a emergencia y calcular la severidad.
class CuestionarioScreen extends StatefulWidget {
  const CuestionarioScreen({super.key});

  @override
  State<CuestionarioScreen> createState() => _CuestionarioScreenState();
}

class _CuestionarioScreenState extends State<CuestionarioScreen> {
  // Las 14 del cuestionario v1 y, al final, «¿Ves ronchas?» (D42, no se envía al backend).
  final _preguntas = Cuestionario.instancia.preguntasEnPantalla;
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
    if (id == Cuestionario.preguntaRonchas.id) {
      _episodio.veRonchas = valor as String;
    } else {
      _episodio.respuestas[id] = valor;
    }

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
    final elegida =
        pregunta.id == Cuestionario.preguntaRonchas.id ? _episodio.veRonchas : _episodio.respuestas[pregunta.id];

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
            Text(
              'Pregunta ${_i + 1} de ${_preguntas.length}',
              style: AppText.cuerpo(12.5, weight: FontWeight.w600, color: AppColors.textoSuave),
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
              child: Text(
                pregunta.texto,
                key: ValueKey(_i),
                style: AppText.titulo(pregunta.texto.length > 55 ? 23 : 27),
              ),
            ),
            const Spacer(),
            const SizedBox(height: 24),
            for (final (label, valor) in pregunta.botones) ...[
              _BotonOpcion(
                label: label,
                elegida: elegida == valor,
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
  const _BotonOpcion({required this.label, required this.elegida, required this.onTap});

  final String label;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = elegida ? AppColors.sobreAccion : AppColors.tinta;
    final borde = elegida ? AppColors.tinta : AppColors.borde;

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
