import 'package:flutter/material.dart';

import 'app.dart';
import 'data/cuestionario.dart';
import 'data/db.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.cargar();
  await Cuestionario.cargar();
  await AppState.instance.cargar(); // installation_id, preferencias y última evaluación
  await AppState.instance.actualizarPermisos();
  // Al volver a la app (p. ej. desde los ajustes del celular) se releen los permisos.
  AppLifecycleListener(onResume: AppState.instance.actualizarPermisos);
  runApp(const WawaQhaliApp());
}
