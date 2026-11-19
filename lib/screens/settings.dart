import 'package:flutter/material.dart';

import '../data/db.dart';
import '../services/links.dart';
import '../services/permissions_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

/// 14 · Ajustes: permisos, fotos, legal y versiones.
class AjustesScreen extends StatelessWidget {
  const AjustesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final app = Db.instance.app;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final hayFoto = state.ultimo?.foto != null;
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
          children: [
            Text('Ajustes', style: AppText.titulo(32)),
            const SizedBox(height: 20),
            _Seccion(
              titulo: 'PERMISOS',
              pie: 'Para quitarlos, ve a los ajustes de tu celular.',
              children: [
                for (final p in Db.instance.permisos)
                  _Fila(
                    icono: iconoPermiso(p['id'] as String),
                    titulo: p['nombre'] as String,
                    trailing: (state.permisos[p['id']] ?? false)
                        ? const Pastilla(
                            texto: 'Permitido',
                            icono: Icons.check_rounded,
                            fondo: AppColors.verdeFondo,
                            color: AppColors.verde,
                          )
                        : TextButton(
                            onPressed: () => pedirPermiso(context, p['id'] as String),
                            child: const Text('Permitir'),
                          ),
                  ),
              ],
            ),
            _Seccion(
              titulo: 'MIS FOTOS',
              children: [
                _Fila(
                  titulo: 'Donar mis fotos',
                  subtitulo: 'Cifradas y anónimas, para mejorar el modelo. Si se ve el rostro de tu wawa, esa foto no se dona.',
                  trailing: Switch(
                    value: state.donarFotos,
                    onChanged: (valor) async {
                      final messenger = ScaffoldMessenger.of(context);
                      final error = await state.setDonarFotos(valor);
                      if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
                    },
                  ),
                ),
                _Fila(
                  titulo: 'Guardar la última foto',
                  subtitulo: 'Solo en este celular, para el resumen',
                  trailing: Switch(value: state.guardarFoto, onChanged: state.setGuardarFoto),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: hayFoto ? state.borrarFoto : null,
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Borrar foto guardada'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.terracota,
                            side: BorderSide(color: hayFoto ? AppColors.terracotaBorde : AppColors.borde, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(hayFoto ? '1 foto guardada' : 'Sin fotos',
                          style: AppText.cuerpo(12, color: AppColors.textoSuave)),
                    ],
                  ),
                ),
              ],
            ),
            _Seccion(
              titulo: 'LEGAL',
              children: [
                _Fila(
                  titulo: 'Aviso legal',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => mostrarAvisoLegal(context),
                ),
                _Fila(
                  titulo: 'Términos y condiciones',
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => abrirUrl(context, app['terminosUrl'] as String),
                ),
                _Fila(
                  titulo: 'Política de privacidad',
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => abrirUrl(context, app['privacidadUrl'] as String),
                ),
              ],
            ),
            _Seccion(
              titulo: 'ACERCA DE',
              children: [
                _Fila(titulo: 'Contenido clínico', trailing: _Valor('Actualizado ${app['contenidoClinico']}')),
                _Fila(titulo: 'Versión de la app', trailing: _Valor(app['version'] as String)),
                _Fila(titulo: 'Versión del modelo', trailing: _Valor(app['modelo'] as String)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.children, this.pie});

  final String titulo;
  final List<Widget> children;
  final String? pie;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: AppText.cuerpo(11, weight: FontWeight.w700, color: AppColors.textoSuave)
                  .copyWith(letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Tarjeta(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: ListaConDivisores(children: children),
          ),
          if (pie != null) ...[
            const SizedBox(height: 8),
            Text(pie!, style: AppText.cuerpo(11.5, color: AppColors.textoSuave)),
          ],
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.titulo, required this.trailing, this.subtitulo, this.icono, this.onTap});

  final String titulo;
  final String? subtitulo;
  final IconData? icono;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              if (icono != null) ...[Icon(icono, size: 20, color: AppColors.caramelo), const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titulo, style: AppText.cuerpo(14, weight: FontWeight.w600)),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitulo!, style: AppText.cuerpo(12, color: AppColors.textoSuave, height: 1.4)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _Valor extends StatelessWidget {
  const _Valor(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(texto, style: AppText.cuerpo(12.5, color: AppColors.textoSuave));
}
