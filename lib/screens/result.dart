import 'package:flutter/material.dart';

import '../data/cuestionario.dart';
import '../data/db.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/recommendations.dart';
import '../widgets/shared.dart';
import '../widgets/zona_evaluada.dart';

/// Colores e ícono según la clase que devuelve el modelo.
({Color fondo, Color texto, IconData icono}) estiloClase(String clase) => switch (clase) {
  'compatible' => (
    fondo: AppColors.carameloFondo,
    texto: AppColors.carameloOscuro,
    icono: Icons.check_circle_outline_rounded,
  ),
  'no_compatible' => (
    fondo: AppColors.olivaFondo,
    texto: AppColors.olivaTexto,
    icono: Icons.remove_circle_outline_rounded,
  ),
  _ => (fondo: AppColors.ambarFondo, texto: AppColors.ambarTexto, icono: Icons.help_outline_rounded),
};

/// 10 · Resultado, paso 4 (US07, US08).
class ResultadoScreen extends StatelessWidget {
  const ResultadoScreen({super.key});

  void _terminar(BuildContext context) {
    AppState.instance.terminarEpisodio();
    Navigator.pushNamedAndRemoveUntil(context, Rutas.home, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final e = AppState.instance.actual ?? AppState.instance.ultimo;
    final r = e?.resultado;
    final o = e?.orientacion;
    if (r == null || o == null) {
      return Scaffold(
        body: Center(
          child: BotonTexto(label: 'No hay resultado. Volver al inicio', onPressed: () => _terminar(context)),
        ),
      );
    }

    final info = Db.instance.resultado(r.clase);
    final severidad = Db.instance.severidad(o.severidad);
    final nivel = severidad['nivel'] as int;
    final estilo = estiloClase(r.clase);
    final colores = colorSeveridad(o.severidad);
    final motivos = Cuestionario.instancia.motivosSeveridad(e!.respuestas, r.clase, sinRonchas: r.corregidaPorRonchas);

    return Scaffold(
      body: PantallaScroll(
        children: [
          EncabezadoPaso(
            paso: 4,
            nombre: 'Resultado',
            iconoVolver: Icons.close_rounded,
            onVolver: () => _terminar(context),
          ),
          const SizedBox(height: 18),
          Tarjeta(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: estilo.fondo, borderRadius: BorderRadius.circular(16)),
                      child: Icon(estilo.icono, size: 26, color: estilo.texto),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¿COMPATIBLE CON URTICARIA AGUDA?',
                            style: AppText.cuerpo(
                              10.5,
                              weight: FontWeight.w700,
                              color: AppColors.textoSuave,
                            ).copyWith(letterSpacing: 1.1),
                          ),
                          const SizedBox(height: 4),
                          Text(info['respuesta'] as String, style: AppText.titulo(21)),
                          const SizedBox(height: 6),
                          Pastilla(texto: etiquetaConfianza(r.confianza), fondo: estilo.fondo, color: estilo.texto),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  info['descripcion'] as String,
                  style: AppText.cuerpo(13, color: AppColors.textoSuave, height: 1.5),
                ),
                // Para saber qué modelo dio el resultado al revisar casos (pruebas, informe).
                // D42: la respuesta «no veo ronchas» corrigió al modelo; se dice con claridad.
                if (r.corregidaPorRonchas) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Indicaste que no ves ronchas, así que no lo tomamos como urticaria. '
                    'El análisis de la foto decía: ${Db.instance.resultado(r.claseModelo!)['respuesta']}.',
                    key: const Key('resultado-corregido'),
                    style: AppText.cuerpo(12.5, color: AppColors.textoSuave, height: 1.4),
                  ),
                ],
                if (r.modelo != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Modelo ${r.modelo} · ${(r.confianza * 100).round()} %',
                    key: const Key('resultado-modelo'),
                    style: AppText.cuerpo(11.5, color: AppColors.textoSuave),
                  ),
                ],
              ],
            ),
          ),
          if (e.foto != null && e.zona != null && e.zona!.tieneContorno) ...[
            const SizedBox(height: 12),
            ZonaEvaluada(foto: e.foto!, zona: e.zona!),
          ],
          const SizedBox(height: 12),
          Tarjeta(
            color: AppColors.arena,
            borde: null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Según tus respuestas y el análisis de la foto',
                  style: AppText.cuerpo(11.5, color: AppColors.textoSuave),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Severidad', style: AppText.cuerpo(14, weight: FontWeight.w700)),
                    Text(
                      severidad['label'] as String,
                      style: AppText.cuerpo(14, weight: FontWeight.w700, color: colores.texto),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 1; i <= 3; i++) ...[
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: i <= nivel ? colores.barra : AppColors.barraVacia,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      if (i < 3) const SizedBox(width: 5),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(severidad['descripcion'] as String, style: AppText.cuerpo(12.5, color: AppColors.textoSuave)),
                if (motivos.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Por qué: ${motivos.join(' · ')}',
                    style: AppText.cuerpo(12, weight: FontWeight.w600, color: colores.texto),
                  ),
                ],
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppColors.tostado),
                const SizedBox(height: 12),
                Text('Recomendación', style: AppText.cuerpo(14, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                ListaRecomendaciones(o),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: AppState.instance,
            builder: (context, _) => switch (e.donacion) {
              'enviando' => const _EstadoDonacion(Icons.lock_clock_outlined, 'Cifrando y donando tu foto…'),
              'enviada' => const _EstadoDonacion(Icons.lock_outline_rounded, 'Foto donada, cifrada y anónima. ¡Gracias!'),
              'pendiente' => const _EstadoDonacion(Icons.schedule_rounded, 'Tu foto quedó cifrada en el celular y se donará cuando haya conexión.'),
              'fallo' => const _EstadoDonacion(Icons.cloud_off_outlined, 'No se pudo donar la foto esta vez.'),
              _ => const SizedBox.shrink(),
            },
          ),
          const SizedBox(height: 12),
          Text.rich(
            const TextSpan(
              children: [
                TextSpan(
                  text: 'Aviso: ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text:
                      'esta orientación no es un diagnóstico médico ni reemplaza la consulta con un profesional de salud.',
                ),
              ],
            ),
            style: AppText.cuerpo(11.5, color: AppColors.textoSuave, height: 1.5),
          ),
          const Spacer(),
          const SizedBox(height: 18),
          BotonSecundario(
            label: 'Ver centros de salud cercanos',
            icono: Icons.location_on_outlined,
            onPressed: () => Navigator.pushNamed(context, Rutas.centros),
          ),
          const SizedBox(height: 10),
          BotonSecundario(
            label: 'Resumen para el médico',
            icono: Icons.assignment_outlined,
            onPressed: () => Navigator.pushNamed(context, Rutas.resumen),
          ),
          const SizedBox(height: 10),
          BotonPrincipal(label: 'Terminar', onPressed: () => _terminar(context)),
        ],
      ),
    );
  }
}

class _EstadoDonacion extends StatelessWidget {
  const _EstadoDonacion(this.icono, this.texto);

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Pastilla(texto: texto, icono: icono, fondo: AppColors.olivaFondo, color: AppColors.olivaTexto),
    );
  }
}
