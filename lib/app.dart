import 'package:flutter/material.dart';

import 'routes.dart';
import 'screens/analysis.dart';
import 'screens/welcome.dart';
import 'screens/camera.dart';
import 'screens/child_data.dart';
import 'screens/health_centers.dart';
import 'screens/questionnaire.dart';
import 'screens/donation.dart';
import 'screens/emergency.dart';
import 'screens/home_shell.dart';
import 'screens/permissions.dart';
import 'screens/result.dart';
import 'screens/summary.dart';
import 'screens/photo_validation.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

class WawaQhaliApp extends StatelessWidget {
  const WawaQhaliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wawa Qhali',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Si ya aceptó los términos en otra sesión, entra directo a Inicio.
      initialRoute: AppState.instance.terminosAceptados ? Rutas.home : Rutas.bienvenida,
      routes: {
        Rutas.bienvenida: (_) => const BienvenidaScreen(),
        Rutas.donacion: (_) => const DonacionScreen(),
        Rutas.permisos: (_) => const PermisosScreen(),
        Rutas.home: (_) => const HomeShell(),
        Rutas.camara: (_) => const CamaraScreen(),
        Rutas.validacion: (_) => const ValidacionScreen(),
        Rutas.datosNino: (_) => const DatosNinoScreen(),
        Rutas.cuestionario: (_) => const CuestionarioScreen(),
        Rutas.emergencia: (_) => const EmergenciaScreen(),
        Rutas.analisis: (_) => const AnalisisScreen(),
        Rutas.resultado: (_) => const ResultadoScreen(),
        Rutas.resumen: (_) => const ResumenScreen(),
        Rutas.centros: (_) => const Scaffold(body: SafeArea(child: CentrosScreen(conVolver: true))),
      },
    );
  }
}
