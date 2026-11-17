import 'package:flutter/material.dart';

import '../routes.dart';
import '../theme/app_theme.dart';
import 'settings.dart';
import 'health_centers.dart';
import 'guides.dart';
import 'home.dart';

/// Inicio, Guías, Centros y Ajustes con la barra inferior y el botón central de evaluar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _irA(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            InicioScreen(onIrATab: _irA),
            const GuiasScreen(),
            const CentrosScreen(),
            const AjustesScreen(),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox(
        width: 62,
        height: 62,
        child: FloatingActionButton(
          onPressed: () => Navigator.pushNamed(context, Rutas.camara),
          tooltip: 'Evaluar lesión',
          elevation: 0,
          backgroundColor: AppColors.caramelo,
          foregroundColor: AppColors.sobreAccion,
          shape: const CircleBorder(side: BorderSide(color: AppColors.crema, width: 4)),
          child: const Icon(Icons.photo_camera_outlined, size: 26),
        ),
      ),
      bottomNavigationBar: _BarraNavegacion(actual: _tab, onTab: _irA),
    );
  }
}

class _BarraNavegacion extends StatelessWidget {
  const _BarraNavegacion({required this.actual, required this.onTab});

  final int actual;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icono, IconData iconoActivo, String label) {
      final activo = i == actual;
      final color = activo ? AppColors.caramelo : AppColors.textoSuave;
      return Expanded(
        child: InkWell(
          onTap: () => onTab(i),
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(activo ? iconoActivo : icono, size: 22, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: AppText.cuerpo(11, weight: activo ? FontWeight.w700 : FontWeight.w500, color: color, height: 1),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.superficie,
        border: Border(top: BorderSide(color: AppColors.borde)),
      ),
      padding: EdgeInsets.fromLTRB(10, 6, 10, 6 + MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: [
          item(0, Icons.home_outlined, Icons.home_rounded, 'Inicio'),
          item(1, Icons.menu_book_outlined, Icons.menu_book_rounded, 'Guías'),
          const Expanded(child: SizedBox()),
          item(2, Icons.location_on_outlined, Icons.location_on_rounded, 'Centros'),
          item(3, Icons.tune_outlined, Icons.tune_rounded, 'Ajustes'),
        ],
      ),
    );
  }
}
