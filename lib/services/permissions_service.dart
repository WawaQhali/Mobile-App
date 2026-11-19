import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../state/app_state.dart';

enum ResultadoPermiso { concedido, denegado, bloqueado }

/// Permisos reales del sistema (Android). Los ids son los de `db.json -> permisos`.
abstract class Permisos {
  static Permisos instancia = PermisosSistema();

  Future<bool> concedido(String id);
  Future<ResultadoPermiso> solicitar(String id);
  Future<void> abrirAjustes();
}

class PermisosSistema implements Permisos {
  static Permission _permiso(String id) => switch (id) {
        'camara' => Permission.camera,
        'telefono' => Permission.phone, // CALL_PHONE en el manifest
        'ubicacion' => Permission.locationWhenInUse,
        _ => throw ArgumentError('Permiso desconocido: $id'),
      };

  @override
  Future<bool> concedido(String id) async {
    try {
      return await _permiso(id).isGranted;
    } catch (_) {
      return false; // plataforma sin permisos (web, escritorio)
    }
  }

  @override
  Future<ResultadoPermiso> solicitar(String id) async {
    try {
      final estado = await _permiso(id).request();
      if (estado.isGranted || estado.isLimited) return ResultadoPermiso.concedido;
      if (estado.isPermanentlyDenied || estado.isRestricted) return ResultadoPermiso.bloqueado;
      return ResultadoPermiso.denegado;
    } catch (_) {
      return ResultadoPermiso.denegado;
    }
  }

  @override
  Future<void> abrirAjustes() => openAppSettings();
}

/// Pide el permiso con el diálogo de Android. Si el usuario lo bloqueó
/// («No volver a preguntar»), ofrece abrir los ajustes de la app.
Future<void> pedirPermiso(BuildContext context, String id) async {
  final messenger = ScaffoldMessenger.of(context);
  final resultado = await AppState.instance.permitir(id);
  switch (resultado) {
    case ResultadoPermiso.concedido:
      break;
    case ResultadoPermiso.denegado:
      messenger.showSnackBar(const SnackBar(content: Text('No diste el permiso. Puedes intentarlo otra vez.')));
    case ResultadoPermiso.bloqueado:
      messenger.showSnackBar(SnackBar(
        content: const Text('El permiso está bloqueado. Actívalo en los ajustes de tu celular.'),
        action: SnackBarAction(label: 'Abrir ajustes', onPressed: Permisos.instancia.abrirAjustes),
      ));
  }
}
