import 'package:flutter/material.dart';

import '../routes.dart';
import '../services/classifier_service.dart';
import '../services/donation_service.dart';
import '../services/recommendation_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

/// 09 · Análisis local, paso 3 (US06).
class AnalisisScreen extends StatefulWidget {
  const AnalisisScreen({super.key});

  @override
  State<AnalisisScreen> createState() => _AnalisisScreenState();
}

class _AnalisisScreenState extends State<AnalisisScreen> with SingleTickerProviderStateMixin {
  late final _progreso = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..forward();
  bool _resultadoListo = false;
  bool _buscandoRecomendaciones = false;

  static const _etapas = [
    ('Preparando la imagen', .30),
    ('Revisando relieve, color y bordes', .65),
    ('Comparando con patrones de urticaria', 1.0),
  ];

  @override
  void initState() {
    super.initState();
    _analizar();
  }

  Future<void> _analizar() async {
    final e = AppState.instance.episodio;
    // Modelo TFLite en el celular sobre el recorte de 1024 px.
    final prediccion = await Clasificador.instancia.clasificar(e.foto!);
    final resultado = ResultadoAnalisis(clase: prediccion.clase, confianza: prediccion.confianza);
    if (mounted) setState(() => _buscandoRecomendaciones = true);
    // Severidad en la app; recomendaciones del backend (LLM + RAG) o, si falla, locales.
    final orientacion = await RecomendacionService.orientar(e, resultado: resultado);
    if (!mounted) return;
    await AppState.instance.guardarResultado(resultado, orientacion);
    // Si el padre aceptó donar: se cifra y se envía en segundo plano (sección 6).
    DonacionService.donarSiCorresponde(e);
    if (mounted) setState(() => _resultadoListo = true);
  }

  @override
  void dispose() {
    _progreso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foto = AppState.instance.episodio.foto;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _progreso,
        builder: (context, _) {
          final p = _progreso.value;
          final listo = p >= 1 && _resultadoListo;

          return PantallaScroll(
            children: [
              const EncabezadoPaso(paso: 3, nombre: 'Análisis', volver: false),
              const Spacer(),
              const SizedBox(height: 18),
              Center(
                child: SizedBox(
                  width: 216,
                  height: 216,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: p,
                          strokeWidth: 8,
                          strokeCap: StrokeCap.round,
                          backgroundColor: AppColors.borde,
                        ),
                      ),
                      ClipOval(
                        child: SizedBox(width: 150, height: 150, child: FotoLesion(bytes: foto)),
                      ),
                      Positioned(
                        bottom: 4,
                        right: 18,
                        child: Pastilla(
                          texto: '${(p * 100).round()}%',
                          fondo: AppColors.tinta,
                          color: AppColors.sobreAccion,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                listo ? 'Análisis listo' : 'Analizando la foto…',
                textAlign: TextAlign.center,
                style: AppText.titulo(27),
              ),
              const SizedBox(height: 6),
              Text(
                p >= 1 && !listo && _buscandoRecomendaciones
                    ? 'Buscando recomendaciones en las guías clínicas…'
                    : 'En tu celular, en menos de 3 segundos',
                textAlign: TextAlign.center,
                style: AppText.cuerpo(13, color: AppColors.textoSuave),
              ),
              const SizedBox(height: 26),
              Tarjeta(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListaConDivisores(
                  children: [for (final (label, umbral) in _etapas) _FilaEtapa(label: label, hecha: p >= umbral)],
                ),
              ),
              const Spacer(),
              const SizedBox(height: 18),
              if (listo) ...[
                BotonPrincipal(
                  label: 'Ver resultado',
                  onPressed: () => Navigator.pushReplacementNamed(context, Rutas.resultado),
                ),
                const SizedBox(height: 12),
              ],
              const Center(
                child: Pastilla(
                  texto: 'Tu foto no sale de tu celular',
                  icono: Icons.lock_outline_rounded,
                  fondo: AppColors.olivaFondo,
                  color: AppColors.olivaTexto,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilaEtapa extends StatelessWidget {
  const _FilaEtapa({required this.label, required this.hecha});

  final String label;
  final bool hecha;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: hecha ? AppColors.oliva : Colors.transparent,
              shape: BoxShape.circle,
              border: hecha ? null : Border.all(color: AppColors.tostado, width: 2),
            ),
            child: hecha ? const Icon(Icons.check_rounded, size: 15, color: AppColors.sobreAccion) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppText.cuerpo(
                13.5,
                weight: FontWeight.w500,
                color: hecha ? AppColors.tinta : AppColors.textoSuave,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
