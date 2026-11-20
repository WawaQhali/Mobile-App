# Wawa Qhali · App (Flutter)

App Android de orientación ante ronchas en niños de 1 a 4 años. Habla con el backend (`../wawa_qhali_backend`) y hace en el celular todo lo que la guía pide hacer en el celular.

## Qué hace

| Paso | Cómo funciona |
| --- | --- |
| Permisos | Cámara, teléfono y ubicación con el aviso real de Android (`permission_handler`). Si se bloquean, la app ofrece abrir los ajustes |
| Foto | Vista previa **en vivo** de la cámara trasera, sin flash; el círculo marca dónde centrar el habón (`camera`). También se puede subir de la galería |
| Validación (sección 5.2) | **Medida sobre la foto real:** nitidez (varianza del Laplaciano), luz media, resolución, proporción de piel (YCbCr) y rostro con Google ML Kit. Muestra el valor medido de cada chequeo |
| Preprocesamiento (sección 5.3) | Orientación aplicada, **sin EXIF** (sin ubicación), recorte central cuadrado de 1024 px, JPEG 85. Solo ese recorte se guarda y se dona |
| Cuestionario | `assets/preguntas.json` v1: 8 de riesgo (un «Sí» va directo a emergencia) y 6 normales |
| Modelo | **TFLite en el celular**. Si la salida no es válida o no llega al umbral, da «indeterminado». Al abrir la app (como mucho cada 6 h) revisa `GET /v1/modelos/manifiesto`. Si hay una versión publicada nueva, la descarga, verifica el tamaño y el `sha256`, la prueba (sin NaN) y la usa. Si no hay o algo falla, sigue con el modelo anterior o con el de `assets/modelo/` |
| Severidad | La calcula la app con las reglas de `preguntas.json` y muestra **el porqué** |
| Recomendaciones | Backend con LLM + RAG (`POST /v1/orientacion`). Si responde 503, no hay internet o tarda más de 20 s, usa el respaldo local |
| Donación (sección 6) | Si el padre aceptó: la foto se **cifra** (AES-256-GCM + RSA-OAEP-256) y se envía a `POST /v1/donaciones`. Ver «Cómo se cifra la foto» |
| Centros de salud | Tu ubicación real (GPS) y establecimientos de **OpenStreetMap**, ordenados por distancia. También calcula la emergencia más cercana |
| Última evaluación | Se guarda en el celular y se reemplaza en cada evaluación nueva |

## Correr

```bash
flutter pub get
flutter run                                          # emulador Android → backend en http://10.0.2.2:8000
flutter run --dart-define=API_URL=http://localhost:8000   # celular por USB (antes: adb reverse tcp:8000 tcp:8000)
flutter run --dart-define=API_URL=https://<backend>       # backend en Azure
```

En debug y profile se permite HTTP sin TLS para el backend local; release solo usa HTTPS.

## Pruebas

```bash
flutter test     # flujo completo, validación real de fotos, cifrado, modelo, centros (backend simulado)

# Contra el backend real, desde la computadora:
flutter test test/integracion_backend_test.dart --dart-define=API_URL=http://localhost:8000

# En un celular o emulador (modelo TFLite, ML Kit, GPS, donación cifrada). Usa profile porque pesa menos:
flutter drive --profile --driver=test_driver/integration_test.dart \
  --target=integration_test/conexion_backend_test.dart -d <dispositivo>
```

`flutter drive` desinstala la app al terminar, y con eso se pierden los permisos. Para la prueba de GPS, la app necesita el permiso de ubicación (`adb shell pm grant com.wawaqhali.wawa_qhali android.permission.ACCESS_FINE_LOCATION`).

## Cómo se cifra la foto donada

Solo pasa si el padre aceptó donar, la foto es real, no se ve un rostro y el modelo dio un resultado (`lib/services/donation_service.dart`):

1. Arma un JSON en claro con el recorte JPEG de 1024 px en base64 y la etiqueta preliminar: clase, confianza, respuestas, versión del modelo y del cuestionario.
2. Genera una clave AES de 32 bytes y un nonce de 12 bytes, nuevos en cada donación.
3. Cifra con **AES-256-GCM**, usando el `installation_id` como dato adicional autenticado (AAD). Así el paquete no se puede reasignar a otra instalación.
4. Cifra la clave AES con la clave pública del servidor (`GET /v1/claves/publica`) usando **RSA-OAEP-256**, con SHA-256 en el hash y en MGF1, como espera Key Vault. Después borra la clave en claro.
5. Guarda el paquete `{v, kid, alg, clave_cifrada, nonce, datos}` en una **cola local** (como mucho 10) y lo envía a `POST /v1/donaciones`.
6. Sin conexión, con 429 o con un error del servidor, el paquete queda en la cola (estado «pendiente») y se reintenta al abrir o volver a la app. Un 403 o un 422 se descartan. Al revocar el permiso, la cola se vacía.

La cola guarda el paquete **ya cifrado**: en el celular no queda otra copia en claro de la foto. La clave pública se guarda al autorizar, para poder cifrar sin conexión, y se renueva cada vez que hay conexión.

El backend **no puede** descifrarlo: solo guarda el paquete en la cuarentena. Lo descifra el servicio de reentrenamiento con Key Vault (sección 6.4). Está verificado que lo que cifra la app lo descifra Python con el código de esa sección.

## Configuración (sin tocar código)

| Archivo | Qué se cambia |
| --- | --- |
| `assets/preguntas.json` | Cuestionario. Copia **exacta** del backend: si cambia, se actualizan los dos |
| `assets/modelo/modelo.tflite` + `modelo.json` | Modelo y su contrato: entrada, normalización, orden de clases, umbral |
| `assets/db.json → foto` | Umbrales de la validación (**provisionales**, calibrar con fotos reales) |
| `assets/db.json → recomendacionesLocales` | Respaldo cuando el backend no responde |

## Qué se guarda en el celular

En la carpeta privada de la app (nunca en la galería):

| Archivo | Contenido |
| --- | --- |
| `config.json` | `installation_id` (UUID aleatorio, la única identificación ante el backend) y preferencias |
| `ultima_evaluacion.json` | Solo la **última** evaluación: respuestas, clase y confianza, severidad, recomendaciones y fuentes |
| `ultima_foto.jpg` | El recorte de 1024 px sin EXIF, si «Guardar la última foto» está activo |
| `centros.json` | La última búsqueda de centros, para cuando no hay internet |

## Estructura

```
assets/preguntas.json            Cuestionario v1 (copia del backend)
assets/modelo/                   modelo.tflite + modelo.json (contrato)
assets/db.json                   Textos, umbrales, severidades, respaldo local, guías
lib/data/cuestionario.dart       Cuestionario, severidad y su porqué
lib/state/app_state.dart         Estado, persistencia, installation_id, permisos
lib/state/centros_state.dart     Búsqueda de centros compartida (Centros y Emergencia)
lib/services/
  api_client.dart                Backend (X-Installation-Id)
  image_processing.dart          Nitidez, luz, piel, recorte sin EXIF
  validation_service.dart        Validación de la foto + ML Kit
  classifier_service.dart        Modelo TFLite
  donation_service.dart          Cifrado, cola local y envío de la donación
  model_update_service.dart      Descarga del modelo publicado (manifiesto + sha256)
  location_service.dart          GPS + OpenStreetMap (Overpass, con Nominatim de respaldo)
  permissions_service.dart       Permisos reales de Android
  recommendation_service.dart    Severidad + recomendaciones del backend o locales
  local_storage.dart             Archivos privados de la app
lib/screens/                     Una pantalla por artboard del mockup
```

## Notas de Android

- `compileSdk = 37`, porque lo exige `permission_handler` (`targetSdk` y `minSdk` no cambian).
- `android/build.gradle.kts` alinea la versión de Kotlin de `tflite_flutter` (Java 11), que si no, no compila.

## Pendiente

- **Modelo nuevo de Diego**: el actual está dañado y siempre da «indeterminado». Ver `wawa-qhali-pendientes-urgentes.md`.
- Calibrar los umbrales de la foto con fotos reales.
- Decidir si un rostro en la foto la bloquea (guía) o solo avisa (app hoy).
