import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'widgets/edge_swipe_back.dart';

/// Sistema "Navy + Oro": el navy es el ancla fría de confianza (header,
/// nav, marca) y el oro es el ÚNICO color cálido del sistema, reservado
/// para lo que debe atraer el ojo y termina en una compra: precio, botón de
/// publicar y badge de descuento.
///
/// La regla que sostiene todo: si algo es oro, es porque queremos que lo
/// mires. Si el oro se reparte entre decoración e información, deja de
/// funcionar como señal y la pantalla vuelve a sentirse plantilla.
class AppColors {
  // ─── Primario — Navy ─────────────────────────────────────
  static const primary = Color(0xFF1B2A4A); // Navy base — marca, nav activo
  static const primaryDark = Color(
    0xFF14213A,
  ); // Navy oscuro — hover/pressed, headers, overlays
  static const primaryLight = Color(
    0xFF2E3F5C,
  ); // Navy claro — bordes sutiles, íconos inactivos
  // Íconos/labels inactivos DENTRO de la barra navy: primaryLight es un
  // color de superficie, sobre navy no alcanza a leerse como texto.
  static const onPrimaryMuted = Color(0xFF93A2BC);

  // ─── Acento — Oro ────────────────────────────────────────
  // Único acento cálido: precio, FAB de publicar, badges de oferta.
  static const gold = Color(0xFFD4A02C); // Oro base — el acento vivo
  static const goldDark = Color(0xFFB07D12); // Hover/pressed, bordes
  static const goldSoft = Color(
    0xFFF7E7C0,
  ); // Oro muy claro — bordes de badge, chip activo
  static const goldTint = Color(
    0xFFFDF4E2,
  ); // Fondo de badge/banner oro (pendiente, premium)
  // Latón para TEXTO PEQUEÑO sobre superficies claras: el oro base sobre
  // blanco da 2.4:1 y es ilegible. Sigue siendo oro y no café — 40° de tono
  // y 79% de saturación, contra los 24°/42% de un cobre.
  static const goldText = Color(0xFF8A6210);
  // Lo que va ENCIMA de un relleno de oro es NAVY, no blanco: navy sobre oro
  // da 6.0:1 y blanco apenas 2.4:1. Eso es lo que deja al oro quedarse en su
  // versión brillante dentro de badges, botones y etiqueta de precio, en vez
  // de tener que oscurecerse hasta parecer café.
  static const onGold = primary;

  static const verifiedBlue = Color(
    0xFF3897F0,
  ); // Azul de verificación estilo Meta/Instagram

  // ─── Base ────────────────────────────────────────────────
  static const background = Color(0xFFFAFAF8); // Blanco cálido, no blanco puro
  static const surface = Color(0xFFFFFFFF); // Tarjetas
  static const surfaceMuted = Color(0xFFF2F1EE); // Surface muted (neutro)
  static const ink = Color(0xFF1A1A1D); // Texto principal (casi negro)
  // Texto secundario. Se usa a 11-12px en los metadatos de tarjeta (fecha,
  // vistas, descripción), así que tiene que aguantar AA a ese tamaño: el
  // #8A8A85 del que salió esta paleta daba 3.3:1 sobre el fondo.
  static const muted = Color(0xFF6F6F6A);
  // Gris de texto pequeño sobre fondos ya grises (badge "Agotado" sobre
  // neutralBg): ahí [muted] se queda en 4.3:1, apenas por debajo del mínimo.
  static const mutedStrong = Color(0xFF63635F);
  static const border = Color(0xFFE8E6E1); // Bordes/separadores sutiles

  // ─── Estados semánticos ──────────────────────────────────
  // Sin verdes/rojos puros: desentonan con navy+oro. Verde apagado casi
  // sage para disponible, y el mismo oro reutilizado para pendiente.
  static const success = Color(0xFF4A6B5C); // Disponible
  static const successBg = Color(0xFFE4EBE7);
  static const danger = Color(0xFFA6483C); // Ladrillo apagado, no rojo puro
  static const neutralBg = Color(0xFFEDEDEB); // No disponible / inactivo

  // Premium/destacado: mismo oro, diferenciado del badge de oferta por
  // tratamiento (fondo crema + borde) y no por tono.
  static const premiumBorder = goldSoft;

  // ─── Oscuro ──────────────────────────────────────────────
  // Jerarquía por elevación (fondo < surface < surfaceElevated) en vez de
  // un solo gris plano — así las tarjetas se separan del fondo sin
  // depender de sombras, que casi no se ven sobre fondo oscuro. Los grises
  // van teñidos de navy para que el modo oscuro siga leyéndose como la
  // misma marca.
  static const darkBackground = Color(0xFF0E1420); // navy casi negro
  static const darkSurface = Color(0xFF17202E); // tarjetas estándar
  static const darkSurfaceElevated = Color(
    0xFF1F2A3A,
  ); // modales, sheets, banners destacados
  static const darkSurfaceMuted = Color(0xFF1A2432); // fondos de sección/inputs
  static const darkInk = Color(0xFFECEEF2);
  static const darkMuted = Color(0xFF959FAF);
  static const darkBorder = Color(
    0xFF2C3849,
  ); // con suficiente presencia para separar tarjetas
  // Reemplaza a primary/primaryDark cuando se usa como color de
  // ícono/texto sobre una superficie neutra (no como fondo de AppBar/nav):
  // el navy es casi negro y se pierde sobre fondos ya oscuros.
  static const primaryAccentDark = Color(0xFF9FB6D6);
  // Sobre fondo oscuro el oro base ya contrasta bien (6.9:1), pero esta
  // variante aclarada le devuelve el brillo que pierde sin blanco alrededor.
  static const goldOnDark = Color(0xFFE3B84E);
  // Los estados semánticos también se aclaran en oscuro por la misma razón
  // que el oro: el tono claro conserva la identidad, el oscuro se pierde.
  static const successOnDark = Color(0xFF7FA593);
  static const darkSuccessBg = Color(0xFF1B2A24);
  static const dangerOnDark = Color(0xFFD98577);
  // Reemplaza a goldTint (fondo de badges/banners "premium") en oscuro.
  static const darkPremiumBg = Color(0xFF2B2312);
  static const darkPremiumBorder = Color(0xFF4E4222);
}

/// Set de colores neutros que sí cambian según el tema activo (a diferencia
/// de los colores de marca en [AppColors], que son fijos). Usar
/// `context.colors.xxx` en vez de `AppColors.background/surface/ink/muted/
/// border` para que cualquier superficie/texto neutro responda al modo
/// oscuro.
class AppColorSet {
  const AppColorSet({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.ink,
    required this.muted,
    required this.mutedStrong,
    required this.border,
    required this.accent,
    required this.gold,
    required this.premiumBg,
    required this.premiumBorder,
    required this.success,
    required this.successBg,
    required this.pendingBg,
    required this.neutralBg,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color ink;
  final Color muted;

  /// Gris legible para texto pequeño sobre superficies grises/tintadas,
  /// donde [muted] queda por debajo del contraste mínimo.
  final Color mutedStrong;
  final Color border;
  final Color accent;

  /// Oro legible como TEXTO/ÍCONO sobre una superficie del tema actual.
  /// Para oro como RELLENO sólido (FAB, badge, botón) usar [AppColors.gold]
  /// con [AppColors.onGold] encima: ahí el fondo es el oro mismo y no
  /// depende del tema.
  final Color gold;
  final Color premiumBg;
  final Color premiumBorder;

  /// Fondos de los tres estados semánticos (disponible / pendiente / no
  /// disponible). Son colores propios y no el foreground con alpha: un
  /// verde sage al 8% sobre fondo cálido se ensucia y deja de distinguirse
  /// del gris de "no disponible", que es justo la diferencia que el badge
  /// tiene que comunicar.
  final Color success;
  final Color successBg;
  final Color pendingBg;
  final Color neutralBg;

  /// Ladrillo apagado legible sobre la superficie del tema actual. Para
  /// rellenos sólidos de error usar [AppColors.danger].
  final Color danger;

  static const light = AppColorSet(
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceElevated: AppColors.surface,
    surfaceMuted: AppColors.surfaceMuted,
    ink: AppColors.ink,
    muted: AppColors.muted,
    mutedStrong: AppColors.mutedStrong,
    border: AppColors.border,
    accent: AppColors.primary,
    gold: AppColors.goldText,
    premiumBg: AppColors.goldTint,
    premiumBorder: AppColors.premiumBorder,
    success: AppColors.success,
    successBg: AppColors.successBg,
    pendingBg: AppColors.goldTint,
    neutralBg: AppColors.neutralBg,
    danger: AppColors.danger,
  );

  static const dark = AppColorSet(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceElevated: AppColors.darkSurfaceElevated,
    surfaceMuted: AppColors.darkSurfaceMuted,
    ink: AppColors.darkInk,
    muted: AppColors.darkMuted,
    // En oscuro el gris de texto ya tiene contraste de sobra sobre los
    // fondos de sección, así que no hace falta una segunda variante.
    mutedStrong: AppColors.darkMuted,
    border: AppColors.darkBorder,
    accent: AppColors.primaryAccentDark,
    gold: AppColors.goldOnDark,
    premiumBg: AppColors.darkPremiumBg,
    premiumBorder: AppColors.darkPremiumBorder,
    success: AppColors.successOnDark,
    successBg: AppColors.darkSuccessBg,
    pendingBg: AppColors.darkPremiumBg,
    neutralBg: AppColors.darkSurfaceMuted,
    danger: AppColors.dangerOnDark,
  );
}

extension AppColorsContext on BuildContext {
  AppColorSet get colors => Theme.of(this).brightness == Brightness.dark
      ? AppColorSet.dark
      : AppColorSet.light;
}

class AppTypography {
  // Baloo 2: para precios — redondeada, con carácter de etiqueta de puesto,
  // usada con moderación (solo precios y headlines grandes).
  static TextStyle price(
    double size, {
    FontWeight weight = FontWeight.w800,
    Color? color,
  }) => GoogleFonts.baloo2(
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.ink,
    height: 1.1,
  );

  // Baloo 2: headings de sección
  static TextStyle heading(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) => GoogleFonts.baloo2(
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.ink,
    height: 1.2,
  );

  // Work Sans: cuerpo, descripción, labels
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => GoogleFonts.workSans(
    fontSize: size,
    fontWeight: weight,
    color: color ?? AppColors.ink,
    height: 1.4,
  );

  static TextStyle label(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) => GoogleFonts.workSans(
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

  static List<BoxShadow> get gold => [
    BoxShadow(
      color: AppColors.goldDark.withValues(alpha: 0.34),
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
      onPrimary: Colors.white,
      secondary: AppColors.gold,
      onSecondary: AppColors.onGold,
      tertiary: AppColors.goldText,
      surface: AppColors.surface,
      surfaceContainerHighest: AppColors.surfaceMuted,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      // Transición + gesto de "deslizar desde el borde para regresar" de
      // estilo iOS en Android y iOS por igual. El área activa del gesto ya
      // viene limitada por Flutter a una franja angosta desde el borde
      // izquierdo (~20px o el ancho del notch, lo que sea mayor — ver
      // _kBackGestureWidth en flutter/cupertino/route.dart), así que no
      // compite con gestos horizontales de ancho completo como el carrusel
      // de imágenes o el mapa interactivo. Aplica solo a rutas que respetan
      // el theme (MaterialPageRoute/CupertinoPageRoute); un PageRouteBuilder
      // con transitionsBuilder propio lo ignora por completo.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SensitiveCupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: SensitiveCupertinoPageTransitionsBuilder(),
        },
      ),
      textTheme: base.copyWith(
        headlineLarge: base.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        headlineMedium: base.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        headlineSmall: base.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        titleLarge: base.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        titleMedium: base.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        bodyLarge: base.bodyLarge?.copyWith(color: AppColors.ink),
        bodyMedium: base.bodyMedium?.copyWith(color: AppColors.ink),
        labelSmall: base.labelSmall?.copyWith(color: AppColors.muted),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        // Fondo oscuro del AppBar → íconos claros en la barra de estado.
        // Explícito (no auto-detectado) para que sea consistente sin
        // importar el color exacto de fondo que se use.
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.baloo2(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
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
          // El botón lleno es la acción — y toda acción es oro con etiqueta
          // navy. El navy sólido se queda para el cromo (header, nav), así
          // nunca compiten.
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.onGold,
          disabledBackgroundColor: AppColors.gold.withValues(alpha: 0.38),
          disabledForegroundColor: AppColors.onGold.withValues(alpha: 0.55),
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.workSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primaryLight),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        // Chip activo en oro muy claro: marca la selección con el color de
        // acento sin gastar oro sólido, que está reservado a precio y CTA.
        selectedColor: AppColors.goldTint,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.workSans(
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: GoogleFonts.workSans(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: AppColors.border,
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData get dark {
    final base = GoogleFonts.workSansTextTheme(ThemeData.dark().textTheme);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ).copyWith(
          // En oscuro el navy base se confunde con el fondo, así que el rol
          // de "primary" lo toma la variante aclarada.
          primary: AppColors.primaryAccentDark,
          onPrimary: AppColors.primaryDark,
          secondary: AppColors.goldOnDark,
          onSecondary: AppColors.primaryDark,
          tertiary: AppColors.gold,
          surface: AppColors.darkSurface,
          surfaceContainerHighest: AppColors.darkSurfaceMuted,
          outline: AppColors.darkBorder,
          outlineVariant: AppColors.darkBorder,
          error: AppColors.danger,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkBackground,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SensitiveCupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: SensitiveCupertinoPageTransitionsBuilder(),
        },
      ),
      textTheme: base.copyWith(
        headlineLarge: base.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.darkInk,
        ),
        headlineMedium: base.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.darkInk,
        ),
        headlineSmall: base.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.darkInk,
        ),
        titleLarge: base.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.darkInk,
        ),
        titleMedium: base.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.darkInk,
        ),
        bodyLarge: base.bodyLarge?.copyWith(color: AppColors.darkInk),
        bodyMedium: base.bodyMedium?.copyWith(color: AppColors.darkInk),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.darkBackground,
        foregroundColor: AppColors.darkInk,
        // Fondo oscuro del AppBar → íconos claros en la barra de estado.
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
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
          borderSide: const BorderSide(
            color: AppColors.primaryAccentDark,
            width: 1.5,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // El botón lleno es la acción — y toda acción es oro con etiqueta
          // navy. El navy sólido se queda para el cromo (header, nav), así
          // nunca compiten.
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.onGold,
          disabledBackgroundColor: AppColors.gold.withValues(alpha: 0.38),
          disabledForegroundColor: AppColors.onGold.withValues(alpha: 0.55),
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.workSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryAccentDark,
          side: const BorderSide(color: AppColors.darkBorder),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedColor: AppColors.darkPremiumBg,
        side: const BorderSide(color: AppColors.darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.workSans(
          fontWeight: FontWeight.w700,
          color: AppColors.darkInk,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: GoogleFonts.workSans(
          color: AppColors.darkInk,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: AppColors.darkBorder,
      visualDensity: VisualDensity.standard,
    );
  }
}
