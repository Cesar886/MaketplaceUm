# MercadoUm Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rediseñar visualmente MercadoUm con un sistema de diseño propio ("Tianguis Digital"): nueva paleta, tipografía Sora+Nunito, elemento firma (PriceTag asimétrico en ámbar), y animaciones premium — sin tocar lógica funcional.

**Architecture:** Sistema centralizado en `app_theme.dart`; elemento firma extraído a `lib/widgets/price_tag.dart`; animaciones de entrada en `home_screen.dart` con `AnimationController` + `Interval`; transición de detalle con `PageRouteBuilder` con spring physics; nav bar con FAB embebido.

**Tech Stack:** Flutter, `google_fonts` (Sora + Nunito), Material 3, `AnimationController`, `CurvedAnimation`, `Hero`, `PageRouteBuilder`.

## Global Constraints

- No modificar lógica de negocio: stock, precios, chat, auth, push — solo visual.
- No agregar animaciones en más de los lugares especificados — disciplina de "uno firma, todo lo demás limpio".
- `google_fonts` usa SIL Open Font License — sin restricciones.
- Target: Android mobile, orientación portrait.
- Flutter SDK `^3.11.4`, Dart `^3.x`.
- El verde primario actual (`#256B5F`) se reemplaza con `#1F6357`. Actualizar todas las referencias a `AppColors.primary`.
- No usar `withOpacity()` — usar `withValues(alpha: x)` (ya es el patrón en el proyecto).

---

## Mapa de archivos

| Archivo | Acción | Responsabilidad |
|---|---|---|
| `pubspec.yaml` | Modificar | Agregar `google_fonts` |
| `lib/app_theme.dart` | Reemplazar | Paleta nueva, tipografía, ThemeData, constantes de animación |
| `lib/widgets/price_tag.dart` | Crear | Elemento firma: etiqueta de precio con animación de entrada |
| `lib/widgets/product_card.dart` | Modificar | Usar PriceTag, imagen 16:10, radius 14, stagger-ready |
| `lib/screens/home_screen.dart` | Modificar | AnimationController para staggered entrance de cards |
| `lib/screens/product_detail_screen.dart` | Modificar | PriceTag grande, custom spring PageRoute |
| `lib/screens/main_shell.dart` | Modificar | FAB embebido ámbar para "Publicar", nav bar restyled |
| `lib/screens/publish_product_screen.dart` | Modificar | AppBar + sección header con nuevo estilo |

---

## Task 1: Agregar google_fonts

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Produce: paquete `google_fonts` disponible en el proyecto

- [ ] **Step 1: Agregar dependencia**

En `pubspec.yaml`, bajo `dependencies:` (después de `shared_preferences`), agregar:
```yaml
  google_fonts: ^6.2.1
```

- [ ] **Step 2: Instalar**

```bash
cd /home/daniel/mercaditoUM && flutter pub get
```

Esperado: `Resolving dependencies... Got dependencies!` sin errores.

- [ ] **Step 3: Verificar compilación básica**

```bash
cd /home/daniel/mercaditoUM && flutter build apk --debug 2>&1 | tail -5
```

Esperado: `Built build/app/outputs/flutter-apk/app-debug.apk` o solo errores de linting, no de compilación.

- [ ] **Step 4: Commit**

```bash
cd /home/daniel/mercaditoUM && git add pubspec.yaml pubspec.lock && git commit -m "chore: add google_fonts dependency"
```

---

## Task 2: Reemplazar app_theme.dart

**Files:**
- Modify: `lib/app_theme.dart`

**Interfaces:**
- Produce:
  - `AppColors` — todos los colores como `static const Color`
  - `AppTypography` — `static TextStyle price(double size)`, `static TextStyle heading(double size)`, `static TextStyle body(double size)`, `static TextStyle label(double size)`
  - `AppAnimations` — `static const Duration fast`, `medium`, `slow`; `static const Curve spring`, `easeOut`
  - `AppShadows` — sin cambios de interfaz, solo valores ajustados
  - `AppTheme.light` y `AppTheme.dark` — `ThemeData` completo con Nunito como fontFamily base

- [ ] **Step 1: Reemplazar el archivo completo**

Reemplazar `lib/app_theme.dart` con:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // ─── Paleta principal ────────────────────────────────────
  static const primary = Color(0xFF1F6357);       // Verde Mercado
  static const primaryDark = Color(0xFF122E28);   // Verde noche (sombras, overlays)
  static const amber = Color(0xFFE8A614);          // Ámbar Maíz — signature accent
  static const amberDark = Color(0xFFB37E0A);      // Ámbar oscuro para texto sobre amber
  static const gold = Color(0xFFC79A3B);           // Dorado — featured/premium (sin cambios)
  static const champagne = Color(0xFFFBF6EA);      // Fondo premium badge (sin cambios)
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
```

- [ ] **Step 2: Verificar compilación**

```bash
cd /home/daniel/mercaditoUM && flutter analyze lib/app_theme.dart 2>&1
```

Esperado: sin errores de tipo. Puede haber warnings de otras partes del proyecto (no son nuestros).

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM && git add lib/app_theme.dart && git commit -m "feat: nueva paleta y tipografía Sora+Nunito en app_theme"
```

---

## Task 3: Crear lib/widgets/price_tag.dart (el elemento firma)

**Files:**
- Create: `lib/widgets/price_tag.dart`

**Interfaces:**
- Produce:
  - `PriceTag({required Product product, this.large = false})` — widget que consume `Product` del modelo existente
  - `AnimatedPriceTag({required Product product, required Animation<double> animation, this.large = false})` — versión animada con stamp de entrada

- [ ] **Step 1: Crear el archivo**

```dart
// lib/widgets/price_tag.dart
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';

/// Etiqueta de precio con forma asimétrica — el elemento firma de MercadoUm.
/// 
/// En oferta: fondo ámbar, esquina superior izquierda recta (simulando etiqueta doblada).
/// Sin oferta: solo texto plano en Sora Bold.
class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.product, this.large = false});

  final Product product;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return _PriceTagContent(product: product, large: large);
  }
}

/// Versión animada: escala desde 0.7 con fade al aparecer (efecto stamp).
class AnimatedPriceTag extends StatelessWidget {
  const AnimatedPriceTag({
    super.key,
    required this.product,
    required this.animation,
    this.large = false,
  });

  final Product product;
  final Animation<double> animation;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.78, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: AppAnimations.entrance),
        ),
        alignment: Alignment.centerLeft,
        child: _PriceTagContent(product: product, large: large),
      ),
    );
  }
}

class _PriceTagContent extends StatelessWidget {
  const _PriceTagContent({required this.product, required this.large});

  final Product product;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final hasOffer = product.isOffer;
    final priceSize = large ? 26.0 : 17.0;
    final oldPriceSize = large ? 14.0 : 12.0;
    final discountSize = large ? 13.0 : 11.0;

    if (!hasOffer) {
      // Sin oferta: precio plano, sin contenedor
      return Text(
        Product.formatPrice(product.price),
        style: AppTypography.price(priceSize, color: AppColors.ink),
      );
    }

    // Con oferta: etiqueta ámbar asimétrica
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.amber,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),      // esquina doblada — el detalle que nos identifica
          topRight: Radius.circular(13),
          bottomRight: Radius.circular(13),
          bottomLeft: Radius.circular(13),
        ),
        boxShadow: large ? AppShadows.amber : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: large ? 12 : 8,
          vertical: large ? 7 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              Product.formatPrice(product.price),
              style: AppTypography.price(priceSize, color: AppColors.amberDark),
            ),
            if (product.previousPrice != null) ...[
              const SizedBox(width: 6),
              Text(
                Product.formatPrice(product.previousPrice!),
                style: AppTypography.body(
                  oldPriceSize,
                  color: AppColors.amberDark.withValues(alpha: 0.60),
                ).copyWith(decoration: TextDecoration.lineThrough),
              ),
              const SizedBox(width: 5),
              Text(
                product.discountLabel ?? '',
                style: AppTypography.label(
                  discountSize,
                  color: AppColors.amberDark,
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verificar que compila**

```bash
cd /home/daniel/mercaditoUM && flutter analyze lib/widgets/price_tag.dart 2>&1
```

Esperado: sin errores de tipo.

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM && git add lib/widgets/price_tag.dart && git commit -m "feat: PriceTag widget — elemento firma con animación stamp"
```

---

## Task 4: Actualizar product_card.dart

**Files:**
- Modify: `lib/widgets/product_card.dart`

**Interfaces:**
- Consume: `PriceTag`, `AnimatedPriceTag` de `price_tag.dart`
- Produce: `ProductCard` — acepta nuevo param `animationValue` opcional (`double? animationValue` 0.0–1.0) para stagger desde el feed

**Cambios clave:**
- Imagen: aspect ratio 16:10 (no altura fija 100px)
- Card radius: 14 (de 10)
- Sin border en cards normales, solo border en oferta/destacado
- `_PriceBlock` reemplazado por `PriceTag` / `AnimatedPriceTag`
- Nombre del producto en `AppTypography.label`
- Descripción en `AppTypography.body`

- [ ] **Step 1: Reemplazar el archivo**

```dart
// lib/widgets/product_card.dart
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'badges.dart';
import 'mock_product_image.dart';
import 'price_tag.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.width,
    this.horizontal = false,
    this.heroEnabled = true,
    this.animationValue,
  });

  final Product product;
  final VoidCallback? onTap;
  final double? width;
  final bool horizontal;
  final bool heroEnabled;

  /// 0.0 → invisible, 1.0 → fully visible. Null = sin animación.
  final double? animationValue;

  @override
  Widget build(BuildContext context) {
    Widget card = _buildCard(context);

    if (animationValue != null) {
      final anim = animationValue!.clamp(0.0, 1.0);
      card = Opacity(
        opacity: Curves.easeOut.transform(anim),
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - Curves.easeOutCubic.transform(anim))),
          child: card,
        ),
      );
    }

    if (width == null) return card;
    return SizedBox(width: width, child: card);
  }

  Widget _buildCard(BuildContext context) {
    final hasAccent = product.isOffer || product.isFeatured;
    final borderColor = product.isOffer
        ? AppColors.amber.withValues(alpha: 0.35)
        : product.isFeatured
            ? AppColors.gold.withValues(alpha: 0.35)
            : Colors.transparent;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: hasAccent ? AppShadows.lifted : AppShadows.soft,
      ),
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor, width: hasAccent ? 1.5 : 0),
        ),
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.primary.withValues(alpha: 0.06),
          highlightColor: AppColors.primary.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: horizontal
                ? _HorizontalProductCard(product: product, heroEnabled: heroEnabled)
                : _GridProductCard(product: product, heroEnabled: heroEnabled),
          ),
        ),
      ),
    );
  }
}

class _GridProductCard extends StatelessWidget {
  const _GridProductCard({required this.product, required this.heroEnabled});

  final Product product;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroProductImage(
          product: product,
          enabled: heroEnabled,
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: MockProductImage(product: product, height: double.infinity),
          ),
        ),
        const SizedBox(height: 9),
        PriceTag(product: product),
        const SizedBox(height: 5),
        Text(
          product.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.label(13.5, weight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          product.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.body(12, color: AppColors.muted),
        ),
        const Spacer(),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                product.publishedAgo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(11, color: AppColors.muted),
              ),
            ),
            if (product.availability != null)
              AvailabilityBadge(availability: product.availability!),
          ],
        ),
      ],
    );
  }
}

class _HorizontalProductCard extends StatelessWidget {
  const _HorizontalProductCard({required this.product, required this.heroEnabled});

  final Product product;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: _HeroProductImage(
            product: product,
            enabled: heroEnabled,
            child: MockProductImage(product: product, height: 96),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PriceTag(product: product),
              const SizedBox(height: 5),
              Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label(13.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                product.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(12, color: AppColors.muted),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(product.category.icon, size: 14, color: product.category.color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      product.category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(11, color: AppColors.muted),
                    ),
                  ),
                  Text(
                    product.publishedAgo,
                    style: AppTypography.body(11, color: AppColors.muted),
                  ),
                  if (product.availability != null) ...[
                    const SizedBox(width: 6),
                    AvailabilityBadge(availability: product.availability!),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroProductImage extends StatelessWidget {
  const _HeroProductImage({
    required this.product,
    required this.enabled,
    required this.child,
  });

  final Product product;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: child,
    );

    if (!product.isAvailable) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.65),
                ),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    'Agotado',
                    style: AppTypography.label(13, weight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!enabled) return content;
    return Hero(tag: 'product-${product.id}', child: content);
  }
}
```

- [ ] **Step 2: Verificar compilación**

```bash
cd /home/daniel/mercaditoUM && flutter analyze lib/widgets/product_card.dart 2>&1
```

Esperado: sin errores.

- [ ] **Step 3: Commit**

```bash
cd /home/daniel/mercaditoUM && git add lib/widgets/product_card.dart && git commit -m "feat: rediseño ProductCard — imagen 16:10, radius 14, PriceTag"
```

---

## Task 5: Agregar staggered animations en home_screen.dart

**Files:**
- Modify: `lib/screens/home_screen.dart`

**Goal:** Las cards del feed principal entran con un efecto staggered — cada card aparece con un delay escalonado (slide-up + fade), dando sensación de contenido "llegando" al pantalla.

**Interfaz:** `ProductCard` ya acepta `animationValue` — solo hay que pasarle el valor correcto según el índice en el grid.

**Strategy:** Usar `AnimationController` que va de 0→1 cuando `_loading` pasa a `false`. Cada card recibe `animationValue` derivado de su índice con un `Interval` de duración `staggerDelay * index`.

- [ ] **Step 1: Leer el build actual del grid en home_screen.dart**

Buscar en `home_screen.dart` el `SliverGrid` o `GridView` donde se renderizan los productos (`_GridProductCard`, `ProductCard`, etc). El grid está alrededor de la línea 200+.

- [ ] **Step 2: Agregar AnimationController al State**

En `_HomeScreenState`, agregar:

```dart
// Al inicio de la clase State:
late final AnimationController _staggerController;

@override
void initState() {
  super.initState();
  _staggerController = AnimationController(
    vsync: this,
    duration: AppAnimations.slow + AppAnimations.staggerDelay * 12,
  );
  _loadData();
}

@override
void dispose() {
  _staggerController.dispose();
  super.dispose();
}
```

Agregar `with TickerProviderStateMixin` (o `SingleTickerProviderStateMixin`) al mixin list del State:
```dart
class _HomeScreenState extends State<HomeScreen> with AutoRefreshMixin, TickerProviderStateMixin {
```

- [ ] **Step 3: Disparar animación al terminar de cargar**

En `_loadData()`, después de `setState(() { _loading = false; ... })`:
```dart
_staggerController.forward(from: 0);
```

- [ ] **Step 4: Pasar animationValue a cada ProductCard del grid**

Donde se construyen las cards del grid principal (buscar el lugar donde se hace `ProductCard(product: p, ...)`), agregar un índice `i` y pasar:

```dart
ProductCard(
  product: p,
  // ... otros params existentes ...
  animationValue: _staggerController.value == 0
      ? 0.0
      : Animation<double>.fromValueListenable(
          _staggerController,
          transformer: (v) => CurvedAnimation(
            parent: _staggerController,
            curve: Interval(
              (AppAnimations.staggerDelay.inMilliseconds * i) /
                  _staggerController.duration!.inMilliseconds,
              ((AppAnimations.staggerDelay.inMilliseconds * i) +
                      AppAnimations.slow.inMilliseconds) /
                  _staggerController.duration!.inMilliseconds,
              curve: AppAnimations.spring,
            ),
          ).value,
        ).value,
)
```

**Nota importante:** Para simplificar, usar un `AnimatedBuilder` que envuelva el grid y recalcule `animationValue` per-card:

```dart
AnimatedBuilder(
  animation: _staggerController,
  builder: (context, _) {
    return SliverGrid(
      // ... delegate existente ...
      // Dentro, al construir cada card con índice i:
      // animationValue: _cardAnimValue(i)
    );
  },
)
```

Función helper en el State:
```dart
double _cardAnimValue(int index) {
  final total = _staggerController.duration!.inMilliseconds.toDouble();
  final start = (AppAnimations.staggerDelay.inMilliseconds * index) / total;
  final end = start + (AppAnimations.slow.inMilliseconds / total);
  final interval = CurvedAnimation(
    parent: _staggerController,
    curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0), curve: AppAnimations.spring),
  );
  return interval.value;
}
```

- [ ] **Step 5: Verificar compilación**

```bash
cd /home/daniel/mercaditoUM && flutter analyze lib/screens/home_screen.dart 2>&1
```

- [ ] **Step 6: Commit**

```bash
cd /home/daniel/mercaditoUM && git add lib/screens/home_screen.dart && git commit -m "feat: staggered entrance animation en feed de productos"
```

---

## Task 6: Actualizar product_detail_screen.dart

**Files:**
- Modify: `lib/screens/product_detail_screen.dart`

**Goal:**
1. Usar `PriceTag(product: product, large: true)` con `AnimatedPriceTag` en la sección de precio
2. Mejorar tipografía del título y descripción con `AppTypography`
3. Crear `SpringDetailRoute<T>` — `PageRouteBuilder` con spring easing para la transición de entrada
4. Actualizar las llamadas a `Navigator.push` en home/main_shell que abren el detalle

**Interfaz:** `SpringDetailRoute<T extends Widget>({required Widget page})` — devuelve `Route<T>` usando slide-up + fade con `Curves.easeOutCubic`.

- [ ] **Step 1: Crear SpringDetailRoute al final de product_detail_screen.dart**

Al final del archivo, agregar:

```dart
/// Transición premium para abrir pantalla de detalle: slide-up + fade con spring easing.
Route<T> springDetailRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: AppAnimations.slow,
    reverseTransitionDuration: AppAnimations.medium,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: AppAnimations.spring));

      final fade = Tween<double>(begin: 0.0, end: 1.0)
          .animate(CurvedAnimation(parent: animation, curve: const Interval(0, 0.6, curve: Curves.easeOut)));

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}
```

- [ ] **Step 2: Reemplazar el precio en el build de la pantalla de detalle**

Buscar donde se muestra el precio en el `build()` de `_ProductDetailScreenState`. Actualmente hay un `_PriceBlock` o texto directo. Reemplazarlo con:

```dart
// Agregar al initState:
late final AnimationController _priceTagController;

// En initState():
_priceTagController = AnimationController(
  vsync: this,
  duration: AppAnimations.medium,
);
// Disparar después de un frame para que sea visible el efecto
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) _priceTagController.forward();
});

// En dispose():
_priceTagController.dispose();
```

Y en el widget tree donde va el precio:
```dart
AnimatedPriceTag(
  product: product,
  animation: _priceTagController,
  large: true,
),
```

Agregar `SingleTickerProviderStateMixin` al State si no lo tiene (o cambiarlo por `TickerProviderStateMixin` si ya tiene otro controller).

- [ ] **Step 3: Mejorar tipografía del título y descripción**

Buscar el `Text` del título del producto en el detail screen y aplicar:
```dart
Text(
  product.title,
  style: AppTypography.heading(20),
),
```

Para la descripción:
```dart
Text(
  product.description,
  style: AppTypography.body(15, color: AppColors.muted),
),
```

- [ ] **Step 4: Agregar `_lowest30d` price hint si existe**

Donde se muestra el precio histórico (ya existe lógica de `_lowest30d`), wrap con:
```dart
if (_lowest30d != null)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(Icons.trending_down_rounded, size: 14, color: AppColors.success),
        const SizedBox(width: 4),
        Text(
          'Mínimo en 30 días: ${Product.formatPrice(_lowest30d!)}',
          style: AppTypography.label(12, color: AppColors.success),
        ),
      ],
    ),
  ),
```

- [ ] **Step 5: Actualizar Navigator.push en home_screen.dart para usar springDetailRoute**

En `home_screen.dart`, buscar todas las llamadas que abren `ProductDetailScreen`:
```dart
// Antes:
MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p))
// Después:
springDetailRoute(ProductDetailScreen(product: p))
```

Importar: `import '../screens/product_detail_screen.dart';` ya debería estar.

- [ ] **Step 6: Verificar**

```bash
cd /home/daniel/mercaditoUM && flutter analyze lib/screens/product_detail_screen.dart lib/screens/home_screen.dart 2>&1
```

- [ ] **Step 7: Commit**

```bash
cd /home/daniel/mercaditoUM && git add lib/screens/product_detail_screen.dart lib/screens/home_screen.dart && git commit -m "feat: AnimatedPriceTag en detalle + spring page transition"
```

---

## Task 7: Actualizar main_shell.dart — FAB embebido en nav

**Files:**
- Modify: `lib/screens/main_shell.dart`

**Goal:** El ítem "Publicar" del nav bar se convierte en un FAB ámbar visible y elevado. Los demás ítems del nav se mantienen iguales en lógica, mejorados en estilo.

**Approach:** Reemplazar `NavigationBar` con un `BottomAppBar` custom que tenga los ítems como `IconButton` a mano, con el FAB ámbar en el centro. Esto da control total sobre el visual sin afectar la navegación.

- [ ] **Step 1: Reemplazar el NavigationBar por layout custom**

En `main_shell.dart`, el `bottomNavigationBar` pasa a ser:

```dart
bottomNavigationBar: SafeArea(
  top: false,
  child: DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
    ),
    child: SizedBox(
      height: 66,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Inicio', index: 0, currentIndex: _currentIndex, onTap: selectTab,
            badge: _unreadNotifCount > 0 ? _unreadNotifCount : null),
          _NavItem(icon: Icons.local_offer_outlined, selectedIcon: Icons.local_offer_rounded, label: 'Ofertas', index: 1, currentIndex: _currentIndex, onTap: selectTab),
          // FAB central ámbar
          _PublishFab(onTap: () => selectTab(2)),
          _NavItem(icon: Icons.favorite_outline_rounded, selectedIcon: Icons.favorite_rounded, label: 'Favs', index: 3, currentIndex: _currentIndex, onTap: selectTab),
          _NavItem(icon: Icons.chat_outlined, selectedIcon: Icons.chat_rounded, label: 'Chat', index: 4, currentIndex: _currentIndex, onTap: selectTab,
            badge: _unreadChatCount > 0 ? _unreadChatCount : null),
        ],
      ),
    ),
  ),
),
```

- [ ] **Step 2: Agregar widgets helper al final del archivo**

```dart
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final selected = index == currentIndex;
    final color = selected ? AppColors.primary : AppColors.muted;

    Widget iconWidget = Icon(
      selected ? selectedIcon : icon,
      size: 24,
      color: color,
    );

    if (badge != null && badge! > 0) {
      iconWidget = Badge.count(
        count: badge!,
        backgroundColor: AppColors.primary,
        child: iconWidget,
      );
    }

    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: AppAnimations.fast,
          curve: AppAnimations.spring,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1.0,
                duration: AppAnimations.fast,
                curve: AppAnimations.spring,
                child: iconWidget,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppTypography.label(
                  10,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublishFab extends StatelessWidget {
  const _PublishFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.amber,
            shape: BoxShape.circle,
            boxShadow: AppShadows.amber,
          ),
          child: const SizedBox(
            width: 52,
            height: 52,
            child: Icon(Icons.add_rounded, color: AppColors.amberDark, size: 28),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Quitar el ítem de Perfil del nav si son 6 ítems y no caben bien**

El nav original tiene 6 ítems (Inicio, Ofertas, Publicar, Favoritos, Chat, Perfil). En el nuevo layout con FAB, se queda en 4 + FAB = 5 elementos. Perfil (`index: 5`) se omite del Row pero debe seguir siendo accesible — puede abrirse desde el header de HomeScreen o desde ProfileScreen directamente. **Solo omitir si el diseño no cabe cómodamente en pantalla de 360dp.** Ajustar según prueba visual.

- [ ] **Step 4: Verificar**

```bash
cd /home/daniel/mercaditoUM && flutter analyze lib/screens/main_shell.dart 2>&1
```

- [ ] **Step 5: Commit**

```bash
cd /home/daniel/mercaditoUM && git add lib/screens/main_shell.dart && git commit -m "feat: FAB ámbar embebido en nav bar + iconos con scale animation"
```

---

## Task 8: Estilizar publish_product_screen.dart

**Files:**
- Modify: `lib/screens/publish_product_screen.dart`

**Goal:** La pantalla de publicar hereda automáticamente los estilos del tema (inputs, botones, chips). Solo hay que asegurarse de que el AppBar y los headers de sección usen la nueva tipografía.

- [ ] **Step 1: Actualizar AppBar**

Buscar el `AppBar` en el build y ajustar title:
```dart
AppBar(
  title: Text('Publicar producto', style: AppTypography.heading(18)),
  backgroundColor: AppColors.background,
  foregroundColor: AppColors.ink,
  elevation: 0,
  scrolledUnderElevation: 0,
),
```

- [ ] **Step 2: Actualizar headers de sección**

Buscar los `Text` que funcionan como títulos de sección dentro del formulario (ej: "Imágenes", "Categoría", "Precio", etc.) y aplicar:
```dart
Text('Categoría', style: AppTypography.heading(15)),
```

- [ ] **Step 3: Verificar**

```bash
cd /home/daniel/mercaditoUM && flutter analyze lib/screens/publish_product_screen.dart 2>&1
```

- [ ] **Step 4: Commit**

```bash
cd /home/daniel/mercaditoUM && git add lib/screens/publish_product_screen.dart && git commit -m "feat: tipografía AppTypography en pantalla publicar"
```

---

## Self-Review

**Spec coverage:**
- ✅ Paleta nueva (#1F6357 verde, #E8A614 ámbar, #F5F2EB fondo) → Task 2
- ✅ Tipografía Sora + Nunito → Task 2
- ✅ Elemento firma (PriceTag asimétrico con animación stamp) → Task 3
- ✅ Cards con imagen 16:10, radius 14 → Task 4
- ✅ Staggered animations en feed → Task 5
- ✅ Detalle con AnimatedPriceTag y spring transition → Task 6
- ✅ Nav bar con FAB ámbar + scale feedback en ítems → Task 7
- ✅ Pantalla publicar restyled → Task 8
- ✅ Lógica funcional intacta (solo cambios visuales en todos los tasks)

**Placeholder scan:** Ningún TBD o TODO en el plan.

**Type consistency:**
- `AppColors.amber` / `AppColors.amberDark` / `AppColors.primaryDark` — definidos en Task 2, usados en Tasks 3, 4, 7 ✅
- `AppTypography.price()`, `.heading()`, `.body()`, `.label()` — definidos en Task 2, usados en Tasks 3, 4, 6, 7, 8 ✅
- `AppAnimations.fast/medium/slow/spring/entrance` — definidos en Task 2, usados en Tasks 4, 5, 6, 7 ✅
- `AppShadows.amber` — definido en Task 2, usado en Tasks 3, 7 ✅
- `springDetailRoute<T>(Widget)` — definido y usado en Task 6 ✅
- `ProductCard.animationValue` — agregado en Task 4, consumido en Task 5 ✅
