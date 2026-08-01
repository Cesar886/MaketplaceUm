import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // ─── Paleta principal ────────────────────────────────────
  static const primary = Color(0xFF1F6357);       // Verde Mercado
  static const primaryDark = Color(0xFF122E28);   // Verde noche (sombras, overlays)
  static const amber = Color(0xFFE8A614);          // Ámbar Maíz — signature accent
  static const amberDark = Color(0xFFB37E0A);      // Ámbar oscuro para texto sobre amber
  static const gold = Color(0xFFC79A3B);           // Dorado — featured/premium
  static const champagne = Color(0xFFFBF6EA);      // Fondo premium badge
  static const orange = Color(0xFFC7653E);         // Naranja — reservado/negociando
  static const teal = Color(0xFF2B7C73);           // Teal secundario

  // ─── Base ────────────────────────────────────────────────
  static const background = Color(0xFFF5F2EB);    // Hueso Cálido
  static const surface = Color(0xFFFFFFFF);        // Blanco limpio
  static const surfaceMuted = Color(0xFFF0EDE6);  // Surface muted (tono cálido)
  static const ink = Color(0xFF1A2B27);            // Tinta Profunda
  static const muted = Color(0xFF6B716E);          // Texto secundario
  static const border = Color(0xFFE3E0D8);         // Border (tono cálido)
  static const premiumBorder = Color(0xFFE4D4A7);

  // ─── Estados ─────────────────────────────────────────────
  static const danger = Color(0xFFC8433A);
  static const success = Color(0xFF2D7D55);

  // ─── Oscuro ──────────────────────────────────────────────
  static const darkBackground = Color(0xFF121212);
  static const darkSurface = Color(0xFF1E1E1E);
  static const darkSurfaceMuted = Color(0xFF2A2A2A);
  static const darkInk = Color(0xFFE8EAE6);
  static const darkMuted = Color(0xFF9A9F9C);
  static const darkBorder = Color(0xFF333533);
}

class AppTypography {
  // Sora: para precios y números — carácter, sin frialdad corporativa
  static TextStyle price(double size, {FontWeight weight = FontWeight.w800, Color? color}) =>
      GoogleFonts.sora(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        height: 1.1,
      );

  // Sora medium: para headings de sección
  static TextStyle heading(double size, {FontWeight weight = FontWeight.w700, Color? color}) =>
      GoogleFonts.sora(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        height: 1.2,
      );

  // Nunito: cuerpo, descripción, labels
  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.nunito(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        height: 1.4,
      );

  static TextStyle label(double size, {FontWeight weight = FontWeight.w600, Color? color}) =>
      GoogleFonts.nunito(
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
    final base = GoogleFonts.nunitoTextTheme();
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
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
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
          textStyle: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary.withValues(alpha: 0.10),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: AppColors.ink),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      dividerColor: AppColors.border,
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData get dark {
    final base = GoogleFonts.nunitoTextTheme(ThemeData.dark().textTheme);
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
          textStyle: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.darkBorder),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedColor: AppColors.primary.withValues(alpha: 0.20),
        side: const BorderSide(color: AppColors.darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: AppColors.darkInk),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: GoogleFonts.nunito(color: AppColors.darkInk, fontWeight: FontWeight.w600),
      ),
      dividerColor: AppColors.darkBorder,
      visualDensity: VisualDensity.standard,
    );
  }
}
