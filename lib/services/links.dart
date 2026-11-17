import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre una web en el navegador (términos, privacidad, mapas).
Future<void> abrirUrl(BuildContext context, String url) =>
    _lanzar(context, Uri.parse(url), 'No se pudo abrir el enlace.');

/// Abre el marcador del teléfono con el número listo.
Future<void> llamar(BuildContext context, String numero) =>
    _lanzar(context, Uri(scheme: 'tel', path: numero), 'No se pudo abrir el teléfono. Marca $numero.');

Future<void> comoLlegar(BuildContext context, double lat, double lng) =>
    abrirUrl(context, 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');

Future<void> _lanzar(BuildContext context, Uri uri, String error) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((Object _) => false);
  if (!ok) messenger.showSnackBar(SnackBar(content: Text(error)));
}
