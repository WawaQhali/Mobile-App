import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

typedef Coordenadas = ({double lat, double lng});

enum ProblemaUbicacion { sinPermiso, gpsApagado, sinSenal }

class ErrorUbicacion implements Exception {
  const ErrorUbicacion(this.problema);

  final ProblemaUbicacion problema;
}

/// Ubicación del celular (GPS). El permiso se pide aparte (Permisos).
abstract class Ubicacion {
  static Ubicacion instancia = UbicacionGps();

  Future<Coordenadas> actual();
  Future<void> abrirAjustesGps();
}

class UbicacionGps implements Ubicacion {
  @override
  Future<Coordenadas> actual() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw const ErrorUbicacion(ProblemaUbicacion.gpsApagado);
    final permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
      throw const ErrorUbicacion(ProblemaUbicacion.sinPermiso);
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
      return (lat: p.latitude, lng: p.longitude);
    } on TimeoutException {
      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima == null) throw const ErrorUbicacion(ProblemaUbicacion.sinSenal);
      return (lat: ultima.latitude, lng: ultima.longitude);
    }
  }

  @override
  Future<void> abrirAjustesGps() => Geolocator.openLocationSettings();
}

/// Un establecimiento de salud cercano, de OpenStreetMap.
class CentroSalud {
  const CentroSalud({
    required this.nombre,
    required this.tipo,
    required this.lat,
    required this.lng,
    required this.distanciaKm,
    this.telefono,
  });

  final String nombre;
  final String tipo; // emergencia (hospital) | centro (clínica, centro de salud, consultorio)
  final double lat;
  final double lng;
  final double distanciaKm;
  final String? telefono;

  bool get emergencia => tipo == 'emergencia';

  String get distanciaTexto => distanciaKm < 1
      ? '${(distanciaKm * 1000).round()} m'
      : '${distanciaKm.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Distancia en línea recta (fórmula del haversine), en km.
double distanciaKm(Coordenadas a, Coordenadas b) {
  const radioTierra = 6371.0;
  double rad(double g) => g * pi / 180;
  final dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  final h = pow(sin(dLat / 2), 2) + cos(rad(a.lat)) * cos(rad(b.lat)) * pow(sin(dLng / 2), 2);
  return 2 * radioTierra * asin(sqrt(h));
}

/// Busca establecimientos de salud cerca con la API Overpass de OpenStreetMap.
/// Privacidad: la ubicación se redondea a 3 decimales (~100 m) antes de enviarla,
/// y no va acompañada de ningún dato de la familia.
///
/// Los servidores públicos de Overpass a veces están saturados: se consulta a
/// varios a la vez y se usa la primera respuesta válida.
class CentrosService {
  CentrosService({http.Client? cliente, List<String>? servidores})
      : _cliente = cliente ?? http.Client(),
        servidores = servidores ?? servidoresOverpass;

  static CentrosService instancia = CentrosService();

  static const servidoresOverpass = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  final http.Client _cliente;
  final List<String> servidores;
  static const radioMetros = 6000;
  static const tiempoMaximo = Duration(seconds: 15);

  ({Coordenadas origen, DateTime cuando, List<CentroSalud> centros})? _cache;

  static double _redondear(double v) => (v * 1000).round() / 1000;

  static String consulta(double lat, double lng) {
    final cerca = 'around:$radioMetros,$lat,$lng';
    return '[out:json][timeout:30];('
        'nwr[amenity=hospital]($cerca);'
        'nwr[amenity=clinic]($cerca);'
        'nwr[amenity=doctors]($cerca);'
        'nwr[healthcare=centre]($cerca);'
        ');out center tags 100;';
  }

  Future<List<CentroSalud>> cercanos(Coordenadas origen) async {
    final c = _cache;
    if (c != null && DateTime.now().difference(c.cuando).inMinutes < 10 && distanciaKm(c.origen, origen) < 0.3) {
      return c.centros;
    }
    final lat = _redondear(origen.lat), lng = _redondear(origen.lng);
    List<CentroSalud> centros;
    try {
      centros = interpretar(await _primeraRespuesta(consulta(lat, lng)), origen);
    } catch (_) {
      // Overpass saturado: hospitales y clínicas con el buscador de OpenStreetMap.
      centros = await _nominatim(lat, lng, origen);
    }
    _cache = (origen: origen, cuando: DateTime.now(), centros: centros);
    return centros;
  }

  /// Consulta a todos los servidores a la vez; gana la primera respuesta válida.
  Future<Map<String, dynamic>> _primeraRespuesta(String consulta) {
    final resultado = Completer<Map<String, dynamic>>();
    var fallidos = 0;
    for (final url in servidores) {
      _cliente
          .post(
            Uri.parse(url),
            headers: {'User-Agent': 'WawaQhali/0.1 (aplicacion academica)'},
            body: {'data': consulta},
          )
          .timeout(tiempoMaximo)
          .then((r) {
        if (r.statusCode != 200) throw Exception('$url respondió ${r.statusCode}');
        final datos = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        if (datos['elements'] is! List) throw Exception('$url: respuesta sin elementos');
        if (!resultado.isCompleted) resultado.complete(datos);
      }).catchError((Object error) {
        fallidos++;
        if (fallidos == servidores.length && !resultado.isCompleted) {
          resultado.completeError(Exception('Ningún servidor de mapas respondió'));
        }
      });
    }
    return resultado.future;
  }

  static const urlNominatim = 'https://nominatim.openstreetmap.org/search';

  /// Respaldo: Nominatim, dentro de un cuadro de ~6 km alrededor. Dos consultas
  /// seguidas, separadas 1 s (política de uso de Nominatim).
  Future<List<CentroSalud>> _nominatim(double lat, double lng, Coordenadas origen) async {
    final dLat = radioMetros / 111000, dLng = radioMetros / (111000 * cos(lat * pi / 180));
    final caja = '${lng - dLng},${lat + dLat},${lng + dLng},${lat - dLat}';
    final elementos = <Map<String, dynamic>>[];
    for (final (i, texto) in ['hospital', 'clinica'].indexed) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 1100));
      final uri = Uri.parse(urlNominatim).replace(queryParameters: {
        'q': texto,
        'format': 'jsonv2',
        'viewbox': caja,
        'bounded': '1',
        'limit': '40',
        'extratags': '1',
      });
      final r = await _cliente
          .get(uri, headers: {'User-Agent': 'WawaQhali/0.1 (aplicacion academica)'})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) continue;
      for (final x in (jsonDecode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>()) {
        if (x['category'] != 'amenity' && x['class'] != 'amenity') continue;
        final extras = (x['extratags'] as Map?)?.cast<String, dynamic>() ?? const {};
        elementos.add({
          'lat': double.tryParse('${x['lat']}'),
          'lon': double.tryParse('${x['lon']}'),
          'tags': {'amenity': x['type'], 'name': x['name'], ...extras},
        });
      }
    }
    if (elementos.isEmpty) throw Exception('No hay centros de salud en el mapa cerca de aquí');
    return interpretar({'elements': elementos}, origen);
  }

  /// Convierte la respuesta de Overpass en centros, sin repetidos y del más cercano al más lejano.
  static List<CentroSalud> interpretar(Map<String, dynamic> datos, Coordenadas origen) {
    final vistos = <String>{};
    final centros = <CentroSalud>[];
    for (final e in (datos['elements'] as List).cast<Map<String, dynamic>>()) {
      final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
      final nombre = (tags['name'] as String?)?.trim();
      final punto = (e['center'] as Map?) ?? e;
      final lat = (punto['lat'] as num?)?.toDouble(), lng = (punto['lon'] as num?)?.toDouble();
      if (nombre == null || nombre.isEmpty || lat == null || lng == null) continue;
      if (!vistos.add(nombre.toLowerCase())) continue;
      final hospital = tags['amenity'] == 'hospital' || tags['healthcare'] == 'hospital';
      centros.add(CentroSalud(
        nombre: nombre,
        tipo: hospital && tags['emergency'] != 'no' ? 'emergencia' : 'centro',
        lat: lat,
        lng: lng,
        distanciaKm: distanciaKm(origen, (lat: lat, lng: lng)),
        telefono: (tags['phone'] ?? tags['contact:phone']) as String?,
      ));
    }
    centros.sort((a, b) => a.distanciaKm.compareTo(b.distanciaKm));
    return centros;
  }
}
