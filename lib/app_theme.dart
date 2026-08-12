import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'widgets/edge_swipe_back.dart';

/// Constantes crudas del sistema. NO usarlas directamente en pantallas:
/// el color de marca ahora lo elige cada quien, así que todo lo que sea
/// marca se lee de `context.colors` (ver [AppColorSet]) y solo los neutros
/// y los estados semánticos viven aquí como valores fijos.
///
/// La regla que sostiene la personalización: **el color solo aparece como
/// relleno o como línea, nunca como texto de contenido.** El texto, los
/// precios y los datos van siempre en tinta neutra. Eso es lo que permite
/// ofrecer ocho colores sin revisar el contraste de cada pantalla ocho
/// veces — y es la razón por la que el oro dejó de existir como acento
/// paralelo: dos acentos compitiendo obligaban a decidir cuál gana en cada
/// superficie, y esa decisión no sobrevive a que el usuario cambie uno.
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

  // ─── Oscuro ──────────────────────────────────────────────
  // Jerarquía por elevación (fondo < surface < surfaceElevated) en vez de
  // un solo gris plano — así las tarjetas se separan del fondo sin
  // depender de sombras, que casi no se ven sobre fondo oscuro. Los grises
  // van teñidos de navy para que el modo oscuro siga leyéndose como la
  // misma marca. Más claros que la primera versión — casi negro leía como
  // apagado en vez de como "de noche".
  static const darkBackground = Color(0xFF1B2635);
  static const darkSurface = Color(0xFF233042); // tarjetas estándar
  static const darkSurfaceElevated = Color(
    0xFF2B394E,
  ); // modales, sheets, banners destacados
  static const darkSurfaceMuted = Color(0xFF202C3E); // fondos de sección/inputs
  static const darkBorder = Color(
    0xFF3A4A61,
  ); // con suficiente presencia para separar tarjetas

  // Texto en oscuro: BLANCO siempre, nunca un gris con tinte propio — la
  // jerarquía (principal/secundario) se hace con OPACIDAD del mismo blanco,
  // no con un segundo color. Da 7-15:1 de contraste incluso en el nivel más
  // tenue, muy por encima del mínimo AA.
  static const darkInk = Colors.white;
  static const darkMuted = Color(0xA8FFFFFF); // ~66% — texto secundario
  static const darkMutedStrong = Color(0xD9FFFFFF); // ~85% — secundario pequeño

  // Los estados semánticos también se aclaran en oscuro por la misma razón
  // que el oro: el tono claro conserva la identidad, el oscuro se pierde.
  static const successOnDark = Color(0xFF7FA593);
  static const darkSuccessBg = Color(0xFF1B2A24);
  static const dangerOnDark = Color(0xFFD98577);
}

/// Set de colores neutros que sí cambian según el tema activo (a diferencia
/// de los colores de marca en [AppColors], que son fijos). Usar
/// `context.colors.xxx` en vez de `AppColors.background/surface/ink/muted/
/// border` para que cualquier superficie/texto neutro responda al modo
/// oscuro.
class AppColorSet extends ThemeExtension<AppColorSet> {
  const AppColorSet({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.ink,
    required this.muted,
    required this.mutedStrong,
    required this.border,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.accentTint,
    required this.accentTintBorder,
    required this.success,
    required this.successBg,
    required this.neutralBg,
    required this.danger,
  });

  /// Construye la paleta completa a partir del swatch elegido y del tema.
  ///
  /// Todo lo de marca sale de aquí, así que cambiar de swatch repinta la app
  /// entera sin tocar un solo call site. Los neutros (fondos, grises, texto)
  /// NO se tiñen: el texto se queda en tinta negra pase lo que pase, que es
  /// justo lo que evita que elegir un color rosa deje la app ilegible.
  factory AppColorSet.of(AccentSwatch swatch, Brightness brightness) {
    final oscuro = brightness == Brightness.dark;
    final base = oscuro ? AppColors.darkSurface : AppColors.surface;
    return AppColorSet(
      background: oscuro ? AppColors.darkBackground : AppColors.background,
      surface: base,
      surfaceElevated: oscuro
          ? AppColors.darkSurfaceElevated
          : AppColors.surface,
      surfaceMuted: oscuro
          ? AppColors.darkSurfaceMuted
          : AppColors.surfaceMuted,
      ink: oscuro ? AppColors.darkInk : AppColors.ink,
      muted: oscuro ? AppColors.darkMuted : AppColors.muted,
      mutedStrong: oscuro ? AppColors.darkMutedStrong : AppColors.mutedStrong,
      border: oscuro ? AppColors.darkBorder : AppColors.border,
      primary: oscuro ? swatch.darkFill : swatch.fill,
      // Sobre el relleno oscuro lo legible es la tinta clara, no el navy que
      // se usa sobre el pastel.
      onPrimary: oscuro ? AppColors.darkInk : swatch.onFill,
      accent: swatch.line(brightness),
      // Lavado del color para fondos de chip/sección, derivado del relleno
      // de SU tema: en oscuro parte del tono oscuro, no del pastel.
      accentTint: Color.lerp(
        oscuro ? swatch.darkFill : swatch.fill,
        base,
        oscuro ? 0.72 : 0.62,
      )!,
      accentTintBorder: Color.lerp(
        oscuro ? swatch.darkFill : swatch.fill,
        base,
        oscuro ? 0.35 : 0.28,
      )!,
      success: oscuro ? AppColors.successOnDark : AppColors.success,
      successBg: oscuro ? AppColors.darkSuccessBg : AppColors.successBg,
      neutralBg: oscuro ? AppColors.darkSurfaceMuted : AppColors.neutralBg,
      danger: oscuro ? AppColors.dangerOnDark : AppColors.danger,
    );
  }

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

  /// RELLENO sólido del color elegido: AppBar, barra de navegación, botones
  /// primarios, FAB. Lo que va encima es [onPrimary] y nada más.
  final Color primary;

  /// Único color legible sobre [primary]. En los seis pasteles es tinta
  /// oscura; en navy y wine es blanco, porque sobre un relleno oscuro la
  /// tinta negra da 1.5:1 y no hay forma de arreglarlo.
  final Color onPrimary;

  /// El color elegido como TEXTO/ÍCONO/LÍNEA sobre una superficie neutra
  /// (íconos activos, bordes de foco, indicadores). Ya viene resuelto contra
  /// el tema: el pastel crudo sobre fondo claro no se ve.
  final Color accent;

  /// Lavado del color para fondos de chip, badge y sección. El texto encima
  /// va en [ink], nunca en el color.
  final Color accentTint;
  final Color accentTintBorder;

  /// Fondos de los estados semánticos (disponible / no disponible). Son
  /// colores propios y no el foreground con alpha: un verde sage al 8% sobre
  /// fondo cálido se ensucia y deja de distinguirse del gris de "no
  /// disponible", que es justo la diferencia que el badge tiene que
  /// comunicar. Estos NO se tiñen con el swatch: verde es verde.
  final Color success;
  final Color successBg;
  final Color neutralBg;

  /// Ladrillo apagado legible sobre la superficie del tema actual. Para
  /// rellenos sólidos de error usar [AppColors.danger].
  final Color danger;

  @override
  AppColorSet copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceMuted,
    Color? ink,
    Color? muted,
    Color? mutedStrong,
    Color? border,
    Color? primary,
    Color? onPrimary,
    Color? accent,
    Color? accentTint,
    Color? accentTintBorder,
    Color? success,
    Color? successBg,
    Color? neutralBg,
    Color? danger,
  }) {
    return AppColorSet(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      mutedStrong: mutedStrong ?? this.mutedStrong,
      border: border ?? this.border,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      accentTint: accentTint ?? this.accentTint,
      accentTintBorder: accentTintBorder ?? this.accentTintBorder,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      neutralBg: neutralBg ?? this.neutralBg,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColorSet lerp(ThemeExtension<AppColorSet>? other, double t) {
    if (other is! AppColorSet) return this;
    return AppColorSet(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedStrong: Color.lerp(mutedStrong, other.mutedStrong, t)!,
      border: Color.lerp(border, other.border, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
      accentTintBorder: Color.lerp(
        accentTintBorder,
        other.accentTintBorder,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      neutralBg: Color.lerp(neutralBg, other.neutralBg, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Color de marca elegido por la persona usuaria. Es la raíz de la que sale
/// TODO el color de la app: [AppColorSet.of] lo convierte en la paleta
/// completa y [AppTheme] la mete en el ThemeData, así que cambiar de swatch
/// repinta AppBar, navegación, botones, chips e íconos de una sola vez.
///
/// Lo que NUNCA se tiñe es el contenido: texto, precios y datos van siempre
/// en tinta neutra. Esa frontera es lo que hace viable ofrecer ocho colores
/// sin auditar el contraste de cada pantalla ocho veces.
///
/// Cada swatch necesita CUATRO colores y no uno, porque un mismo tono no
/// puede cumplir los dos trabajos a la vez:
///
///  - [fill] / [darkFill] son el RELLENO sólido de cada tema. El pastel se
///    queda en claro; en oscuro entra su versión normalizada, porque un
///    pastel crudo sobre fondo oscuro deslumbra y rompe la jerarquía.
///  - [onFill] es lo único legible sobre [fill]. Sobre [darkFill] va tinta
///    clara, que la paleta resuelve sola.
///  - [lineLight] / [lineDark] son el color como LÍNEA sobre el fondo de la
///    página, que sí depende del tema: un pastel sobre `#FAFAF8` da 1.4:1 y
///    literalmente no se ve, y un navy sobre `#0E1420` da 1.3:1 y tampoco.
///    Ambas variantes están calculadas al mínimo no-textual de 3:1 (WCAG
///    1.4.11) contra la superficie MENOS favorable de su tema, no contra el
///    fondo: en claro eso es `background` (el más oscuro de los claros) y en
///    oscuro es `darkSurfaceElevated` (el más claro de los oscuros).
class AccentSwatch {
  const AccentSwatch({
    required this.id,
    required this.label,
    required this.fill,
    required this.darkFill,
    required this.onFill,
    required this.lineLight,
    required this.lineDark,
  });

  /// Clave estable de persistencia. Nunca renombrar: es lo que queda
  /// guardado en disco.
  final String id;
  final String label;

  /// Relleno sólido en tema CLARO (AppBar, botón, FAB).
  final Color fill;

  /// El mismo color llevado a tema oscuro: mismo tono, normalizado a una
  /// LUMINANCIA común (~0.075) para los ocho.
  ///
  /// Se normaliza por luminancia relativa y no por claridad HSL porque no
  /// son lo mismo: a igual claridad HSL, un verde y un cian se perciben
  /// bastante más brillantes que un morado, y el modo oscuro terminaba
  /// sintiéndose distinto según el color elegido. Igualando la luminancia,
  /// los ocho pesan lo mismo y el tema oscuro se lee como la misma app.
  ///
  /// Para los seis pasteles esto los OSCURECE (un pastel crudo sobre fondo
  /// oscuro deslumbra y el botón se come la jerarquía); para navy y wine,
  /// que ya son casi negros, los ACLARA, porque si no desaparecerían contra
  /// el fondo. Convergen desde lados opuestos.
  final Color darkFill;

  /// Único color legible sobre [fill]. Los seis pasteles llevan navy y los
  /// dos sobrios llevan blanco, así que el foreground es por swatch y no una
  /// constante del sistema.
  final Color onFill;

  final Color lineLight;
  final Color lineDark;

  /// El color como línea sobre el fondo del tema activo.
  Color line(Brightness brightness) =>
      brightness == Brightness.dark ? lineDark : lineLight;

  /// Seis pasteles editoriales de saturación baja/media más dos tonos
  /// sobrios para quien no quiera pastel. En los pasteles [lineLight] es el
  /// mismo tono profundizado hasta 3:1 con un techo de saturación de 55%,
  /// que es lo que evita que el durazno aterrice en naranja neón y le
  /// dispute el rol de señal al oro.
  static const azulNiebla = AccentSwatch(
    id: 'azul_niebla',
    label: 'Azul niebla',
    fill: Color(0xFFC7D8EE),
    darkFill: Color(0xFF274F81),
    onFill: AppColors.primary,
    lineLight: Color(0xFF6493D0),
    lineDark: Color(0xFFC7D8EE),
  );
  static const salvia = AccentSwatch(
    id: 'salvia',
    label: 'Salvia',
    fill: Color(0xFFC6D8C9),
    darkFill: Color(0xFF2F5735),
    onFill: AppColors.primary,
    lineLight: Color(0xFF6F9C76),
    lineDark: Color(0xFFC6D8C9),
  );
  static const durazno = AccentSwatch(
    id: 'durazno',
    label: 'Durazno',
    fill: Color(0xFFF3D4BE),
    darkFill: Color(0xFF714221),
    onFill: AppColors.primary,
    lineLight: Color(0xFFCA7F4A),
    lineDark: Color(0xFFF3D4BE),
  );
  static const lavanda = AccentSwatch(
    id: 'lavanda',
    label: 'Lavanda',
    fill: Color(0xFFD6D0E8),
    darkFill: Color(0xFF544288),
    onFill: AppColors.primary,
    lineLight: Color(0xFF9888C5),
    lineDark: Color(0xFFD6D0E8),
  );
  static const rosaPolvo = AccentSwatch(
    id: 'rosa_polvo',
    label: 'Rosa polvo',
    fill: Color(0xFFEFD0D4),
    darkFill: Color(0xFF892E3A),
    onFill: AppColors.primary,
    lineLight: Color(0xFFD17783),
    lineDark: Color(0xFFEFD0D4),
  );
  static const celeste = AccentSwatch(
    id: 'celeste',
    label: 'Celeste',
    fill: Color(0xFFC3DDE4),
    darkFill: Color(0xFF2B545F),
    onFill: AppColors.primary,
    lineLight: Color(0xFF4F9BB0),
    lineDark: Color(0xFFC3DDE4),
  );

  // Los dos sobrios invierten el foreground: sobre un relleno oscuro el navy
  // no se lee y el blanco sí.
  static const navy = AccentSwatch(
    id: 'navy',
    label: 'Navy',
    fill: AppColors.primary,
    darkFill: Color(0xFF314C85),
    onFill: Colors.white,
    lineLight: AppColors.primary,
    // Recalibrado tras aclarar el fondo oscuro (ver AppColors.darkSurface*):
    // el mismo tono a 3:1 contra la superficie MENOS favorable de cada
    // versión del tema — que ahora es más clara, así que el tono también.
    lineDark: Color(0xFF6381C6),
  );
  static const wine = AccentSwatch(
    id: 'wine',
    label: 'Wine',
    fill: Color(0xFF6B2737),
    darkFill: Color(0xFF853044),
    onFill: Colors.white,
    lineLight: Color(0xFF6B2737),
    lineDark: Color(0xFFC6647A),
  );

  static const opciones = <AccentSwatch>[
    azulNiebla,
    salvia,
    durazno,
    lavanda,
    rosaPolvo,
    celeste,
    navy,
    wine,
  ];

  /// El swatch por defecto es el navy de la marca: quien nunca entre a
  /// Apariencia ve exactamente la app que veía antes.
  static const defecto = navy;

  /// Resuelve un id guardado en disco. Un id desconocido (swatch retirado en
  /// una versión posterior, dato corrupto) cae al de marca en vez de romper.
  static AccentSwatch porId(String? id) =>
      opciones.firstWhere((s) => s.id == id, orElse: () => defecto);
}

/// Normaliza el color de una categoría para que TODAS pesen visualmente lo
/// mismo sobre la superficie del tema activo.
///
/// Los hex de categoría vienen del backend (`/api/categories`) y no de esta
/// paleta, así que llegan sin ninguna disciplina: saturaciones de 18% (Otros
/// `#607D8B`) a 95% (Apuntes `#D97706`), y contrastes de 3.09:1 (Servicios)
/// a 5.13:1 (Libros) sobre blanco. Esa dispersión de 1.66x es exactamente lo
/// que hace que unas categorías se lean "apagadas" al lado de otras sin que
/// nadie lo haya decidido.
///
/// En oscuro era peor (2.54x) porque la versión anterior clampeaba la
/// LIGHTNESS al rango 0.6-0.85, y lightness igual no es peso percibido
/// igual: a la misma lightness un cian pesa mucho más que un morado. Por eso
/// Electrónicos terminaba en cian neón `#52E0D1` a 8.23:1 mientras Ropa ni
/// se tocaba y se quedaba en 3.24:1, la más apagada de las ocho.
///
/// Lo que se normaliza aquí es el CONTRASTE, no la lightness: se conserva el
/// matiz del backend (es lo que identifica a la categoría), se capa la
/// saturación al mismo techo de 55% que ya usa [AccentSwatch] (es lo que
/// evita que el naranja de Apuntes aterrice en neón) y se resuelve la
/// lightness por tono hasta dar en el contraste objetivo. Resultado: 1.02x
/// de dispersión en claro y 1.03x en oscuro.
///
/// No se unificaron a la familia navy a propósito: el ícono ya carga la
/// identidad de la categoría y el color es señal secundaria, pero ocho tiles
/// en variaciones de un mismo navy se vuelven indistinguibles de un vistazo
/// y se pierde el escaneo rápido, que es para lo que existe esa fila.
Color normalizeCategoryColor(Color base, Brightness brightness) {
  final oscuro = brightness == Brightness.dark;
  // Superficie sobre la que se dibuja el ícono en cada tema (el tile de
  // categoría y la tarjeta de producto usan `colors.surface`, no el fondo).
  final fondo = oscuro ? AppColors.darkSurface : AppColors.surface;
  // En oscuro se apunta un poco más alto porque el ícono va a 14-22px sobre
  // una superficie elevada, donde el mismo ratio se percibe más débil.
  final objetivo = oscuro ? 5.0 : 4.6;

  final hsl = HSLColor.fromColor(base);
  final saturacion = hsl.saturation.clamp(0.0, 0.55);

  double contraste(double lightness) {
    final color = hsl
        .withSaturation(saturacion)
        .withLightness(lightness)
        .toColor();
    final a = color.computeLuminance();
    final b = fondo.computeLuminance();
    final (alta, baja) = a > b ? (a, b) : (b, a);
    return (alta + 0.05) / (baja + 0.05);
  }

  // Sobre fondo claro el contraste BAJA al subir la lightness y sobre fondo
  // oscuro SUBE, así que la búsqueda binaria arranca del rango y la
  // dirección de cada tema. 20 iteraciones dejan el error de lightness por
  // debajo de 1/2^20, muy por debajo de lo que un canal de 8 bits distingue.
  var lo = oscuro ? 0.45 : 0.05;
  var hi = oscuro ? 0.95 : 0.60;
  for (var i = 0; i < 20; i++) {
    final medio = (lo + hi) / 2;
    final sobra = contraste(medio) > objetivo;
    if (oscuro) {
      if (sobra) {
        hi = medio;
      } else {
        lo = medio;
      }
    } else {
      if (sobra) {
        lo = medio;
      } else {
        hi = medio;
      }
    }
  }

  return hsl
      .withSaturation(saturacion)
      .withLightness((lo + hi) / 2)
      .toColor();
}

extension AppColorsContext on BuildContext {
  /// La paleta viaja dentro del ThemeData como [ThemeExtension], no en un
  /// provider aparte: así cambiar de swatch repinta TODA la app por el mismo
  /// camino que ya usa el modo oscuro, y ningún widget necesita suscribirse
  /// a nada.
  ///
  /// El fallback cubre a quien monte un [MaterialApp] con un tema pelado
  /// (varios tests lo hacen): mejor la paleta de marca que un crash.
  AppColorSet get colors {
    final theme = Theme.of(this);
    return theme.extension<AppColorSet>() ??
        AppColorSet.of(AccentSwatch.defecto, theme.brightness);
  }
}

class AppTypography {
  // `color` es OBLIGATORIO en las cuatro — a propósito, sin fallback.
  //
  // Antes caían a `AppColors.ink`, una constante fija de tema claro
  // (#1A1A1D). Cualquier call site que "se olvidara" de pasar color
  // quedaba con texto casi negro sobre fondo oscuro en modo oscuro (1.14:1
  // de contraste — invisible) sin que nada lo avisara: compilaba limpio y
  // se veía bien en claro, que es como sobrevivió sin que nadie lo notara
  // hasta que alguien miró la pantalla en oscuro.
  //
  // Con `color` requerido, omitirlo es un error de compilación, no un
  // valor por defecto silenciosamente equivocado. El call site típico pasa
  // `context.colors.ink` (o `.muted`, `.accent`, etc.) — ya tiene el
  // BuildContext a mano en cualquier `build()`, así que no es más trabajo
  // que antes, solo ya no es opcional.

  // Baloo 2: para precios — redondeada, con carácter de etiqueta de puesto,
  // usada con moderación (solo precios y headlines grandes).
  static TextStyle price(
    double size, {
    required Color color,
    FontWeight weight = FontWeight.w800,
  }) => GoogleFonts.baloo2(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.1,
  );

  // Baloo 2: headings de sección
  static TextStyle heading(
    double size, {
    required Color color,
    FontWeight weight = FontWeight.w700,
  }) => GoogleFonts.baloo2(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.2,
  );

  // Work Sans: cuerpo, descripción, labels
  static TextStyle body(
    double size, {
    required Color color,
    FontWeight weight = FontWeight.w400,
  }) => GoogleFonts.workSans(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.4,
  );

  static TextStyle label(
    double size, {
    required Color color,
    FontWeight weight = FontWeight.w600,
  }) => GoogleFonts.workSans(
    fontSize: size,
    fontWeight: weight,
    color: color,
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

  /// Sombra tintada para elementos que flotan en el color elegido (FAB,
  /// etiqueta de precio con oferta). Recibe el color en vez de leerlo de una
  /// constante: la sombra tiene que ser del mismo tono que lo que la
  /// proyecta, y ese tono ya no es fijo.
  static List<BoxShadow> accent(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.34),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

class AppTheme {
  /// Tema claro pintado con el swatch elegido.
  ///
  /// Todo el color de marca sale de [c]; los neutros y el texto no se tiñen.
  /// Esa separación es lo que permite ofrecer ocho colores sin revisar el
  /// contraste de cada pantalla ocho veces: el texto siempre es tinta sobre
  /// superficie neutra, y el color solo aparece como relleno (con
  /// [AppColorSet.onPrimary] encima) o como línea ya resuelta.
  static ThemeData light([AccentSwatch swatch = AccentSwatch.defecto]) {
    final base = GoogleFonts.workSansTextTheme();
    final c = AppColorSet.of(swatch, Brightness.light);
    final scheme = ColorScheme.fromSeed(seedColor: c.primary).copyWith(
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.accent,
      onSecondary: c.onPrimary,
      tertiary: c.accent,
      surface: c.surface,
      surfaceContainerHighest: c.surfaceMuted,
      outline: c.border,
      outlineVariant: c.border,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [c],
      scaffoldBackgroundColor: c.background,
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
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        surfaceTintColor: Colors.transparent,
        // Los íconos de la barra de estado se eligen según lo claro que sea
        // el AppBar, no fijos: con un swatch pastel el header es claro y
        // unos íconos blancos ahí desaparecerían.
        systemOverlayStyle: swatch.fill.computeLuminance() > 0.45
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.baloo2(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: c.onPrimary,
        ),
        iconTheme: IconThemeData(color: c.onPrimary),
        actionsIconTheme: IconThemeData(color: c.onPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          // El foco usa la variante de LÍNEA: el relleno pastel sobre el
          // blanco del campo no marcaría nada.
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // El botón lleno es la acción principal y va en el color elegido,
          // con el único foreground legible encima de ese relleno.
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.primary.withValues(alpha: 0.38),
          disabledForegroundColor: c.onPrimary.withValues(alpha: 0.55),
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
          foregroundColor: c.accent,
          side: BorderSide(color: c.accentTintBorder),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        // Chip activo con el lavado del color: marca la selección sin gastar
        // relleno sólido, que se reserva a las acciones.
        selectedColor: c.accentTint,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.workSans(
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // El snackbar se queda en tinta neutra: flota sobre cualquier
        // pantalla y teñirlo lo pondría a competir con el contenido.
        backgroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: GoogleFonts.workSans(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: c.border,
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData dark([AccentSwatch swatch = AccentSwatch.defecto]) {
    final base = GoogleFonts.workSansTextTheme(ThemeData.dark().textTheme);
    final c = AppColorSet.of(swatch, Brightness.dark);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: c.primary,
          brightness: Brightness.dark,
        ).copyWith(
          // En oscuro el rol de "primary" de Material lo toma la variante de
          // LÍNEA y no el relleno: un pastel sólido como color de rol haría
          // que Material lo usara de fondo en sitios donde no controlamos el
          // foreground.
          primary: c.accent,
          onPrimary: AppColors.darkBackground,
          secondary: c.accent,
          onSecondary: AppColors.darkBackground,
          tertiary: c.accent,
          surface: c.surface,
          surfaceContainerHighest: c.surfaceMuted,
          outline: c.border,
          outlineVariant: c.border,
          error: AppColors.danger,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [c],
      scaffoldBackgroundColor: c.background,
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
      // En oscuro el AppBar NO se pinta con el relleno del swatch: un
      // pastel claro de header sobre una app oscura invierte la jerarquía y
      // deslumbra. El color entra como línea en el título y los íconos.
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.background,
        foregroundColor: c.ink,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: IconThemeData(color: c.accent),
        actionsIconTheme: IconThemeData(color: c.accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // Mismo par relleno/foreground que en claro: el fondo es el color
          // mismo, así que no depende del tema.
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.primary.withValues(alpha: 0.38),
          disabledForegroundColor: c.onPrimary.withValues(alpha: 0.55),
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
          foregroundColor: c.accent,
          side: BorderSide(color: c.border),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.accentTint,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.workSans(
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: GoogleFonts.workSans(
          color: c.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: c.border,
      visualDensity: VisualDensity.standard,
    );
  }
}
