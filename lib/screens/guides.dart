import 'package:flutter/material.dart';

import '../data/db.dart';
import '../services/links.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

/// 13 · Guías (US09): secciones desplegables, funciona sin internet.
class GuiasScreen extends StatelessWidget {
  const GuiasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final abierta = AppState.instance.guiaAbierta;
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
          children: [
            Row(
              children: [
                Expanded(child: Text('Guías', style: AppText.titulo(32))),
              ],
            ),
            const SizedBox(height: 18),
            for (final g in Db.instance.guias) ...[
              _GuiaDesplegable(guia: g, abierta: abierta == g['id']),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _GuiaDesplegable extends StatelessWidget {
  const _GuiaDesplegable({required this.guia, required this.abierta});

  final Json guia;
  final bool abierta;

  @override
  Widget build(BuildContext context) {
    final alarma = guia['alarma'] as bool;
    final puntos = (guia['puntos'] as List).cast<String>();
    final texto = guia['texto'] as String;
    final samu = Db.instance.app['samu'] as String;

    return Tarjeta(
      color: alarma ? AppColors.terracotaFondo : AppColors.superficie,
      borde: alarma ? AppColors.terracotaBorde : AppColors.borde,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => AppState.instance.abrirGuia(abierta ? null : guia['id'] as String),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: alarma ? AppColors.terracota : AppColors.arena,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(iconoGuia(guia['icono'] as String),
                        size: 19, color: alarma ? AppColors.sobreAccion : AppColors.caramelo),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      guia['titulo'] as String,
                      style: AppText.cuerpo(14.5,
                          weight: FontWeight.w700, color: alarma ? AppColors.terracotaTexto : AppColors.tinta),
                    ),
                  ),
                  AnimatedRotation(
                    turns: abierta ? .5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: !abierta
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final p in puntos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: alarma ? AppColors.terracota : AppColors.caramelo,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(p, style: AppText.cuerpo(13.5))),
                              ],
                            ),
                          ),
                        if (texto.isNotEmpty)
                          Text(texto, style: AppText.cuerpo(13.5, color: const Color(0xFF4E4136), height: 1.5)),
                        if (alarma) ...[
                          const SizedBox(height: 14),
                          BotonPrincipal(
                            label: 'Llamar al SAMU · $samu',
                            icono: Icons.call_outlined,
                            alto: 50,
                            color: AppColors.terracota,
                            onPressed: () => llamar(context, samu),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
