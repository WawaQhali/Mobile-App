import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../routes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

/// 06c · Datos de la wawa, paso 2, antes del cuestionario: sexo y edad (1 a 4 años).
/// Se envían al backend (orientación y donación, para el modelo) y salen en el resumen.
class DatosNinoScreen extends StatefulWidget {
  const DatosNinoScreen({super.key});

  @override
  State<DatosNinoScreen> createState() => _DatosNinoScreenState();
}

class _DatosNinoScreenState extends State<DatosNinoScreen> {
  static final _edades = [for (var e = AppState.edadMinima; e <= AppState.edadMaxima; e++) e];

  // Si ya hubo una evaluación, se proponen los mismos datos (suele ser la misma wawa).
  late String? _sexo = AppState.instance.episodio.sexo ?? AppState.instance.ultimo?.sexo;
  late int _edad = _edadInicial();
  late final _rueda = FixedExtentScrollController(initialItem: _edades.indexOf(_edad));

  int _edadInicial() {
    final e = AppState.instance.episodio.edadAnios ?? AppState.instance.ultimo?.edadAnios;
    return e != null && _edades.contains(e) ? e : AppState.edadMinima;
  }

  @override
  void dispose() {
    _rueda.dispose();
    super.dispose();
  }

  void _continuar() {
    AppState.instance.guardarDatosNino(edadAnios: _edad, sexo: _sexo!);
    Navigator.pushNamed(context, Rutas.cuestionario);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PantallaScroll(
        children: [
          const EncabezadoPaso(paso: 2, nombre: 'Tu wawa'),
          const SizedBox(height: 22),
          Text('Cuéntanos sobre tu wawa', style: AppText.titulo(27)),
          const SizedBox(height: 6),
          Text(
            'Con su edad y si es niña o niño te orientamos mejor.',
            style: AppText.cuerpo(13, color: AppColors.textoSuave, height: 1.5),
          ),
          const SizedBox(height: 24),
          Text('¿Es niña o niño?', style: AppText.cuerpo(14, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _OpcionSexo(
                  label: 'Niña',
                  icono: Icons.girl_rounded,
                  elegida: _sexo == 'femenino',
                  onTap: () => setState(() => _sexo = 'femenino'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OpcionSexo(
                  label: 'Niño',
                  icono: Icons.boy_rounded,
                  elegida: _sexo == 'masculino',
                  onTap: () => setState(() => _sexo = 'masculino'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('¿Cuántos años tiene?', style: AppText.cuerpo(14, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          _RuedaEdad(
            controlador: _rueda,
            edades: _edades,
            elegida: _edad,
            onCambio: (e) {
              HapticFeedback.selectionClick();
              setState(() => _edad = e);
            },
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textoSuave),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Wawa Qhali es para niñas y niños de 1 a 4 años. Si tu wawa es menor o mayor, consulta con un médico.',
                  style: AppText.cuerpo(12, color: AppColors.textoSuave, height: 1.45),
                ),
              ),
            ],
          ),
          const Spacer(),
          const SizedBox(height: 20),
          BotonPrincipal(label: 'Continuar', onPressed: _sexo == null ? null : _continuar),
        ],
      ),
    );
  }
}

class _OpcionSexo extends StatelessWidget {
  const _OpcionSexo({required this.label, required this.icono, required this.elegida, required this.onTap});

  final String label;
  final IconData icono;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegida,
      child: Material(
        color: elegida ? AppColors.tinta : AppColors.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: elegida ? AppColors.tinta : AppColors.borde, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SizedBox(
            height: 92,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icono, size: 34, color: elegida ? AppColors.sobreAccion : AppColors.caramelo),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: AppText.cuerpo(15, weight: FontWeight.w600, color: elegida ? AppColors.sobreAccion : AppColors.tinta),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rueda de edad: solo 1, 2, 3 y 4 años (no se puede elegir otra).
class _RuedaEdad extends StatelessWidget {
  const _RuedaEdad({required this.controlador, required this.edades, required this.elegida, required this.onCambio});

  final FixedExtentScrollController controlador;
  final List<int> edades;
  final int elegida;
  final ValueChanged<int> onCambio;

  static const _alto = 168.0;
  static const _altoItem = 48.0;

  @override
  Widget build(BuildContext context) {
    // Alto fijo: la pantalla usa IntrinsicHeight y la rueda no puede medirse sola.
    return SizedBox(
      height: _alto,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: _altoItem,
            decoration: BoxDecoration(
              color: AppColors.arena,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.tostado),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: controlador,
            itemExtent: _altoItem,
            diameterRatio: 1.6,
            perspective: 0.004,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (i) => onCambio(edades[i]),
            childDelegate: ListWheelChildListDelegate(
              children: [
                for (final e in edades)
                  Center(
                    child: Text(
                      '$e ${e == 1 ? 'año' : 'años'}',
                      style: AppText.cuerpo(
                        e == elegida ? 20 : 17,
                        weight: e == elegida ? FontWeight.w700 : FontWeight.w500,
                        color: e == elegida ? AppColors.tinta : AppColors.textoSuave,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
