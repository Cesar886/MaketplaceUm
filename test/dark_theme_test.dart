import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mercadito_um/app_theme.dart';

/// Ratio de contraste WCAG 2.1 entre dos colores OPACOS.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

/// Mezcla [fg] (con su propio alpha) sobre [bg] opaco — lo que Flutter
/// pinta de verdad cuando un color translúcido se dibuja encima de una
/// superficie. Necesario porque [darkMuted]/[darkMutedStrong] son blanco
/// con alpha, no un gris sólido: su contraste real depende de qué hay
/// debajo, y `computeLuminance()` de un color con alpha < 255 no es ese
/// resultado.
Color _sobre(Color fg, Color bg) {
  // `.r`/`.g`/`.b`/`.a` son dobles en [0, 1] en el Color moderno de
  // Flutter, no bytes 0-255 — mezclarlos directo con `fromARGB` (que sí
  // espera bytes) daba una composición rota y contrastes falsos.
  final a = fg.a;
  return Color.from(
    alpha: 1.0,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

void main() {
  group('Fondo oscuro', () {
    test('background ya no es casi negro', () {
      // Regresión directa del reporte: el navy casi negro (#0E1420, lum
      // ≈0.007) leía como "apagado" en vez de "de noche". El nuevo fondo
      // tiene que ser sensiblemente más claro.
      expect(AppColors.darkBackground.computeLuminance(), greaterThan(0.015));
    });

    test(
      'la jerarquía por elevación se mantiene: fondo < surface < elevada',
      () {
        final bg = AppColors.darkBackground.computeLuminance();
        final surf = AppColors.darkSurface.computeLuminance();
        final elev = AppColors.darkSurfaceElevated.computeLuminance();
        expect(surf, greaterThan(bg));
        expect(elev, greaterThan(surf));
      },
    );
  });

  group('Texto en modo oscuro', () {
    test('el texto principal es blanco puro, no un gris con tinte', () {
      expect(AppColors.darkInk, Colors.white);
    });

    test('muted y mutedStrong son el MISMO blanco a distinta opacidad', () {
      expect(AppColors.darkMuted.toARGB32() & 0x00FFFFFF, 0x00FFFFFF);
      expect(AppColors.darkMutedStrong.toARGB32() & 0x00FFFFFF, 0x00FFFFFF);
      expect(
        AppColors.darkMutedStrong.a,
        greaterThan(AppColors.darkMuted.a),
        reason: 'mutedStrong debe pesar más que muted para que haya jerarquía',
      );
    });

    test('incluso el nivel más tenue (muted) cumple AA sobre el fondo', () {
      final compuesto = _sobre(AppColors.darkMuted, AppColors.darkBackground);
      expect(
        _contraste(compuesto, AppColors.darkBackground),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('mutedStrong se lee incluso sobre la superficie elevada', () {
      final compuesto = _sobre(
        AppColors.darkMutedStrong,
        AppColors.darkSurfaceElevated,
      );
      expect(
        _contraste(compuesto, AppColors.darkSurfaceElevated),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('AppColorSet.of expone la misma jerarquía blanca en oscuro', () {
      for (final s in AccentSwatch.opciones) {
        final c = AppColorSet.of(s, Brightness.dark);
        expect(c.ink, Colors.white, reason: '${s.label}: ink no es blanco');
        expect(c.muted, AppColors.darkMuted);
        expect(c.mutedStrong, AppColors.darkMutedStrong);
        expect(c.mutedStrong.a, greaterThan(c.muted.a));
      }
    });

    test('en claro el texto NO cambia: sigue siendo tinta, no blanco', () {
      // La consigna era "solo en el tema oscuro" — este test es la mitad
      // que evita que alguien generalice el cambio sin querer.
      final c = AppColorSet.of(AccentSwatch.defecto, Brightness.light);
      expect(c.ink, AppColors.ink);
      expect(c.ink, isNot(Colors.white));
    });
  });

  group('Regresión: título de producto invisible en oscuro', () {
    // El bug reportado: `AppTypography.heading/body/label/price` caían a
    // `AppColors.ink` (constante fija de tema claro, #1A1A1D) cuando el call
    // site no pasaba `color:` — daba 1.14:1 de contraste contra el fondo
    // oscuro, prácticamente invisible. La corrección de raíz hizo `color`
    // OBLIGATORIO en las cuatro, así que omitirlo hoy es un error de
    // compilación (lo prueba `flutter analyze`, no algo testeable en
    // runtime). Lo que SÍ hay que fijar en runtime es que el patrón
    // correcto — pasar `context.colors.ink` — de verdad resuelve a un color
    // legible en oscuro, y no al valor viejo por accidente.
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    Future<Color> colorRenderizado(
      WidgetTester tester,
      AccentSwatch swatch,
      Brightness brillo,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: brillo == Brightness.dark
              ? AppTheme.dark(swatch)
              : AppTheme.light(swatch),
          home: Builder(
            builder: (context) => Scaffold(
              body: Text(
                'Título de producto',
                key: const Key('titulo'),
                style: AppTypography.heading(20, color: context.colors.ink),
              ),
            ),
          ),
        ),
      );
      final texto = tester.widget<Text>(find.byKey(const Key('titulo')));
      return texto.style!.color!;
    }

    testWidgets(
      'en oscuro el título NO usa el AppColors.ink fijo (el bug original)',
      (tester) async {
        final color = await colorRenderizado(
          tester,
          AccentSwatch.defecto,
          Brightness.dark,
        );
        expect(
          color,
          isNot(AppColors.ink),
          reason: 'volvió a caer en la constante fija de tema claro',
        );
      },
    );

    testWidgets(
      'en oscuro el título es legible contra el fondo real de la app',
      (tester) async {
        final color = await colorRenderizado(
          tester,
          AccentSwatch.defecto,
          Brightness.dark,
        );
        expect(
          _contraste(color, AppColors.darkBackground),
          greaterThanOrEqualTo(4.5),
        );
      },
    );

    testWidgets(
      'en claro el título sigue siendo tinta, sin cambiar de comportamiento',
      (tester) async {
        final color = await colorRenderizado(
          tester,
          AccentSwatch.defecto,
          Brightness.light,
        );
        expect(color, AppColors.ink);
      },
    );

    testWidgets(
      'el mismo patrón es legible en oscuro con cualquier swatch elegido',
      (tester) async {
        for (final swatch in AccentSwatch.opciones) {
          final color = await colorRenderizado(tester, swatch, Brightness.dark);
          expect(
            _contraste(color, AppColors.darkBackground),
            greaterThanOrEqualTo(4.5),
            reason: '${swatch.label}: el título no se lee en oscuro',
          );
        }
      },
    );
  });
}
