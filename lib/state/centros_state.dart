import 'package:flutter/foundation.dart';

import '../services/location_service.dart';
import 'app_state.dart';

enum EstadoBusqueda { inicial, cargando, listo, error }

/// Búsqueda de centros de salud cercanos, compartida por Centros y Emergencia.
class BuscadorCentros extends ChangeNotifier {
  BuscadorCentros._();
  static final instancia = BuscadorCentros._();

  EstadoBusqueda estado = EstadoBusqueda.inicial;
  Coordenadas? origen;
  List<CentroSalud> centros = const [];

  /// Qué falló: sin permiso, GPS apagado, sin señal, o null si fue la red.
  ProblemaUbicacion? problema;

  /// Si los centros vienen de una búsqueda anterior guardada (sin internet), su fecha.
  DateTime? guardadosEl;

  static const _archivo = 'centros.json';

  CentroSalud? get emergenciaMasCercana {
    for (final c in centros) {
      if (c.emergencia) return c;
    }
    return null;
  }

  /// Busca si hay permiso y todavía no se buscó (o si se pide `forzar`).
  Future<void> buscar({bool forzar = false}) async {
    // Se puede llamar desde initState: los avisos van después del build actual.
    await Future<void>.delayed(Duration.zero);
    if (estado == EstadoBusqueda.cargando) return;
    if (!forzar && estado == EstadoBusqueda.listo) return;
    if (!(AppState.instance.permisos['ubicacion'] ?? false)) {
      estado = EstadoBusqueda.error;
      problema = ProblemaUbicacion.sinPermiso;
      notifyListeners();
      return;
    }
    estado = EstadoBusqueda.cargando;
    problema = null;
    notifyListeners();
    Coordenadas? aqui;
    try {
      aqui = await Ubicacion.instancia.actual();
      centros = await CentrosService.instancia.cercanos(aqui);
      origen = aqui;
      guardadosEl = null;
      estado = EstadoBusqueda.listo;
      await _guardar(aqui, centros);
    } on ErrorUbicacion catch (e) {
      problema = e.problema;
      estado = EstadoBusqueda.error;
    } catch (_) {
      // Sin internet o los servidores de mapas no respondieron: la última búsqueda guardada.
      problema = null;
      estado = await _usarGuardados(aqui) ? EstadoBusqueda.listo : EstadoBusqueda.error;
    }
    notifyListeners();
  }

  Future<void> _guardar(Coordenadas aqui, List<CentroSalud> lista) async {
    try {
      await AppState.instance.almacen.escribirJson(_archivo, {
        'lat': aqui.lat,
        'lng': aqui.lng,
        'fecha': DateTime.now().toIso8601String(),
        'centros': [
          for (final c in lista.take(40))
            {'nombre': c.nombre, 'tipo': c.tipo, 'lat': c.lat, 'lng': c.lng, 'telefono': c.telefono},
        ],
      });
    } catch (_) {}
  }

  /// Usa la búsqueda guardada si se hizo a menos de 3 km de aquí (o si no se sabe dónde estás).
  Future<bool> _usarGuardados(Coordenadas? aqui) async {
    try {
      final j = await AppState.instance.almacen.leerJson(_archivo);
      if (j == null) return false;
      final antes = (lat: (j['lat'] as num).toDouble(), lng: (j['lng'] as num).toDouble());
      if (aqui != null && distanciaKm(antes, aqui) > 3) return false;
      final desde = aqui ?? antes;
      centros = [
        for (final c in (j['centros'] as List).cast<Map<String, dynamic>>())
          CentroSalud(
            nombre: c['nombre'] as String,
            tipo: c['tipo'] as String,
            lat: (c['lat'] as num).toDouble(),
            lng: (c['lng'] as num).toDouble(),
            telefono: c['telefono'] as String?,
            distanciaKm: distanciaKm(desde, (lat: (c['lat'] as num).toDouble(), lng: (c['lng'] as num).toDouble())),
          ),
      ]..sort((a, b) => a.distanciaKm.compareTo(b.distanciaKm));
      origen = desde;
      guardadosEl = DateTime.parse(j['fecha'] as String);
      return centros.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void reiniciar() {
    estado = EstadoBusqueda.inicial;
    origen = null;
    centros = const [];
    problema = null;
    notifyListeners();
  }
}
