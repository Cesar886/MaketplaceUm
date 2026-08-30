// El logo del home abre el menú de categorías.
//
// Antes el logo era decoración: un `AppLogo` dentro de un `Expanded`, sin
// gesto. Ahora es el disparador de un overlay anclado a la esquina con todas
// las categorías del marketplace.
//
// Lo que se protege aquí es el contrato del widget, no su pintura: que el
// menú nazca cerrado, que el tap lo abra con TODAS las categorías que se le
// pasan (nunca una lista propia), que elegir una avise al padre con el id y
// cierre, y que se pueda cerrar sin elegir nada. La lista de categorías entra
// por parámetro justamente para que el home siga siendo el único dueño de
// esos datos.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/config/locales.dart';
import 'package:mercadito_um/mock_data.dart';
import 'package:mercadito_um/widgets/category_logo_menu.dart';

import 'helpers/localizacion_de_prueba.dart';

void main() {
  setUpAll(() => inicializarTraducciones(locale: AppLocales.es));

  String? elegida;
  var vecesLimpiado = 0;

  setUp(() {
    elegida = null;
    vecesLimpiado = 0;
  });

  Widget montar({
    String? seleccionada,
    Brightness brillo = Brightness.light,
  }) {
    return MaterialApp(
      theme: brillo == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(
        // El menú se ancla al logo, así que el logo va donde va en el home:
        // arriba a la izquierda, no centrado en la pantalla.
        body: Align(
          alignment: Alignment.topLeft,
          child: CategoryLogoMenu(
            categories: mockCategories,
            selectedCategoryId: seleccionada,
            onCategorySelected: (id) => elegida = id,
            onClearCategory: () => vecesLimpiado++,
          ),
        ),
      ),
    );
  }

  /// Toca donde está el logo.
  ///
  /// `tapAt` y no `tap` a propósito: con el menú ya abierto, el velo cubre la
  /// pantalla entera y se lleva el toque — que es justo el comportamiento
  /// esperado (tocar el logo abierto lo cierra). `tap` avisaría de un "hit
  /// test missed" en ese caso; lo que se prueba es la coordenada, no qué
  /// widget queda encima.
  Future<void> tocarLogo(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(find.byType(CategoryLogoMenu)));
    await tester.pumpAndSettle();
  }

  testWidgets('nace cerrado: ninguna categoría a la vista', (tester) async {
    await tester.pumpWidget(montar());
    await tester.pumpAndSettle();

    expect(find.text('Libros'), findsNothing);
    expect(find.text('Electrónicos'), findsNothing);
  });

  testWidgets('tocar el logo despliega TODAS las categorías recibidas', (
    tester,
  ) async {
    await tester.pumpWidget(montar());
    await tocarLogo(tester);

    for (final categoria in mockCategories) {
      expect(
        find.text(categoria.name),
        findsOneWidget,
        reason: 'falta ${categoria.name} en el menú',
      );
    }
  });

  testWidgets('elegir una categoría avisa con su id y cierra el menú', (
    tester,
  ) async {
    await tester.pumpWidget(montar());
    await tocarLogo(tester);

    await tester.tap(find.text('Electrónicos'));
    await tester.pumpAndSettle();

    expect(elegida, 'electronics');
    expect(find.text('Libros'), findsNothing);
  });

  testWidgets('tocar fuera cierra sin elegir nada', (tester) async {
    await tester.pumpWidget(montar());
    await tocarLogo(tester);

    // Esquina inferior derecha: fuera del panel, sobre el velo.
    await tester.tapAt(const Offset(700, 550));
    await tester.pumpAndSettle();

    expect(find.text('Libros'), findsNothing);
    expect(elegida, isNull);
  });

  testWidgets('volver a tocar el logo cierra el menú', (tester) async {
    await tester.pumpWidget(montar());
    await tocarLogo(tester);
    expect(find.text('Libros'), findsOneWidget);

    await tocarLogo(tester);

    expect(find.text('Libros'), findsNothing);
    expect(elegida, isNull);
  });

  testWidgets('sin filtro activo no ofrece quitar el filtro', (tester) async {
    await tester.pumpWidget(montar());
    await tocarLogo(tester);

    expect(find.text('Ver todo el mercadito'), findsNothing);
  });

  testWidgets('con filtro activo, quitar el filtro avisa y cierra', (
    tester,
  ) async {
    await tester.pumpWidget(montar(seleccionada: 'books'));
    await tocarLogo(tester);

    await tester.tap(find.text('Ver todo el mercadito'));
    await tester.pumpAndSettle();

    expect(vecesLimpiado, 1);
    expect(find.text('Libros'), findsNothing);
  });

  testWidgets('en modo oscuro también despliega las categorías', (
    tester,
  ) async {
    await tester.pumpWidget(montar(brillo: Brightness.dark));
    await tocarLogo(tester);

    expect(find.text('Libros'), findsOneWidget);
  });
}
