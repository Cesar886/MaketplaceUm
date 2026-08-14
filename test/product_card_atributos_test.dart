// Los badges de atributos entran en una tarjeta de ALTO ACOTADO: la
// cuadrícula del home usa childAspectRatio fijo y los resultados de búsqueda
// envuelven cada tarjeta en un SizedBox(height: 118). Ahí no existe "queda
// apretado": lo que no cabe desborda y raya la pantalla de amarillo.
//
// Este archivo reproduce las tres geometrías reales donde vive ProductCard y
// falla si alguna desborda. Si mañana alguien agrega otra línea a la tarjeta,
// se entera aquí y no en una captura de pantalla de un usuario.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/product_card.dart';

void main() {
  /// Pinta [widget] y devuelve los desbordes VERTICALES que haya provocado.
  ///
  /// Solo el eje vertical, y no por comodidad: el alto de la tarjeta es fijo
  /// (childAspectRatio en la cuadrícula, SizedBox(height: 118) en búsqueda) y
  /// no tiene a dónde ceder, mientras que el ancho ya está protegido por el
  /// `Expanded` de la fila inferior.
  ///
  /// El ancho además no es medible aquí: el entorno de prueba no carga
  /// Google Fonts y cae en una tipografía de respaldo mucho más ancha —el
  /// badge "Disponible" mide 123 px en test contra ~62 reales—, así que
  /// exigir el eje horizontal reportaría desbordes que no existen en la app.
  /// La contraparte es que estas medidas de alto son conservadoras: si el
  /// contenido cabe con la fuente de prueba, cabe con la real.
  Future<List<String>> desbordesVerticalesAlPintar(
    WidgetTester tester,
    Widget widget,
  ) async {
    final errores = <String>[];
    final anterior = FlutterError.onError;
    FlutterError.onError = (detalles) => errores.add(detalles.toString());
    try {
      await tester.pumpWidget(widget);
    } finally {
      FlutterError.onError = anterior;
    }
    tester.takeException();
    return errores.where((e) => e.contains('on the bottom')).toList();
  }

  /// Un producto de ropa con las dos respuestas que el servidor destaca
  /// (talla y estado), que es el caso de badge más largo del catálogo.
  Product productoConBadges({int cuantos = 2}) {
    return Product.fromJson({
      'id': 'p_1',
      'title': 'Sudadera Champion talla grande casi nueva',
      'price': 350,
      'description': 'Poco uso, sin manchas ni detalles, la vendo por mudanza',
      'publishedAgo': 'hace 2 días',
      'seller': 's_1',
      'categoryObj': {'id': 'clothes', 'name': 'Ropa', 'emoji': '👕'},
      'images': <String>[],
      'extras': <dynamic>[],
      'views': 128,
      'atributos': {'talla': 'M', 'estado_ropa': 'Poco uso'},
      'atributosDestacados': [
        {'key': 'talla', 'label': 'Talla', 'value': 'M'},
        if (cuantos > 1)
          {'key': 'estado_ropa', 'label': 'Estado', 'value': 'Poco uso'},
      ],
    });
  }

  Product productoSinBadges() {
    return Product.fromJson({
      'id': 'p_2',
      'title': 'Sudadera Champion talla grande casi nueva',
      'price': 350,
      'description': 'Poco uso, sin manchas ni detalles, la vendo por mudanza',
      'publishedAgo': 'hace 2 días',
      'seller': 's_1',
      'categoryObj': {'id': 'clothes', 'name': 'Ropa', 'emoji': '👕'},
      'images': <String>[],
      'extras': <dynamic>[],
      'views': 128,
    });
  }

  Widget envolver(Widget child, {Size size = const Size(390, 844)}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
  }

  /// Reproduce la celda de la cuadrícula del home/perfil de vendedor: mismo
  /// padding lateral, mismo espaciado y mismo childAspectRatio que
  /// `home_screen.dart`.
  Widget celdaDeCuadricula(
    Product product, {
    required int columnas,
    double anchoPantalla = 390.0,
  }) {
    const paddingLateral = 18.0 * 2;
    const espaciado = 12.0;
    final anchoCelda =
        (anchoPantalla - paddingLateral - espaciado * (columnas - 1)) / columnas;
    final aspecto = columnas == 3 ? 0.72 : 0.64;

    return Center(
      child: SizedBox(
        width: anchoCelda,
        height: anchoCelda / aspecto,
        child: ProductCard(product: product, heroEnabled: false),
      ),
    );
  }

  /// Reproduce un resultado de búsqueda: tarjeta horizontal dentro del
  /// SizedBox(height: 118) de `search_screen.dart`.
  Widget filaDeBusqueda(Product product) {
    return SizedBox(
      height: 118,
      child: ProductCard(
        product: product,
        horizontal: true,
        heroEnabled: false,
      ),
    );
  }

  group('ProductCard con badges de atributos no desborda', () {
    testWidgets('en la cuadrícula de 2 columnas', (tester) async {
      final desbordes = await desbordesVerticalesAlPintar(
        tester,
        envolver(celdaDeCuadricula(productoConBadges(), columnas: 2)),
      );
      expect(desbordes, isEmpty, reason: desbordes.join('\n'));
    });

    testWidgets('en la cuadrícula de 3 columnas (tablet)', (tester) async {
      final desbordes = await desbordesVerticalesAlPintar(
        tester,
        envolver(
          celdaDeCuadricula(
            productoConBadges(),
            columnas: 3,
            anchoPantalla: 800,
          ),
          size: const Size(800, 1200),
        ),
      );
      expect(desbordes, isEmpty, reason: desbordes.join('\n'));
    });

    testWidgets('en un resultado de búsqueda (tarjeta horizontal)', (
      tester,
    ) async {
      final desbordes = await desbordesVerticalesAlPintar(
        tester,
        envolver(filaDeBusqueda(productoConBadges())),
      );
      expect(desbordes, isEmpty, reason: desbordes.join('\n'));
    });

    testWidgets('con textos de badge largos', (tester) async {
      // El peor caso del catálogo: "Con detalles/subrayado" en libros y
      // "Entrega a domicilio" en comida.
      final producto = Product.fromJson({
        'id': 'p_3',
        'title': 'Cálculo de una variable, Stewart, octava edición',
        'price': 450,
        'description': 'Con algunas anotaciones a lápiz en los primeros temas',
        'publishedAgo': 'hace 2 días',
        'seller': 's_1',
        'categoryObj': {'id': 'books', 'name': 'Libros', 'emoji': '📚'},
        'images': <String>[],
        'extras': <dynamic>[],
        'atributosDestacados': [
          {
            'key': 'estado_libro',
            'label': 'Estado',
            'value': 'Con detalles/subrayado',
          },
          {'key': 'edicion', 'label': 'Edición', 'value': 'Copia/Fotocopia'},
        ],
      });

      final enCuadricula = await desbordesVerticalesAlPintar(
        tester,
        envolver(celdaDeCuadricula(producto, columnas: 2)),
      );
      expect(enCuadricula, isEmpty, reason: enCuadricula.join('\n'));

      final enBusqueda = await desbordesVerticalesAlPintar(
        tester,
        envolver(filaDeBusqueda(producto)),
      );
      expect(enBusqueda, isEmpty, reason: enBusqueda.join('\n'));
    });

    testWidgets('con un solo badge', (tester) async {
      final desbordes = await desbordesVerticalesAlPintar(
        tester,
        envolver(celdaDeCuadricula(productoConBadges(cuantos: 1), columnas: 2)),
      );
      expect(desbordes, isEmpty, reason: desbordes.join('\n'));
    });
  });

  group('ProductCard sin badges sigue igual', () {
    testWidgets('no desborda en la cuadrícula', (tester) async {
      final desbordes = await desbordesVerticalesAlPintar(
        tester,
        envolver(celdaDeCuadricula(productoSinBadges(), columnas: 2)),
      );
      expect(desbordes, isEmpty, reason: desbordes.join('\n'));
    });

    testWidgets('conserva la descripción cuando no hay atributos', (
      tester,
    ) async {
      // La descripción solo cede su lugar a los badges; un producto sin
      // responder nada no debe perder nada.
      await desbordesVerticalesAlPintar(
        tester,
        envolver(celdaDeCuadricula(productoSinBadges(), columnas: 2)),
      );
      expect(
        find.textContaining('Poco uso, sin manchas'),
        findsOneWidget,
      );
    });
  });

  testWidgets('los badges se pintan con el valor que mandó el servidor', (
    tester,
  ) async {
    await desbordesVerticalesAlPintar(
      tester,
      envolver(celdaDeCuadricula(productoConBadges(), columnas: 2)),
    );
    expect(find.text('M'), findsOneWidget);
    expect(find.text('Poco uso'), findsOneWidget);
  });
}
