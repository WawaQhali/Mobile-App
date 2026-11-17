import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wawa_qhali/app.dart';
import 'package:wawa_qhali/data/db.dart';
import 'package:wawa_qhali/state/app_state.dart';

Future<void> tocar(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> esperar(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Onboarding completo hasta Inicio y el flujo hasta la pantalla de preguntas.
Future<void> hastaCuestionario(WidgetTester tester) async {
  await tester.pumpWidget(const WawaQhaliApp());
  await tester.pumpAndSettle();

  await tocar(tester, find.text('Comenzar'));
  await tocar(tester, find.byType(Checkbox));
  await tocar(tester, find.text('Continuar'));
  expect(find.text('¿Nos ayudas a mejorar Wawa Qhali?'), findsOneWidget);

  await tocar(tester, find.text('Ahora no'));
  await tocar(tester, find.text('Permitir').first);
  await tocar(tester, find.text('Continuar'));
  expect(find.text('Guías rápidas'), findsOneWidget);

  await tocar(tester, find.byTooltip('Evaluar lesión'));
  expect(find.text('Centra la lesión en el círculo'), findsOneWidget);

  // En el test no hay cámara: se usa la foto de muestra.
  await tocar(tester, find.bySemanticsLabel('Tomar foto'));
  await esperar(tester, 1000);
  expect(find.text('Tu foto se ve bien'), findsOneWidget);

  await tocar(tester, find.text('Usar esta foto'));
  tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
  await tester.pumpAndSettle();
  expect(find.text('Pregunta 1 de 10'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/image_picker'),
    (_) async => throw PlatformException(code: 'no_camera'),
  );

  setUp(() async {
    await Db.cargar();
    final s = AppState.instance;
    s.actual = null;
    s.ultimo = null;
    s.permisos.updateAll((_, _) => false);
  });

  testWidgets('flujo completo hasta el resumen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await hastaCuestionario(tester);

    // 5 preguntas de alarma con «No» y 5 de síntomas.
    for (var i = 0; i < 5; i++) {
      await tocar(tester, find.text('No'));
    }
    for (final r in ['Sí', 'Sí', 'Menos de 24 horas', 'Una zona', 'No']) {
      await tocar(tester, find.text(r));
    }

    await esperar(tester, 3000);
    expect(find.text('Análisis listo'), findsOneWidget);
    await tocar(tester, find.text('Ver resultado'));

    expect(find.text('Sí, compatible'), findsOneWidget);
    expect(find.text('Bajo'), findsOneWidget);

    await tocar(tester, find.text('Resumen para el médico'));
    expect(find.text('Síntomas'), findsOneWidget);
    expect(find.text('Extensión de las ronchas'), findsOneWidget);
    expect(find.text('Una zona'), findsOneWidget);
  });

  testWidgets('un «Sí» de alarma deriva a emergencia sin análisis y deja el resumen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await hastaCuestionario(tester);

    await tocar(tester, find.text('No')); // pregunta 1
    await tocar(tester, find.text('Sí')); // pregunta 2: hinchazón
    expect(find.text('Acude a emergencia ahora'), findsOneWidget);
    expect(find.textContaining('Marcaste un signo de alarma'), findsOneWidget);
    expect(AppState.instance.actual?.resultado, isNull);

    await tocar(tester, find.text('Resumen para el médico'));
    expect(find.text('No analizado: signo de alarma'), findsOneWidget);
    expect(find.text('Labios, lengua o párpados hinchados'), findsOneWidget);
    expect(find.text('Picazón'), findsNothing); // el cuestionario se cortó
  });
}
