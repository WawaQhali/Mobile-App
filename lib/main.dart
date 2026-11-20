import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/cuestionario.dart';
import 'data/db.dart';
import 'services/donation_service.dart';
import 'services/model_update_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.cargar();
  await Cuestionario.cargar();
  await AppState.instance.cargar(); // installation_id, preferencias y última evaluación
  await AppState.instance.actualizarPermisos();
  // Al volver a la app (p. ej. desde los ajustes del celular) se releen los permisos, se
  // reintentan las donaciones pendientes y se revisa si hay un modelo nuevo.
  AppLifecycleListener(onResume: () {
    AppState.instance.actualizarPermisos();
    unawaited(DonacionService.reintentarPendientes());
    unawaited(ActualizadorModelo.revisarEnSegundoPlano());
  });
  runApp(const WawaQhaliApp());
  unawaited(DonacionService.reintentarPendientes());
  unawaited(ActualizadorModelo.revisarEnSegundoPlano());
}
