# Wawa Qhali · App (Flutter)

Frontend base según el mockup de alta fidelidad. Backend, CNN y RAG **todavía no existen**: están simulados.

## Correr

```bash
flutter pub get
flutter run            # celular/emulador Android
flutter run -d chrome  # navegador (sin cámara: usa una foto de muestra)
flutter test           # recorre el flujo completo y la rama de emergencia
```

## Estructura

```
assets/db.json                 Todo el contenido: preguntas, guías, centros, resultados, textos legales.
lib/data/db.dart               Lee db.json.
lib/state/app_state.dart       Estado en memoria (permisos, donación, episodio actual y último).
lib/services/
  validation_service.dart      SIMULADO · validación de la foto (US16)
  classifier_service.dart      SIMULADO · CNN con TensorFlow Lite (US06)
  recommendation_service.dart  SIMULADO · riesgo + recomendación del RAG (US07, US08)
  links.dart                   Llamar al 106, abrir webs y mapas.
lib/screens/                   Una pantalla por artboard del mockup (01 a 14).
lib/widgets/                   Botones, tarjetas, encabezado de pasos e ilustraciones.
```

## Probar otros resultados

Edita `demo` en `assets/db.json` y reinicia la app:

- `validacion`: `aprobada` · `falla_nitidez` · `varias_fallas`
- `resultado`: `compatible` · `no_compatible`
- `confianza`: menor a `0.6` → resultado indeterminado

El riesgo sale de la extensión: «Una zona» → bajo; «Varias zonas» o «Todo el cuerpo» → moderado.

## Pendiente (fuera de esta base)

- Modelo `.tflite` real en `classifier_service.dart` (`tflite_flutter`).
- RAG / contenido remoto (Firebase) en `recommendation_service.dart`.
- Permisos reales del sistema (`permission_handler`); hoy son interruptores en memoria.
- Persistencia local de la última foto y de los ajustes (hoy se pierde al cerrar la app).
- Mapa real y centros reales de La Molina (hoy son placeholders en `db.json`).
- Compartir con el menú nativo (`share_plus`); hoy copia el resumen al portapapeles.
