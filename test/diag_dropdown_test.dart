// DIAGNÓSTICO TEMPORAL — no es parte de la suite. Reproduce el estado en que
// queda el selector de categoría de WantedPostScreen cuando getCategories()
// falla y el `catch (_)` de _loadCategories lo deja con la lista vacía.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mercadito_um/app_theme.dart';

Widget _pantalla({
  required List<String> categorias,
  required String? seleccion,
  required ValueChanged<String?> onChanged,
  ThemeData? tema,
}) {
  return MaterialApp(
    theme: tema,
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: seleccion,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: [
              for (final c in categorias)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('DIAG: con lista vacía el campo se pinta pero no abre menú', (
    tester,
  ) async {
    String? elegido;
    await tester.pumpWidget(
      _pantalla(
        categorias: const [],
        seleccion: null,
        onChanged: (v) => elegido = v,
      ),
    );

    // El label se ve: el usuario SÍ ve un campo "Categoría".
    expect(find.text('Categoría'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    debugPrint('DIAG lista vacía -> elegido=$elegido');
    debugPrint(
      'DIAG lista vacía -> items de menú abiertos: '
      '${find.byType(DropdownMenuItem<String>).evaluate().length}',
    );
  });

  testWidgets('DIAG: con 8 categorías el menú abre y se puede elegir', (
    tester,
  ) async {
    String? elegido;
    await tester.pumpWidget(
      _pantalla(
        categorias: const [
          'Libros',
          'Ropa',
          'Electrónicos',
          'Comida',
          'Hospedaje',
          'Apuntes',
          'Otros',
          'Servicios',
        ],
        seleccion: 'Libros',
        onChanged: (v) => elegido = v,
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    debugPrint(
      'DIAG 8 items -> opciones visibles tras el tap: '
      '${find.text('Ropa').evaluate().length}',
    );

    await tester.tap(find.text('Ropa').last);
    await tester.pumpAndSettle();

    debugPrint('DIAG 8 items -> elegido=$elegido');
  });

  for (final nombre in <String>['CLARO', 'OSCURO']) {
    testWidgets('DIAG: con el tema real $nombre el menú abre y se elige', (
      tester,
    ) async {
      // Se construye DENTRO del test: AppTheme llama a GoogleFonts, que
      // necesita estar en la zona de test para no salir a la red.
      final tema = nombre == 'CLARO' ? AppTheme.light() : AppTheme.dark();
      String? elegido;
      await tester.pumpWidget(
        _pantalla(
          tema: tema,
          categorias: const ['Libros', 'Ropa', 'Comida'],
          seleccion: 'Libros',
          onChanged: (v) => elegido = v,
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      debugPrint(
        'DIAG tema $nombre -> "Ropa" visible tras tap: '
        '${find.text('Ropa').evaluate().length}',
      );

      await tester.tap(find.text('Ropa').last);
      await tester.pumpAndSettle();
      debugPrint('DIAG tema $nombre -> elegido=$elegido');
    });
  }
}
