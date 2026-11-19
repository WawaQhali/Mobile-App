import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/cuestionario.dart';
import '../data/db.dart';
import '../routes.dart';
import '../services/links.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';
import '../widgets/illustrations.dart';

/// 01 · Bienvenida (US01). «Comenzar» abre el pop-up de aceptación (01b).
class BienvenidaScreen extends StatelessWidget {
  const BienvenidaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PantallaScroll(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        children: [
          const Align(alignment: Alignment.centerLeft, child: LogoWawa()),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 200,
              height: 200,
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.only(bottom: 4),
              decoration: const BoxDecoration(color: AppColors.arena, shape: BoxShape.circle),
              child: const WawaIlustracion(width: 126),
            ),
          ),
          const SizedBox(height: 24),
          Text('Cuidamos la piel\nde tu wawa', textAlign: TextAlign.center, style: AppText.titulo(30)),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Orientación inmediata ante ronchas en niños de 1 a 4 años, desde tu casa.',
              textAlign: TextAlign.center,
              style: AppText.cuerpo(14, color: AppColors.textoSuave, height: 1.5),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: _Rasgo(icono: Icons.photo_camera_outlined, texto: 'Una foto')),
              const SizedBox(width: 8),
              Expanded(
                child: _Rasgo(icono: Icons.checklist_rounded, texto: '${Cuestionario.instancia.preguntas.length} preguntas'),
              ),
              const SizedBox(width: 8),
              const Expanded(child: _Rasgo(icono: Icons.favorite_border_rounded, texto: 'Orientación')),
            ],
          ),
          const Spacer(),
          const SizedBox(height: 20),
          const AvisoLegal(),
          const SizedBox(height: 14),
          BotonPrincipal(
            label: 'Comenzar',
            iconoFinal: Icons.arrow_forward_rounded,
            onPressed: () => showDialog<void>(
              context: context,
              barrierColor: AppColors.tinta.withValues(alpha: .55),
              builder: (_) => const TerminosDialog(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rasgo extends StatelessWidget {
  const _Rasgo({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Tarjeta(
      radio: 16,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        children: [
          Icon(icono, size: 22, color: AppColors.caramelo),
          const SizedBox(height: 6),
          Text(texto, style: AppText.cuerpo(12, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 01b · Pop-up de aceptación. Los enlaces abren la web en el navegador.
class TerminosDialog extends StatefulWidget {
  const TerminosDialog({super.key});

  @override
  State<TerminosDialog> createState() => _TerminosDialogState();
}

class _TerminosDialogState extends State<TerminosDialog> {
  bool _acepto = false;
  late final _tyc = TapGestureRecognizer()
    ..onTap = () => abrirUrl(context, Db.instance.app['terminosUrl'] as String);
  late final _privacidad = TapGestureRecognizer()
    ..onTap = () => abrirUrl(context, Db.instance.app['privacidadUrl'] as String);

  @override
  void dispose() {
    _tyc.dispose();
    _privacidad.dispose();
    super.dispose();
  }

  void _continuar() {
    AppState.instance.aceptarTerminos();
    final nav = Navigator.of(context);
    nav.pop();
    nav.pushNamed(Rutas.donacion);
  }

  @override
  Widget build(BuildContext context) {
    final enlace = AppText.cuerpo(13.5, weight: FontWeight.w700, color: const Color(0xFF6E4529))
        .copyWith(decoration: TextDecoration.underline);

    return Dialog(
      backgroundColor: AppColors.crema,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(color: AppColors.arena, shape: BoxShape.circle),
                child: const Icon(Icons.verified_user_outlined, size: 28, color: AppColors.caramelo),
              ),
            ),
            const SizedBox(height: 16),
            Text('Antes de empezar', textAlign: TextAlign.center, style: AppText.titulo(25)),
            const SizedBox(height: 6),
            Text('Para usar Wawa Qhali necesitas aceptar:',
                textAlign: TextAlign.center, style: AppText.cuerpo(13, color: AppColors.textoSuave)),
            const SizedBox(height: 16),
            Tarjeta(
              radio: 18,
              padding: const EdgeInsets.all(14),
              onTap: () => setState(() => _acepto = !_acepto),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(value: _acepto, onChanged: (v) => setState(() => _acepto = v ?? false)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Acepto los '),
                        TextSpan(text: 'Términos y condiciones', style: enlace, recognizer: _tyc),
                        const TextSpan(text: ' y la '),
                        TextSpan(text: 'Política de privacidad', style: enlace, recognizer: _privacidad),
                      ]),
                      style: AppText.cuerpo(13.5, height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.textoSuave),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Los enlaces se abren en tu navegador',
                      style: AppText.cuerpo(11.5, color: AppColors.textoSuave)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            BotonPrincipal(label: 'Continuar', alto: 52, onPressed: _acepto ? _continuar : null),
            BotonTexto(label: 'Cancelar', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}
