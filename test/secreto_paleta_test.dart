// La paleta del enigma sigue el modo oscuro/claro que el usuario ya eligió
// para el resto de la app — no lee su propia preferencia.
//
// Lo que se protege: `SecretoPalette.of` lee `Theme.of(context).brightness`,
// que es exactamente lo que `MaterialApp.themeMode` (armado desde
// `ThemeProvider` en main.dart) ya decide para toda la app. Si esto se
// desconecta, el enigma se queda "atorado" en un modo fijo aunque el usuario
// cambie el interruptor en Ajustes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/screens/secreto/secreto_theme.dart';

void main() {
  Future<SecretoPalette> montarYLeer(
    WidgetTester tester,
    Brightness brillo,
  ) async {
    late SecretoPalette leida;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brillo),
        home: Builder(
          builder: (context) {
            leida = SecretoPalette.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return leida;
  }

  testWidgets('en modo oscuro usa la paleta de medianoche', (tester) async {
    final p = await montarYLeer(tester, Brightness.dark);

    expect(p.esOscuro, isTrue);
    expect(p.fondo, const Color(0xFF0B111C));
  });

  testWidgets('en modo claro usa la paleta de pergamino', (tester) async {
    final p = await montarYLeer(tester, Brightness.light);

    expect(p.esOscuro, isFalse);
    expect(p.fondo, const Color(0xFFF7F1E3));
    expect(
      p.fondo,
      isNot(const Color(0xFF0B111C)),
      reason: 'el modo claro no puede pintar la medianoche',
    );
  });

  testWidgets('el texto siempre contrasta contra su propio fondo', (
    tester,
  ) async {
    for (final brillo in Brightness.values) {
      final p = await montarYLeer(tester, brillo);
      final contraste =
          (p.tinta.computeLuminance() - p.fondo.computeLuminance()).abs();
      expect(
        contraste,
        greaterThan(0.4),
        reason: 'poco contraste en ${brillo.name}: se leería mal',
      );
    }
  });

  testWidgets('las motas se ven sobre su propio fondo en los dos modos', (
    tester,
  ) async {
    for (final brillo in Brightness.values) {
      final p = await montarYLeer(tester, brillo);
      expect(
        (p.mota.computeLuminance() - p.fondo.computeLuminance()).abs(),
        greaterThan(0.15),
        reason: 'la mota se perdería contra el fondo en ${brillo.name}',
      );
    }
  });
}
