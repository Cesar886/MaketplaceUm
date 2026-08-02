import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema "Puesto de Barrio": azul piedra pastel como ancla premium, fondo
/// neutro casi blanco (sin tinte arenoso), cempasúchil como único acento
/// de firma. Ver docs de diseño para justificación de cada valor.
class AppColors {
  // ─── Paleta principal ────────────────────────────────────
  static const primary = Color(0xFF3D5C70);       // Azul Piedra — ancla de marca
  static const primaryDark = Color(0xFF1E313C);   // Azul Noche — headers, nav, overlays
  static const amber = Color(0xFFE3A008);          // Cempasúchil — signature accent
  static const amberDark = Color(0xFF3D2600);      // Texto sobre cempasúchil
  static const gold = Color(0xFFB8863B);           // Dorado — featured/premium
  static const champagne = Color(0xFFFAF3E0);      // Fondo premium badge
  static const orange = Color(0xFFA84B37);         // Terracota — reservado/negociando
  static const teal = Color(0xFF1F6B62);           // Teal secundario

  // ─── Base ────────────────────────────────────────────────
  static const background = Color(0xFFFAFAF8);    // Papel — neutro, casi blanco
  static const surface = Color(0xFFFFFFFF);        // Blanco limpio
  static const surfaceMuted = Color(0xFFF1F1EE);  // Surface muted (neutro)
  static const ink = Color(0xFF1B1A16);            // Tinta
  static const muted = Color(0xFF6E6B64);          // Texto secundario
  static const border = Color(0xFFE4E2DC);         // Border (neutro sutil)
  static const premiumBorder = Color(0xFFD9C68A);

  // ─── Estados ─────────────────────────────────────────────
  static const danger = Color(0xFFB23A2E);
  static const success = Color(0xFF2F7D5C);

  // ─── Oscuro ──────────────────────────────────────────────
  static const darkBackground = Color(0xFF10181D); // teñido de azul, no gris genérico
  static const darkSurface = Color(0xFF17242B);
  static const darkSurfaceMuted = Color(0xFF1E2E36);
  static const darkInk = Color(0xFFE9ECEE);
  static const darkMuted = Color(0xFF9CA8B0);
  static const darkBorder = Color(0xFF2B3F48);
}

class AppTypography {
  // Baloo 2: para precios — redondeada, con carácter de etiqueta de puesto,
  // usada con moderación (solo precios y headlines grandes).
  static TextStyle price(double size, {FontWeight weight = FontWeight.w800, Color? color}) =>
      GoogleFonts.baloo2(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        height: 1.1,
      );

  // Baloo 2: headings de sección
  static TextStyle heading(double size, {FontWeight weight = FontWeight.w700, Color? color}) =>
      GoogleFonts.baloo2(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        height: 1.2,
      );

  // Work Sans: cuerpo, descripción, labels
  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.workSans(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        height: 1.4,
      );

  static TextStyle label(double size, {FontWeight weight = FontWeight.w600, Color? color}) =>
      GoogleFonts.workSans(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        height: 1.3,
      );
}

class AppAnimations {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration staggerDelay = Duration(milliseconds: 60);

  // Spring suave para transiciones de pantalla
  static const Curve spring = Curves.easeOutCubic;
  // Para entrada de elementos (overshoot ligero)
  static const Curve entrance = Curves.easeOutBack;
  static const Curve easeOut = Curves.easeOut;
}

class AppShadows {
  static List<BoxShadow> get soft => [
    BoxShadow(
      color: AppColors.primaryDark.withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get lifted => [
    BoxShadow(
      color: AppColors.primaryDark.withValues(alpha: 0.10),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get amber => [
    BoxShadow(
      color: AppColors.amber.withValues(alpha: 0.28),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

class AppTheme {
  static ThemeData get light {
    final base = GoogleFonts.workSansTextTheme();
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.teal,
      tertiary: AppColors.gold,
      surface: AppColors.surface,
      surfaceContainerHighest: AppColors.surfaceMuted,
      outline: AppColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: base.copyWith(
        headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
        headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
        bodyLarge: base.bodyLarge?.copyWith(color: AppColors.ink),
        bodyMedium: base.bodyMedium?.copyWith(color: AppColors.ink),
        labelSmall: base.labelSmall?.copyWith(color: AppColors.muted),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.baloo2(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: AppColors.background,
        ),
        iconTheme: const IconThemeData(color: AppColors.background),
        actionsIconTheme: const IconThemeData(color: AppColors.background),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.workSans(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary.withValues(alpha: 0.10),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700, color: AppColors.ink),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: GoogleFonts.workSans(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      dividerColor: AppColors.border,
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData get dark {
    final base = GoogleFonts.workSansTextTheme(ThemeData.dark().textTheme);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.teal,
      tertiary: AppColors.gold,
      surface: AppColors.darkSurface,
      surfaceContainerHighest: AppColors.darkSurfaceMuted,
      outline: AppColors.darkBorder,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkBackground,
      textTheme: base.copyWith(
        headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.darkInk),
        headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.darkInk),
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.darkInk),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.darkInk),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.darkInk),
        bodyLarge: base.bodyLarge?.copyWith(color: AppColors.darkInk),
        bodyMedium: base.bodyMedium?.copyWith(color: AppColors.darkInk),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.darkBackground,
        foregroundColor: AppColors.darkInk,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.workSans(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.darkBorder),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedColor: AppColors.primary.withValues(alpha: 0.20),
        side: const BorderSide(color: AppColors.darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700, color: AppColors.darkInk),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: GoogleFonts.workSans(color: AppColors.darkInk, fontWeight: FontWeight.w600),
      ),
      dividerColor: AppColors.darkBorder,
      visualDensity: VisualDensity.standard,
    );
  }
}
