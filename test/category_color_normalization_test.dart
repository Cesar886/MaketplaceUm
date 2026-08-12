import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final alta = la > lb ? la : lb;
  final baja = la > lb ? lb : la;
  return (alta + 0.05) / (baja + 0.05);
}

void main() {
  // Los ocho colores tal como los sirve /api/categories.
  const categorias = <String, Color>{
    'Libros': Color(0xFF2A6FBB),
    'Ropa': Color(0xFF9B5DE5),
    'Electronicos': Color(0xFF1B998B),
    'Comida': Color(0xFFE86F2C),
    'Hospedaje': Color(0xFF6A994E),
    'Apuntes': Color(0xFFD97706),
    'Otros': Color(0xFF607D8B),
    'Servicios': Color(0xFFE76F51),
  };

  test('ninguna categoria se ve mas apagada que otra (claro)', () {
    final ratios = <double>[];
    for (final entry in categorias.entries) {
      final c = normalizeCategoryColor(entry.value, Brightness.light);
      final ratio = _contraste(c, AppColors.surface);
      ratios.add(ratio);
      // ignore: avoid_print
      print(
        '${entry.key.padRight(14)} ${entry.value.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
        ' -> ${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
        '  ${ratio.toStringAsFixed(2)}:1',
      );
      expect(ratio, greaterThan(4.5), reason: entry.key);
    }
    ratios.sort();
    final dispersion = ratios.last / ratios.first;
    // ignore: avoid_print
    print('dispersion claro: ${dispersion.toStringAsFixed(2)}x');
    expect(dispersion, lessThan(1.05));
  });

  test('ninguna categoria se ve mas apagada que otra (oscuro)', () {
    final ratios = <double>[];
    for (final entry in categorias.entries) {
      final c = normalizeCategoryColor(entry.value, Brightness.dark);
      final ratio = _contraste(c, AppColors.darkSurface);
      ratios.add(ratio);
      // ignore: avoid_print
      print(
        '${entry.key.padRight(14)} -> '
        '${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
        '  ${ratio.toStringAsFixed(2)}:1',
      );
      expect(ratio, greaterThan(4.8), reason: entry.key);
    }
    ratios.sort();
    final dispersion = ratios.last / ratios.first;
    // ignore: avoid_print
    print('dispersion oscuro: ${dispersion.toStringAsFixed(2)}x');
    expect(dispersion, lessThan(1.05));
  });

  test('se conserva el matiz del backend y se capa la saturacion a 55%', () {
    for (final entry in categorias.entries) {
      final original = HSLColor.fromColor(entry.value);
      for (final brillo in Brightness.values) {
        final normalizado = HSLColor.fromColor(
          normalizeCategoryColor(entry.value, brillo),
        );
        expect(
          normalizado.hue,
          closeTo(original.hue, 1.0),
          reason: '${entry.key} cambio de matiz',
        );
        // El techo es 0.55; la holgura cubre el redondeo a 8 bits del
        // round-trip HSL -> Color -> HSL (0.55 aterriza en 0.5510204).
        expect(
          normalizado.saturation,
          lessThanOrEqualTo(0.56),
          reason: '${entry.key} excede el techo de saturacion',
        );
      }
    }
  });

  test('el + de publicar contrasta contra su barra en los ocho swatches', () {
    for (final swatch in AccentSwatch.opciones) {
      for (final brillo in Brightness.values) {
        final c = AppColorSet.of(swatch, brillo);
        // barra = c.primary, relleno del FAB = c.onPrimary, glifo = c.primary
        final fabVsBarra = _contraste(c.onPrimary, c.primary);
        // ignore: avoid_print
        print(
          '${swatch.id.padRight(12)} ${brillo.name.padRight(5)} '
          'FAB vs barra ${fabVsBarra.toStringAsFixed(2)}:1',
        );
        expect(fabVsBarra, greaterThan(4.5), reason: '${swatch.id}/$brillo');
      }
    }
  });
}
