// Opción B: el logo abre un panel lateral con todas las categorías.
//
// Se protege el mismo contrato que el dropdown —todas las categorías que se
// le pasan, avisar con el id y cerrar, poder salir sin elegir— más lo que es
// propio del panel: el botón de cerrar, el conteo por categoría y que el
// conteo desaparezca en vez de mentir con ceros cuando el feed no cargó.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/config/locales.dart';
import 'package:mercadito_um/mock_data.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/providers/theme_provider.dart';
import 'package:mercadito_um/widgets/category_logo_menu.dart';

import 'helpers/localizacion_de_prueba.dart';

void main() {
  setUpAll(() => inicializarTraducciones(locale: AppLocales.es));

  String? elegida;
  var vecesLimpiado = 0;

  setUp(() {
    elegida = null;
    vecesLimpiado = 0;
    // El bloque "Cuenta y ajustes" del panel lee AuthProvider/ThemeProvider
    // (context.watch), y ThemeProvider persiste su preferencia con
    // SharedPreferences — sin el mock inicial revienta al construirse.
    SharedPreferences.setMockInitialValues({});
  });

  Widget montar({
    String? seleccionada,
    Brightness brillo = Brightness.light,
    int? Function(String)? conteos,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        theme: brillo == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: CategoryLogoMenu(
              style: CategoryMenuStyle.sidebar,
              categories: mockCategories,
              selectedCategoryId: seleccionada,
              countFor: conteos,
              onCategorySelected: (id) => elegida = id,
              onClearCategory: () => vecesLimpiado++,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tocarLogo(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(find.byType(CategoryLogoMenu)));
    await tester.pumpAndSettle();
  }

  /// Desplaza el panel hasta que el finder aparezca.
  ///
  /// El bloque "Cuenta y ajustes" ahora va ARRIBA de las categorías, así que
  /// una fila de categoría típica ya no está a la vista apenas se abre el
  /// panel — antes sí, cuando el panel solo tenía categorías.
  Future<void> desplazarHasta(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      80,
      scrollable: find.byType(Scrollable).last,
    );
    // `scrollUntilVisible` para en cuanto el finder entra al viewport, pero
    // puede dejarlo pegado al borde inferior —fuera del área que de verdad
    // recibe toques—. `ensureVisible` lo termina de acomodar.
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('nace cerrado: ninguna categoría a la vista', (tester) async {
    await tester.pumpWidget(montar());
    await tester.pumpAndSettle();

    expect(find.text('Libros'), findsNothing);
  });

  testWidgets('tocar el logo abre el panel con TODAS las categorías', (
    tester,
  ) async {
    await tester.pumpWidget(montar());
    await tocarLogo(tester);

    // Se busca desplazándose: el panel es una lista alta —encabezado de
    // marca más filas de 60 con ícono, conteo y estado— y en la pantalla de
    // prueba (600 de alto) las últimas categorías caen bajo el pliegue, igual
    // que en un teléfono corto. Lo que se protege es que estén TODAS las que
    // se le pasaron, no que quepan sin rodar el dedo.
    for (final categoria in mockCategories) {
      await tester.scrollUntilVisible(
        find.text(categoria.name),
        80,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.text(categoria.name),
        findsOneWidget,
        reason: 'falta ${categoria.name} en el panel',
      );
    }
  });

  testWidgets('elegir una categoría avisa con su id y cierra', (tester) async {
    await tester.pumpWidget(montar());
    await tocarLogo(tester);

    await desplazarHasta(tester, find.text('Electrónicos'));
    await tester.tap(find.text('Electrónicos'));
    await tester.pumpAndSettle();

    expect(elegida, 'electronics');
    expect(find.text('Libros'), findsNothing);
  });

  testWidgets('el botón de cerrar cierra sin elegir nada', (tester) async {
    await tester.pumpWidget(montar());
    await tocarLogo(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Libros'), findsNothing);
    expect(elegida, isNull);
  });

  testWidgets('tocar fuera del panel cierra sin elegir nada', (tester) async {
    await tester.pumpWidget(montar());
    await tocarLogo(tester);

    // Borde derecho: fuera del panel (máx. 340 de ancho), sobre el velo.
    await tester.tapAt(const Offset(760, 300));
    await tester.pumpAndSettle();

    expect(find.text('Libros'), findsNothing);
    expect(elegida, isNull);
  });

  testWidgets('arrastrar hacia la izquierda cierra el panel', (tester) async {
    await tester.pumpWidget(montar());
    await tocarLogo(tester);

    // El gesto de cerrar arrastra el panel entero, no una fila puntual: se
    // dispara desde el ícono de cerrar del encabezado, que —a diferencia de
    // una categoría— siempre está a la vista sin importar cuánto se haya
    // desplazado la lista de abajo.
    await tester.fling(
      find.byIcon(Icons.close_rounded),
      const Offset(-300, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(find.text('Libros'), findsNothing);
    expect(elegida, isNull);
  });

  testWidgets('muestra el conteo de publicaciones por categoría', (
    tester,
  ) async {
    await tester.pumpWidget(montar(conteos: (id) => id == 'books' ? 7 : 3));
    await tocarLogo(tester);

    await desplazarHasta(tester, find.text('7'));
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('sin conteos disponibles no pinta ningún número', (tester) async {
    await tester.pumpWidget(montar(conteos: (_) => null));
    await tocarLogo(tester);

    expect(find.text('0'), findsNothing);
    await desplazarHasta(tester, find.text('Libros'));
    expect(find.text('Libros'), findsOneWidget);
  });

  testWidgets('con filtro activo, quitar el filtro avisa y cierra', (
    tester,
  ) async {
    await tester.pumpWidget(montar(seleccionada: 'books'));
    await tocarLogo(tester);

    await desplazarHasta(tester, find.text('Ver todo el mercadito'));
    await tester.tap(find.text('Ver todo el mercadito'));
    await tester.pumpAndSettle();

    expect(vecesLimpiado, 1);
    expect(find.text('Libros'), findsNothing);
  });

  testWidgets('en modo oscuro también abre el panel', (tester) async {
    await tester.pumpWidget(montar(brillo: Brightness.dark));
    await tocarLogo(tester);

    await desplazarHasta(tester, find.text('Libros'));
    expect(find.text('Libros'), findsOneWidget);
  });
}
