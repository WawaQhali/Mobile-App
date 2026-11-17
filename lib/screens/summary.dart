import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/db.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';
import 'result.dart';

/// 11 · Resumen para el médico (US10): foto, resultado y todas las respuestas,
/// para enseñarlo en la consulta o en emergencia.
class ResumenScreen extends StatelessWidget {
  const ResumenScreen({super.key});

  static Episodio? get _episodio {
    final s = AppState.instance;
    final e = s.actual ?? s.ultimo;
    return e != null && (e.resultado != null || e.hayAlarma) ? e : null;
  }

  static String _resultado(Episodio e) => e.resultado == null
      ? 'No analizado: signo de alarma'
      : Db.instance.resultado(e.resultado!.clase)['resumen'] as String;

  static String _riesgo(Episodio e) =>
      e.resultado == null ? 'Emergencia' : Db.instance.riesgo(e.resultado!.riesgo)['label'] as String;

  /// Preguntas respondidas, en orden, separadas en alarma y síntomas.
  static List<(Json, String)> _respondidas(Episodio e, String tipo) {
    final db = Db.instance;
    return [
      for (final p in db.preguntas)
        if (p['tipo'] == tipo && e.respuestas[p['id']] != null)
          (p, db.opcion(p, e.respuestas[p['id']]!)['label'] as String),
    ];
  }

  String _texto(Episodio e) {
    final lineas = [
      'Wawa Qhali · Resumen para el médico',
      '${formatoFecha(e.fecha)} · ${formatoHora(e.fecha)}',
      'Resultado: ${_resultado(e)}'
          '${e.resultado == null ? '' : ' (${etiquetaConfianza(e.resultado!.confianza).toLowerCase()})'}',
      'Nivel de riesgo: ${_riesgo(e)}',
      '',
      'Signos de alarma:',
      for (final (p, r) in _respondidas(e, 'alarma')) '- ${p['resumen']}: $r',
      if (_respondidas(e, 'sintoma').isNotEmpty) ...['', 'Síntomas:'],
      for (final (p, r) in _respondidas(e, 'sintoma')) '- ${p['resumen']}: $r',
      '',
      'Orientación preliminar: no es un diagnóstico médico.',
    ];
    return lineas.join('\n');
  }

  // Por ahora copia al portapapeles; para el menú nativo de Android: share_plus.
  Future<void> _compartir(BuildContext context, Episodio e) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _texto(e)));
    messenger.showSnackBar(const SnackBar(content: Text('Resumen copiado. Pégalo en WhatsApp o muéstralo al médico.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) {
          final e = _episodio;
          if (e == null) {
            return PantallaScroll(
              children: [
                const Align(alignment: Alignment.centerLeft, child: BotonVolver()),
                const Spacer(),
                Text('Aún no hay evaluaciones', textAlign: TextAlign.center, style: AppText.titulo(24)),
                const Spacer(),
              ],
            );
          }

          final r = e.resultado;
          final estilo = r == null
              ? (fondo: AppColors.terracotaFondo, texto: AppColors.terracota, icono: Icons.warning_amber_rounded)
              : estiloClase(r.clase);
          final alarmas = _respondidas(e, 'alarma');
          final sintomas = _respondidas(e, 'sintoma');

          return PantallaScroll(
            children: [
              Row(
                children: [
                  const BotonVolver(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Resumen para el médico', style: AppText.titulo(24)),
                        Text('${formatoFecha(e.fecha)} · ${formatoHora(e.fecha)}',
                            style: AppText.cuerpo(12.5, color: AppColors.textoSuave)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 190,
                child: e.foto == null
                    ? Container(
                        decoration: BoxDecoration(color: AppColors.arena, borderRadius: BorderRadius.circular(22)),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.hide_image_outlined, size: 32, color: AppColors.textoSuave),
                            const SizedBox(height: 8),
                            Text('Sin foto guardada', style: AppText.cuerpo(13, color: AppColors.textoSuave)),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          Positioned.fill(child: FotoLesion(bytes: e.foto, radio: 22)),
                          const Positioned(
                            left: 12,
                            bottom: 12,
                            child: Pastilla(
                              texto: 'Guardada solo en este celular',
                              icono: Icons.lock_outline_rounded,
                              fondo: AppColors.superficie,
                              color: AppColors.carameloOscuro,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              Tarjeta(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Dato('Resultado', _resultado(e)),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: AppColors.divisor),
                    ),
                    Row(
                      children: [
                        Expanded(child: _Dato('Nivel de riesgo', _riesgo(e))),
                        Pastilla(
                          texto: r == null ? 'Derivado a emergencia' : etiquetaConfianza(r.confianza),
                          fondo: estilo.fondo,
                          color: estilo.texto,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Respuestas(titulo: 'Signos de alarma', filas: alarmas),
              if (sintomas.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Respuestas(titulo: 'Síntomas', filas: sintomas),
              ],
              const SizedBox(height: 12),
              Text(
                'Solo guardamos la última foto, en este celular; se reemplaza en tu siguiente evaluación. '
                'Este resumen es una orientación preliminar, no un diagnóstico médico.',
                style: AppText.cuerpo(11.5, color: AppColors.textoSuave, height: 1.5),
              ),
              const Spacer(),
              const SizedBox(height: 18),
              BotonPrincipal(label: 'Compartir', icono: Icons.ios_share_rounded, onPressed: () => _compartir(context, e)),
              const SizedBox(height: 10),
              BotonSecundario(
                label: 'Borrar foto del celular',
                icono: Icons.delete_outline_rounded,
                color: AppColors.terracota,
                onPressed: e.foto == null ? null : AppState.instance.borrarFoto,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.label, this.valor);

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.cuerpo(12, color: AppColors.textoSuave)),
        const SizedBox(height: 2),
        Text(valor, style: AppText.cuerpo(15, weight: FontWeight.w700)),
      ],
    );
  }
}

class _Respuestas extends StatelessWidget {
  const _Respuestas({required this.titulo, required this.filas});

  final String titulo;
  final List<(Json, String)> filas;

  @override
  Widget build(BuildContext context) {
    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: AppText.cuerpo(14, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          ListaConDivisores(
            children: [
              for (final (p, respuesta) in filas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(child: Text(p['resumen'] as String, style: AppText.cuerpo(13))),
                      const SizedBox(width: 10),
                      Text(
                        respuesta,
                        style: AppText.cuerpo(13,
                            weight: FontWeight.w700,
                            color: p['tipo'] == 'alarma' && respuesta == 'Sí' ? AppColors.terracota : AppColors.tinta),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
