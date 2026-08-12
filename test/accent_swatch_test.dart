import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';

/// Ratio de contraste WCAG 2.1 entre dos colores opacos.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

void main() {
  // Los dos casos que construyen un ThemeData van como testWidgets y no
  // como test: AppTheme arma su tipografía con GoogleFonts, que necesita el
  // binding y resuelve la fuente de forma asíncrona. Aquí lo que se mide son
  // los colores, no la tipografía.

  // Estos tests son la razón por la que la paleta puede tocarse sin miedo:
  // cualquier swatch nuevo o cualquier retoque "solo un poco más claro"
  // falla aquí antes de llegar a la pantalla de nadie.
  group('AccentSwatch', () {
    test('los 8 swatches tienen id único', () {
      final ids = AccentSwatch.opciones.map((s) => s.id).toSet();
      expect(AccentSwatch.opciones, hasLength(8));
      expect(ids, hasLength(8));
    });

    test('los ids coinciden con VALID_ACCENT_IDS del backend', () {
      // El backend valida el PATCH contra su propia copia de esta lista
      // (backend/src/validation/sellerProfile.js). Si divergen, el color se
      // elige en la app y el servidor lo rechaza con un 400 que nadie
      // relaciona con la paleta. Este test y su gemelo en
      // validation/colorAcento.test.js fallan juntos si alguien toca una
      // lista sin la otra.
      expect(AccentSwatch.opciones.map((s) => s.id).toList(), [
        'azul_niebla',
        'salvia',
        'durazno',
        'lavanda',
        'rosa_polvo',
        'celeste',
        'navy',
        'wine',
      ]);
    });

    test('onFill cumple AA (4.5:1) sobre su propio fill', () {
      for (final s in AccentSwatch.opciones) {
        expect(
          _contraste(s.onFill, s.fill),
          greaterThanOrEqualTo(4.5),
          reason: '${s.label}: el texto del botón no se lee sobre el relleno',
        );
      }
    });

    test('lineLight cumple 3:1 sobre las superficies claras', () {
      // El fondo de página (#FAFAF8) es la restricción vinculante, no el
      // blanco de tarjeta: al ser más oscuro deja menos contraste para un
      // trazo oscuro encima.
      for (final s in AccentSwatch.opciones) {
        expect(
          _contraste(s.lineLight, AppColors.background),
          greaterThanOrEqualTo(3.0),
          reason: '${s.label}: el anillo no se ve sobre el fondo claro',
        );
        expect(
          _contraste(s.lineLight, AppColors.surface),
          greaterThanOrEqualTo(3.0),
          reason: '${s.label}: el anillo no se ve sobre una tarjeta',
        );
      }
    });

    test('lineDark cumple 3:1 sobre las superficies oscuras', () {
      for (final s in AccentSwatch.opciones) {
        expect(
          _contraste(s.lineDark, AppColors.darkBackground),
          greaterThanOrEqualTo(3.0),
          reason: '${s.label}: el anillo no se ve en modo oscuro',
        );
        expect(
          _contraste(s.lineDark, AppColors.darkSurface),
          greaterThanOrEqualTo(3.0),
          reason: '${s.label}: el anillo no se ve sobre una tarjeta oscura',
        );
        // La superficie elevada es la más clara del tema oscuro y por tanto
        // la restricción vinculante: es donde vive el propio selector.
        expect(
          _contraste(s.lineDark, AppColors.darkSurfaceElevated),
          greaterThanOrEqualTo(3.0),
          reason: '${s.label}: el aro de selección se pierde en el selector',
        );
      }
    });

    test('el check de verificación sobrevive sobre cualquier anillo', () {
      // El azul de verificación NUNCA contrasta contra el anillo (1.0-2.1:1
      // según el swatch), así que lo que lo mantiene visible es su contorno
      // en color de fondo. Esto verifica ese contorno, no el azul.
      for (final s in AccentSwatch.opciones) {
        expect(
          _contraste(AppColors.background, s.lineLight),
          greaterThanOrEqualTo(3.0),
          reason: '${s.label}: el contorno del check se pierde en el anillo',
        );
        expect(
          _contraste(AppColors.darkBackground, s.lineDark),
          greaterThanOrEqualTo(3.0),
          reason: '${s.label}: el contorno del check se pierde en oscuro',
        );
      }
    });

    test('line() resuelve la variante del tema activo', () {
      for (final s in AccentSwatch.opciones) {
        expect(s.line(Brightness.light), s.lineLight);
        expect(s.line(Brightness.dark), s.lineDark);
      }
    });

    testWidgets('el ThemeData completo se repinta con el swatch', (_) async {
      // Esto es lo que hacía que "elegir un color" no se notara: antes el
      // swatch solo tocaba tres widgets sueltos y el ThemeData seguía fijo
      // en navy. Ahora AppBar, botones y esquema de color salen del swatch.
      final salvia = AppTheme.light(AccentSwatch.salvia);
      final wine = AppTheme.light(AccentSwatch.wine);

      expect(salvia.appBarTheme.backgroundColor, AccentSwatch.salvia.fill);
      expect(wine.appBarTheme.backgroundColor, AccentSwatch.wine.fill);
      expect(salvia.colorScheme.primary, isNot(wine.colorScheme.primary));
      expect(salvia.scaffoldBackgroundColor, wine.scaffoldBackgroundColor);
    });

    testWidgets('el foreground del AppBar es el legible sobre su relleno', (
      _,
    ) async {
      for (final s in AccentSwatch.opciones) {
        expect(
          AppTheme.light(s).appBarTheme.foregroundColor,
          s.onFill,
          reason: '${s.label}: el título del AppBar no usa su onFill',
        );
      }
    });

    test('en oscuro el relleno NO es el pastel crudo', () {
      // El síntoma que motivó esto: el pastel se colaba tal cual al modo
      // oscuro y el botón quedaba siendo lo más brillante de la pantalla.
      for (final s in AccentSwatch.opciones) {
        final oscuro = AppColorSet.of(s, Brightness.dark);
        expect(
          oscuro.primary,
          isNot(s.fill),
          reason: '${s.label}: el modo oscuro usa el relleno claro',
        );
        expect(oscuro.primary, s.darkFill);
      }
    });

    test('los 6 pasteles se oscurecen para el modo oscuro', () {
      const pasteles = [
        AccentSwatch.azulNiebla,
        AccentSwatch.salvia,
        AccentSwatch.durazno,
        AccentSwatch.lavanda,
        AccentSwatch.rosaPolvo,
        AccentSwatch.celeste,
      ];
      for (final s in pasteles) {
        expect(
          s.darkFill.computeLuminance(),
          lessThan(s.fill.computeLuminance()),
          reason: '${s.label}: su pastel no se oscureció',
        );
      }
    });

    test('navy y wine se aclaran en vez de oscurecerse', () {
      // Convergen desde el lado contrario: ya son casi negros, así que
      // oscurecerlos los haría desaparecer contra el fondo oscuro.
      for (final s in [AccentSwatch.navy, AccentSwatch.wine]) {
        expect(
          s.darkFill.computeLuminance(),
          greaterThan(s.fill.computeLuminance()),
          reason: '${s.label}: se oscureció hasta desaparecer',
        );
      }
    });

    test('los 8 rellenos oscuros pesan lo mismo', () {
      // "El mismo tema, un poco más oscuro": si un swatch quedara más
      // brillante que el resto, el modo oscuro se sentiría distinto según el
      // color elegido. Se compara LUMINANCIA y no claridad HSL — a igual
      // claridad HSL un verde se ve mucho más brillante que un morado, que
      // es justo el error que este test atrapó.
      final luminancias = AccentSwatch.opciones
          .map((s) => s.darkFill.computeLuminance())
          .toList();
      final min = luminancias.reduce((a, b) => a < b ? a : b);
      final max = luminancias.reduce((a, b) => a > b ? a : b);
      expect(max - min, lessThan(0.01), reason: 'luminancias: $luminancias');
    });

    test('la tinta clara se lee sobre cualquier relleno oscuro', () {
      for (final s in AccentSwatch.opciones) {
        final oscuro = AppColorSet.of(s, Brightness.dark);
        expect(
          _contraste(oscuro.onPrimary, oscuro.primary),
          greaterThanOrEqualTo(4.5),
          reason: '${s.label}: el texto del botón no se lee en oscuro',
        );
      }
    });

    test('los neutros NO se tiñen con el swatch', () {
      // El requisito explícito: el texto se queda en tinta pase lo que pase.
      for (final s in AccentSwatch.opciones) {
        final c = AppColorSet.of(s, Brightness.light);
        expect(c.ink, AppColors.ink, reason: '${s.label} tiñó la tinta');
        expect(c.background, AppColors.background);
        expect(c.surface, AppColors.surface);
        expect(c.muted, AppColors.muted);
      }
    });

    test('el lavado del color deja leer tinta encima', () {
      // accentTint es fondo de chip y badge, y lo que va encima es ink.
      for (final s in AccentSwatch.opciones) {
        final claro = AppColorSet.of(s, Brightness.light);
        expect(
          _contraste(claro.ink, claro.accentTint),
          greaterThanOrEqualTo(4.5),
          reason: '${s.label}: la tinta no se lee sobre su lavado claro',
        );
        final oscuro = AppColorSet.of(s, Brightness.dark);
        expect(
          _contraste(oscuro.ink, oscuro.accentTint),
          greaterThanOrEqualTo(4.5),
          reason: '${s.label}: la tinta no se lee sobre su lavado oscuro',
        );
      }
    });

    test('porId cae al swatch de marca ante un id desconocido', () {
      expect(AccentSwatch.porId('salvia').id, 'salvia');
      expect(AccentSwatch.porId(null), AccentSwatch.defecto);
      expect(AccentSwatch.porId('color_retirado'), AccentSwatch.defecto);
    });
  });
}
