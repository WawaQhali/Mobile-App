import 'package:flutter/material.dart';

import '../data/db.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

/// 02 · Donación opcional de fotos. Ambos botones siguen a Permisos.
class DonacionScreen extends StatefulWidget {
  const DonacionScreen({super.key});

  @override
  State<DonacionScreen> createState() => _DonacionScreenState();
}

class _DonacionScreenState extends State<DonacionScreen> {
  bool _consiento = false;

  bool _enviando = false;

  /// Registra la autorización en el backend. Si falla, sigue igual sin donar y avisa.
  Future<void> _seguir(bool donar) async {
    if (donar) {
      setState(() => _enviando = true);
      final error = await AppState.instance.setDonarFotos(true);
      if (!mounted) return;
      setState(() => _enviando = false);
      if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
    if (mounted) Navigator.pushNamed(context, Rutas.permisos);
  }

  @override
  Widget build(BuildContext context) {
    const garantias = [
      (Icons.lock_outline_rounded, 'Se cifran antes de salir de tu celular'),
      (Icons.visibility_off_outlined, 'Sin rostro, ubicación ni datos personales'),
      (Icons.medical_services_outlined, 'Personal de salud las revisa y etiqueta'),
    ];

    return Scaffold(
      body: PantallaScroll(
        children: [
          Row(
            children: [
              const BotonVolver(),
              const SizedBox(width: 14),
              const Expanded(child: IndicadorOnboarding(actual: 1)),
              const Pastilla(texto: 'Opcional', fondo: AppColors.olivaFondo, color: AppColors.olivaTexto),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(color: AppColors.arena, shape: BoxShape.circle),
              child: const Icon(Icons.health_and_safety_outlined, size: 72, color: AppColors.caramelo),
            ),
          ),
          const SizedBox(height: 18),
          Text('¿Nos ayudas a mejorar Wawa Qhali?', textAlign: TextAlign.center, style: AppText.titulo(27)),
          const SizedBox(height: 8),
          Text(
            'Puedes donar las fotos que analices para que el modelo aprenda a orientar mejor a otras familias.',
            textAlign: TextAlign.center,
            style: AppText.cuerpo(13.5, color: AppColors.textoSuave, height: 1.5),
          ),
          const SizedBox(height: 18),
          Tarjeta(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListaConDivisores(
              children: [
                for (final (icono, texto) in garantias)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      children: [
                        _IconoCaja(icono),
                        const SizedBox(width: 12),
                        Expanded(child: Text(texto, style: AppText.cuerpo(13, weight: FontWeight.w500))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.ambarFondo, borderRadius: BorderRadius.circular(16)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.face_retouching_off_outlined, size: 20, color: AppColors.ambarTexto),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(Db.instance.app['avisoRostro'] as String,
                      style: AppText.cuerpo(12.5, color: AppColors.ambarTexto, height: 1.45)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _consiento = !_consiento),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Checkbox(value: _consiento, onChanged: (v) => setState(() => _consiento = v ?? false)),
                Expanded(
                  child: Text('Acepto donar mis fotos de forma anónima.',
                      style: AppText.cuerpo(13, weight: FontWeight.w500)),
                ),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(height: 18),
          BotonPrincipal(
            label: _enviando ? 'Registrando…' : 'Donar mis fotos',
            onPressed: _consiento && !_enviando ? () => _seguir(true) : null,
          ),
          BotonTexto(label: 'Ahora no', onPressed: () => _seguir(false)),
          Text('Puedes cambiar este permiso luego en Ajustes.',
              textAlign: TextAlign.center, style: AppText.cuerpo(11.5, color: AppColors.textoSuave)),
        ],
      ),
    );
  }
}

class _IconoCaja extends StatelessWidget {
  const _IconoCaja(this.icono);

  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: AppColors.arena, borderRadius: BorderRadius.circular(12)),
      child: Icon(icono, size: 18, color: AppColors.caramelo),
    );
  }
}
