import 'package:flutter/material.dart';

import '../data/db.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Colores de cada nivel de severidad.
({Color barra, Color texto}) colorSeveridad(String severidad) => switch (severidad) {
  'alta' => (barra: AppColors.terracota, texto: AppColors.terracota),
  'moderada' => (barra: AppColors.ambar, texto: AppColors.ambarTexto),
  _ => (barra: AppColors.oliva, texto: AppColors.olivaTexto),
};

String etiquetaSeveridad(String severidad) => Db.instance.severidad(severidad)['label'] as String;

/// "Fuente: guia-urticaria#3" -> "guia urticaria".
String _documento(String fuente) => fuente.split('#').first.replaceAll('-', ' ');

/// Lista de recomendaciones y, debajo, de dónde salieron.
class ListaRecomendaciones extends StatelessWidget {
  const ListaRecomendaciones(this.orientacion, {super.key, this.colorPunto = AppColors.caramelo});

  final Orientacion orientacion;
  final Color colorPunto;

  @override
  Widget build(BuildContext context) {
    final documentos = {for (final f in orientacion.fuentes) _documento(f)}.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rec in orientacion.recomendaciones)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: colorPunto, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(rec, style: AppText.cuerpo(13))),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              orientacion.delBackend ? Icons.menu_book_outlined : Icons.cloud_off_outlined,
              size: 14,
              color: AppColors.textoSuave,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                orientacion.delBackend
                    ? 'Según guías clínicas validadas: ${documentos.join(', ')}'
                    : 'Recomendaciones generales: no pudimos conectarnos con el servidor.',
                style: AppText.cuerpo(11.5, color: AppColors.textoSuave),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
