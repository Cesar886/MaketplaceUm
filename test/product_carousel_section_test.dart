// Tests del carrusel de publicaciones del detalle ("También te puede
// interesar" y "Más de este vendedor").
//
// Lo que se protege:
//
//  1. Que una sección sin nada que mostrar desaparezca ENTERA — ni
//     encabezado ni hueco. Es el requisito con el que se pidió la sección, y
//     el error opuesto (dejar 40 px de aire en medio del detalle) no rompe
//     ningún test de lógica.
//  2. Que la tarjeta sea la misma [ProductCard] del home. Si alguien la
//     sustituyera por una variante local, el detalle empezaría a divergir
//     del feed sin que nada fallara.
//  3. Que la tarjeta vaya en modo ligero ([ProductCard.dense]): sin
//     descripción ni vistas. Es lo que permite que sea más chica sin
//     apretarse, así que si alguien quitara el flag, la fila desbordaría en
//     vez de verse mal a secas.
//  4. Que no desborde a ningún ancho, ni suelta ni dentro de la tarjeta del
//     vendedor. Por eso hay un mínimo de ancho de tarjeta: en pantallas
//     angostas se muestran menos, no más apretadas.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/product_card.dart';
import 'package:mercadito_um/widgets/product_card_skeleton.dart';
import 'package:mercadito_um/widgets/product_carousel_section.dart';
import 'package:mercadito_um/widgets/views_counter.dart';

void main() {
  Product producto(String id, {String title = 'Calculadora científica'}) {
    return Product(
      id: id,
      title: title,
      price: 450,
      category: const MarketplaceCategory(
        id: 'c_1',
        name: 'Libros',
        emoji: '📚',
        icon: Icons.menu_book_rounded,
        color: Color(0xFF3F51B5),
      ),
      description: 'Poco uso, funciona bien.',
      publishedAgo: 'hace 2 días',
      seller: const Seller(
        id: 's_1',
        name: 'Mariana Peña',
        avatarInitials: 'MP',
        major: 'Estudiante',
        rating: 4.5,
        reviews: 12,
        verified: true,
      ),
      imageIcon: Icons.menu_book_rounded,
      imageColor: const Color(0xFF3F51B5),
    );
  }

  List<Product> productos(int cuantos) =>
      List.generate(cuantos, (i) => producto('p_$i', title: 'Producto $i'));

  /// Monta la sección con el tema real y el mismo padding lateral que usa el
  /// detalle (18 px), a un ancho concreto.
  Future<void> montar(
    WidgetTester tester,
    Widget child, {
    double ancho = 390,
  }) async {
    tester.view.physicalSize = Size(ancho, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: child,
            ),
          ),
        ),
      ),
    );
    // No pumpAndSettle: el esqueleto de carga tiene un shimmer en bucle y
    // nunca queda quieto. 200 ms alcanzan de sobra para la entrada de la
    // fila (110 ms).
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester.takeException(),
      isNull,
      reason: 'la fila no debe desbordar a este ancho',
    );
  }

  testWidgets('sin productos y sin carga, la sección no ocupa nada', (
    tester,
  ) async {
    await montar(
      tester,
      ProductCarouselSection(
        title: 'También te puede interesar',
        products: const [],
        onProductTap: (_) {},
      ),
    );

    expect(find.text('También te puede interesar'), findsNothing);
    expect(find.byType(ProductCard), findsNothing);
    expect(
      tester.getSize(find.byType(ProductCarouselSection)).height,
      0,
      reason: 'una sección vacía no debe dejar hueco en el detalle',
    );
  });

  testWidgets('con productos pinta el encabezado y una ProductCard por uno', (
    tester,
  ) async {
    await montar(
      tester,
      ProductCarouselSection(
        title: 'También te puede interesar',
        products: productos(4),
        onProductTap: (_) {},
      ),
    );

    expect(find.text('También te puede interesar'), findsOneWidget);
    // La lista es horizontal y perezosa: no exige que las 4 estén montadas,
    // sí que las visibles sean ProductCard del home y no otra cosa.
    expect(find.byType(ProductCard), findsWidgets);
    expect(find.byType(ProductCardSkeleton), findsNothing);
  });

  testWidgets('la tarjeta va en modo ligero: sin descripción ni vistas', (
    tester,
  ) async {
    await montar(
      tester,
      ProductCarouselSection(
        title: 'También te puede interesar',
        products: [producto('p_0', title: 'Calculadora')],
        onProductTap: (_) {},
      ),
    );

    expect(
      tester.widget<ProductCard>(find.byType(ProductCard).first).dense,
      isTrue,
    );
    expect(find.text('Poco uso, funciona bien.'), findsNothing);
    expect(find.byType(ViewsCounter), findsNothing);
    // El precio y el nombre sí se quedan: son lo que decide si vale la pena
    // tocar la tarjeta.
    expect(find.text('Calculadora'), findsOneWidget);
  });

  testWidgets('la tarjeta es más chica que la del grid del home', (
    tester,
  ) async {
    // El grid del feed a 390 px pinta tarjetas de (354 - 12) / 2 = 171. Aquí
    // deben salir más angostas — es el ajuste que se pidió — pero nunca por
    // debajo del mínimo con el que la tarjeta ligera respira.
    await montar(
      tester,
      ProductCarouselSection(
        title: 'También te puede interesar',
        products: productos(4),
        onProductTap: (_) {},
      ),
    );

    final ancho = tester.getSize(find.byType(ProductCard).first).width;
    expect(ancho, lessThan(171));
    expect(ancho, greaterThanOrEqualTo(148));
  });

  testWidgets('en pantalla angosta se muestran menos, no más apretadas', (
    tester,
  ) async {
    await montar(
      tester,
      ProductCarouselSection(
        title: 'También te puede interesar',
        products: productos(4),
        onProductTap: (_) {},
      ),
      ancho: 320,
    );

    // A 320 px el reparto natural daría ~118 px por tarjeta, ancho al que el
    // título se parte y el pie ya no cabe. El mínimo manda.
    expect(
      tester.getSize(find.byType(ProductCard).first).width,
      greaterThanOrEqualTo(148),
    );
  });

  testWidgets('tocar una tarjeta avisa con ese producto', (tester) async {
    Product? tocado;
    await montar(
      tester,
      ProductCarouselSection(
        title: 'También te puede interesar',
        products: productos(3),
        onProductTap: (p) => tocado = p,
      ),
    );

    await tester.tap(find.byType(ProductCard).first);
    await tester.pump();

    expect(tocado?.id, 'p_0');
  });

  testWidgets('mientras carga muestra esqueletos, no tarjetas vacías', (
    tester,
  ) async {
    await montar(
      tester,
      ProductCarouselSection(
        title: 'También te puede interesar',
        products: const [],
        loading: true,
        onProductTap: (_) {},
      ),
    );

    expect(find.text('También te puede interesar'), findsOneWidget);
    expect(find.byType(ProductCardSkeleton), findsWidgets);
    expect(find.byType(ProductCard), findsNothing);
  });

  testWidgets('la fila se arma igual en pantalla angosta y en ancha', (
    tester,
  ) async {
    for (final ancho in [320.0, 430.0]) {
      await montar(
        tester,
        ProductCarouselSection(
          title: 'Más de Mariana Peña',
          products: productos(5),
          onProductTap: (_) {},
        ),
        ancho: ancho,
      );

      expect(find.text('Más de Mariana Peña'), findsOneWidget);
      expect(find.byType(ProductCard), findsWidgets);
    }
  });

  testWidgets('el bleed no descuadra la primera tarjeta', (tester) async {
    // Con bleed la fila se pinta más ancha que su hueco para que las
    // tarjetas asomen por el borde; si el padding que lo compensa faltara,
    // la primera quedaría pegada al canto de la pantalla.
    await montar(
      tester,
      ProductCarouselSection(
        title: 'También te puede interesar',
        products: productos(4),
        onProductTap: (_) {},
        bleed: 18,
      ),
    );

    final primera = tester.getTopLeft(find.byType(ProductCard).first);
    expect(primera.dx, closeTo(18, 0.5), reason: 'debe alinear con el texto');
  });

  testWidgets('la variante compacta también cabe dentro de otra tarjeta', (
    tester,
  ) async {
    await montar(
      tester,
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
        color: const Color(0xFFFFFFFF),
        child: ProductCarouselSection(
          title: 'Más de Mariana Peña',
          products: productos(4),
          onProductTap: (_) {},
          compact: true,
        ),
      ),
      ancho: 320,
    );

    expect(find.text('Más de Mariana Peña'), findsOneWidget);
    expect(find.byType(ProductCard), findsWidgets);
  });

  testWidgets('un nombre de vendedor larguísimo no rompe el encabezado', (
    tester,
  ) async {
    await montar(
      tester,
      ProductCarouselSection(
        title: 'Más de ${'Comercializadora Universitaria del Norte ' * 3}',
        products: productos(2),
        onProductTap: (_) {},
      ),
      ancho: 320,
    );

    // El encabezado recorta con puntos suspensivos en vez de empujar la fila:
    // se comprueba que no se lleve por delante el ancho de la sección.
    final encabezado = tester.widget<Text>(find.byType(Text).first);
    expect(encabezado.maxLines, 1);
    expect(encabezado.overflow, TextOverflow.ellipsis);
  });
}
