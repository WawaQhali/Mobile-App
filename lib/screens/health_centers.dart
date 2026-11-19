import 'dart:math';

import 'package:flutter/material.dart';

import '../services/links.dart';
import '../services/location_service.dart';
import '../services/permissions_service.dart';
import '../state/app_state.dart';
import '../state/centros_state.dart';
import '../theme/app_theme.dart';
import '../widgets/illustrations.dart';
import '../widgets/shared.dart';

const _tipos = {'emergencia': 'Hospital · emergencia', 'centro': 'Centro de salud o clínica'};

/// 12 · Centros de salud cercanos a tu ubicación real (GPS + OpenStreetMap).
class CentrosScreen extends StatefulWidget {
  const CentrosScreen({super.key, this.conVolver = false});

  final bool conVolver;

  @override
  State<CentrosScreen> createState() => _CentrosScreenState();
}

class _CentrosScreenState extends State<CentrosScreen> {
  String _filtro = 'todos';
  final _buscador = BuscadorCentros.instancia;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_alCambiarPermisos);
    _buscador.buscar();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_alCambiarPermisos);
    super.dispose();
  }

  void _alCambiarPermisos() {
    final permitido = AppState.instance.permisos['ubicacion'] ?? false;
    if (permitido && _buscador.problema == ProblemaUbicacion.sinPermiso) _buscador.buscar(forzar: true);
  }

  @override
  Widget build(BuildContext context) {
    final filtros = {'todos': 'Todos', ..._tipos};

    return ListenableBuilder(
      listenable: _buscador,
      builder: (context, _) {
        final b = _buscador;
        final centros = b.centros.where((c) => _filtro == 'todos' || c.tipo == _filtro).take(25).toList();

        return RefreshIndicator(
          onRefresh: () => b.buscar(forzar: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
            children: [
              Row(
                children: [
                  if (widget.conVolver) ...[const BotonVolver(), const SizedBox(width: 14)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Centros de salud', style: AppText.titulo(28)),
                        Text('Cerca de ti · hasta ${CentrosService.radioMetros ~/ 1000} km',
                            style: AppText.cuerpo(13, color: AppColors.textoSuave)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 170,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borde),
                ),
                child: CustomPaint(painter: _mapa(b)),
              ),
              const SizedBox(height: 12),
              if (b.estado == EstadoBusqueda.cargando)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text('Buscando centros de salud cerca de ti… puede tardar unos segundos.',
                          textAlign: TextAlign.center, style: AppText.cuerpo(12.5, color: AppColors.textoSuave)),
                    ],
                  ),
                )
              else if (b.estado == EstadoBusqueda.error)
                _AvisoError(problema: b.problema)
              else ...[
                if (b.guardadosEl != null) ...[
                  Text(
                    'Sin conexión: mostramos tu última búsqueda (${formatoFecha(b.guardadosEl!)}).',
                    style: AppText.cuerpo(12, weight: FontWeight.w600, color: AppColors.ambarTexto),
                  ),
                  const SizedBox(height: 10),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final MapEntry(key: id, value: label) in filtros.entries)
                      _Filtro(label: label, activo: _filtro == id, onTap: () => setState(() => _filtro = id)),
                  ],
                ),
                const SizedBox(height: 16),
                for (final c in centros) ...[_TarjetaCentro(c), const SizedBox(height: 12)],
                if (centros.isEmpty)
                  Text('No encontramos centros de este tipo cerca de ti.',
                      style: AppText.cuerpo(13, color: AppColors.textoSuave)),
                const SizedBox(height: 4),
                Text('Datos de © OpenStreetMap. Las distancias son en línea recta.',
                    style: AppText.cuerpo(11, color: AppColors.textoSuave)),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Dibuja tu posición y los centros más cercanos, ubicados según sus coordenadas reales.
  MapaPainter _mapa(BuscadorCentros b) {
    final origen = b.origen;
    if (origen == null) return const MapaPainter(pines: []);
    final cerca = b.centros.take(8).toList();
    final lats = [origen.lat, for (final c in cerca) c.lat];
    final lngs = [origen.lng, for (final c in cerca) c.lng];
    final minLat = lats.reduce(min), maxLat = lats.reduce(max);
    final minLng = lngs.reduce(min), maxLng = lngs.reduce(max);
    final rango = max(max(maxLat - minLat, maxLng - minLng), 0.002);
    Offset punto(double lat, double lng) => Offset(
          0.1 + 0.8 * (lng - minLng) / rango,
          0.9 - 0.8 * (lat - minLat) / rango,
        );
    return MapaPainter(
      pines: [for (final c in cerca) punto(c.lat, c.lng)],
      usuario: punto(origen.lat, origen.lng),
    );
  }
}

class _AvisoError extends StatelessWidget {
  const _AvisoError({required this.problema});

  final ProblemaUbicacion? problema;

  @override
  Widget build(BuildContext context) {
    final (texto, boton, accion) = switch (problema) {
      ProblemaUbicacion.sinPermiso => (
          'Activa la ubicación para ver los centros de salud más cercanos a ti.',
          'Permitir',
          () => pedirPermiso(context, 'ubicacion'),
        ),
      ProblemaUbicacion.gpsApagado => (
          'El GPS de tu celular está apagado. Actívalo para buscar centros cercanos.',
          'Activar GPS',
          () async {
            await Ubicacion.instancia.abrirAjustesGps();
            BuscadorCentros.instancia.buscar(forzar: true);
          },
        ),
      ProblemaUbicacion.sinSenal => (
          'No pudimos saber dónde estás. Sal a un lugar abierto e inténtalo otra vez.',
          'Reintentar',
          () => BuscadorCentros.instancia.buscar(forzar: true),
        ),
      null => (
          'No pudimos buscar centros: revisa tu conexión a internet.',
          'Reintentar',
          () => BuscadorCentros.instancia.buscar(forzar: true),
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tarjeta(
          color: AppColors.arena,
          borde: null,
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            children: [
              const Icon(Icons.location_off_outlined, size: 20, color: AppColors.carameloOscuro),
              const SizedBox(width: 10),
              Expanded(child: Text(texto, style: AppText.cuerpo(12.5))),
              TextButton(onPressed: accion, child: Text(boton)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        BotonSecundario(
          label: 'Buscar hospitales en Google Maps',
          icono: Icons.map_outlined,
          onPressed: () => abrirUrl(context, 'https://www.google.com/maps/search/hospital'),
        ),
      ],
    );
  }
}

class _Filtro extends StatelessWidget {
  const _Filtro({required this.label, required this.activo, required this.onTap});

  final String label;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: activo ? AppColors.tinta : AppColors.superficie,
          foregroundColor: activo ? AppColors.sobreAccion : AppColors.tinta,
          side: BorderSide(color: activo ? AppColors.tinta : AppColors.borde, width: 1.5),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: AppText.cuerpo(12.5, weight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

class _TarjetaCentro extends StatelessWidget {
  const _TarjetaCentro(this.centro);

  final CentroSalud centro;

  @override
  Widget build(BuildContext context) {
    final telefono = centro.telefono;

    return Tarjeta(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(centro.nombre, style: AppText.cuerpo(14.5, weight: FontWeight.w700))),
              const SizedBox(width: 8),
              Text(centro.distanciaTexto, style: AppText.cuerpo(12, color: AppColors.textoSuave)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                child: Pastilla(
                  texto: _tipos[centro.tipo] ?? '',
                  fondo: centro.emergencia ? AppColors.terracotaFondo : AppColors.arena,
                  color: centro.emergencia ? AppColors.terracota : AppColors.carameloOscuro,
                ),
              ),
              const SizedBox(width: 8),
              const Spacer(),
              IconButton.outlined(
                tooltip: telefono == null ? 'Teléfono no disponible' : 'Llamar',
                onPressed: telefono == null ? null : () => llamar(context, telefono),
                icon: const Icon(Icons.call_outlined, size: 19),
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.tinta,
                  side: const BorderSide(color: AppColors.borde, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  fixedSize: const Size(44, 44),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: () => comoLlegar(context, centro.lat, centro.lng),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.tinta,
                    side: const BorderSide(color: AppColors.tinta, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: AppText.cuerpo(12.5, weight: FontWeight.w600),
                  ),
                  child: const Text('Cómo llegar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
