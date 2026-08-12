import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';

/// Ratio de contraste WCAG 2.1 entre dos colores OPACOS.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

void main() {
  group('AppColorSet.inverted', () {
    test('voltea el tema y conserva el swatch elegido', () {
      for (final swatch in AccentSwatch.opciones) {
        for (final brillo in Brightness.values) {
          final set = AppColorSet.of(swatch, brillo);
          final invertido = set.inverted;

          expect(
            invertido.swatch,
            swatch,
            reason: 'invertir no debe cambiar el color que la persona eligió',
          );
          expect(
            invertido.brightness,
            brillo == Brightness.dark ? Brightness.light : Brightness.dark,
            reason: 'el tema sí se voltea',
          );
        }
      }
    });

    test('invertir dos veces devuelve la paleta original', () {
      for (final swatch in AccentSwatch.opciones) {
        for (final brillo in Brightness.values) {
          final set = AppColorSet.of(swatch, brillo);
          final ida = set.inverted.inverted;

          expect(ida.brightness, set.brightness);
          expect(ida.swatch, set.swatch);
          expect(ida.primary, set.primary);
          expect(ida.onPrimary, set.onPrimary);
        }
      }
    });

    test(
      'el número del badge se lee sobre su propio fondo en los 8 swatches',
      () {
        for (final swatch in AccentSwatch.opciones) {
          for (final brillo in Brightness.values) {
            final contador = AppColorSet.of(
              swatch,
              brillo,
            ).contadorSobrePrimary;
            final ratio = _contraste(contador.texto, contador.fondo);

            // 4.5:1 = AA para texto normal. El contador es pequeño (11 px), así
            // que se exige el umbral estricto y no el 3:1 de texto grande.
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '${swatch.id} $brillo: el número del badge da '
                  '${ratio.toStringAsFixed(2)}:1 sobre su fondo',
            );
          }
        }
      },
    );

    test('el badge se despega de la barra que lo lleva debajo', () {
      // Este es el bug que motivó el cambio: el badge iba en `colors.primary`,
      // el MISMO color de la barra de navegación y del header — 1.00:1, un
      // contador literalmente invisible.
      for (final swatch in AccentSwatch.opciones) {
        for (final brillo in Brightness.values) {
          final set = AppColorSet.of(swatch, brillo);
          final ratio = _contraste(set.contadorSobrePrimary.fondo, set.primary);

          // 3:1 es el mínimo de WCAG para componentes gráficos no textuales:
          // el badge es una forma, lo que tiene que distinguirse es su silueta
          // contra la barra.
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                '${swatch.id} $brillo: el badge da '
                '${ratio.toStringAsFixed(2)}:1 contra la barra',
          );
        }
      }
    });

    test('en los seis pasteles el contador SÍ es la inversión del tema', () {
      // La regla que pidió el diseño: interfaz clara -> contador oscuro. Se
      // cumple literalmente donde la barra sigue al tema; navy y wine quedan
      // fuera a propósito porque su relleno es oscuro en ambos temas.
      final pasteles = AccentSwatch.opciones.where(
        (s) => s.id != 'navy' && s.id != 'wine',
      );
      for (final swatch in pasteles) {
        for (final brillo in Brightness.values) {
          final set = AppColorSet.of(swatch, brillo);
          expect(
            set.contadorSobrePrimary.fondo,
            set.inverted.accentTint,
            reason: '${swatch.id} $brillo debería usar la paleta contraria',
          );
        }
      }
    });

    test('navy y wine no se invierten a ciegas: la barra manda', () {
      // Con navy en tema CLARO la barra ya es oscura; invertir el tema daría
      // un badge oscuro sobre barra oscura (1.07:1). El fondo tiene que salir
      // de la paleta clara, o sea la MISMA del tema activo.
      for (final id in ['navy', 'wine']) {
        final swatch = AccentSwatch.opciones.firstWhere((s) => s.id == id);
        final claro = AppColorSet.of(swatch, Brightness.light);
        expect(
          claro.contadorSobrePrimary.fondo,
          claro.accentTint,
          reason: '$id en claro no debe tomar la paleta oscura',
        );
      }
    });

    test('copyWith conserva swatch y brightness si no se pasan', () {
      final set = AppColorSet.of(AccentSwatch.defecto, Brightness.light);
      final copia = set.copyWith(ink: const Color(0xFF000000));

      expect(copia.swatch, set.swatch);
      expect(copia.brightness, set.brightness);
      expect(copia.inverted.primary, set.inverted.primary);
    });

    test('lerp deja campos discretos utilizables en los extremos', () {
      final claro = AppColorSet.of(AccentSwatch.defecto, Brightness.light);
      final oscuro = AppColorSet.of(AccentSwatch.defecto, Brightness.dark);

      expect(claro.lerp(oscuro, 0).brightness, Brightness.light);
      expect(claro.lerp(oscuro, 1).brightness, Brightness.dark);
    });
  });
}
