import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta de la guía visual del mockup.
abstract final class AppColors {
  static const crema = Color(0xFFF6EFE4); // fondo
  static const arena = Color(0xFFEDE1CF); // tarjetas
  static const tostado = Color(0xFFDCC6A8); // detalles
  static const caramelo = Color(0xFF8C5A3A); // acción
  static const carameloOscuro = Color(0xFF6B4429);
  static const carameloFondo = Color(0xFFF1E0D2);
  static const tinta = Color(0xFF2A221C); // texto
  static const textoSuave = Color(0xFF6B5D50);
  static const superficie = Color(0xFFFFFCF7);
  static const borde = Color(0xFFE4D5BF);
  static const divisor = Color(0xFFEFE4D4);
  static const sobreAccion = Color(0xFFFFF8EE);
  static const barraVacia = Color(0xFFD8C6AC);

  static const oliva = Color(0xFF6F6B45); // riesgo bajo
  static const olivaFondo = Color(0xFFE9E7D6);
  static const olivaTexto = Color(0xFF545133);

  static const verde = Color(0xFF2E6B3F); // correcto
  static const verdeFondo = Color(0xFFDDEEDF);

  static const ambar = Color(0xFFB9842F); // moderado
  static const ambarFondo = Color(0xFFF3E4C8);
  static const ambarTexto = Color(0xFF7A4E12);

  static const terracota = Color(0xFFA33A2A); // alarma
  static const terracotaFondo = Color(0xFFF6E1D9);
  static const terracotaTexto = Color(0xFF8A2E20);
  static const terracotaBorde = Color(0xFFEBC5B8);

  static const deshabilitado = Color(0xFFE4D5BF);
  static const deshabilitadoTexto = Color(0xFF5E5145);
}

/// Playfair Display para títulos, Montserrat para texto y botones.
abstract final class AppText {
  static TextStyle titulo(double size, {Color color = AppColors.tinta, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.playfairDisplay(fontSize: size, fontWeight: weight, color: color, height: 1.2);

  static TextStyle cuerpo(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.tinta,
    double height = 1.45,
  }) =>
      GoogleFonts.montserrat(fontSize: size, fontWeight: weight, color: color, height: height);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.caramelo,
      primary: AppColors.caramelo,
      surface: AppColors.crema,
    ),
    scaffoldBackgroundColor: AppColors.crema,
  );
  return base.copyWith(
    textTheme: GoogleFonts.montserratTextTheme(base.textTheme)
        .apply(bodyColor: AppColors.tinta, displayColor: AppColors.tinta),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.caramelo : null,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.verde : AppColors.barraVacia,
      ),
      thumbColor: const WidgetStatePropertyAll(AppColors.superficie),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.tinta,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.caramelo),
  );
}
