import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/mock_product_image.dart';

/// Cliente cuyo `getUrl` no resuelve nunca: reproduce el caso real que rompía
/// la tarjeta — no un error de red, sino una respuesta que tarda tanto que
/// para quien mira la pantalla es indistinguible de estar colgada.
class _ClienteColgado implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      Completer<HttpClientRequest>().future;
}

Product _producto() => Product(
  id: 'p1',
  title: 'Producto',
  price: 100,
  category: const MarketplaceCategory(
    id: 'other',
    name: 'Otros',
    emoji: '📦',
    icon: Icons.category,
    color: Color(0xFF607D8B),
  ),
  description: 'desc',
  publishedAgo: 'Ahora',
  seller: const Seller(
    id: 's1',
    name: 'Vendedor',
    avatarInitials: 'V',
    major: 'Sistemas',
    rating: 0,
    reviews: 0,
    verified: false,
  ),
  images: const ['/uploads/foto.webp'],
  imageIcon: Icons.inventory_2,
  imageColor: const Color(0xFF607D8B),
);

Widget _montar(Product product) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 180,
        height: 180,
        child: MockProductImage(product: product, height: 180),
      ),
    ),
  ),
);

/// Corre [cuerpo] con las peticiones de imagen colgadas.
///
/// El reset va DENTRO del cuerpo del test y no en un `tearDown`: Flutter
/// verifica que ninguna variable de debug de painting quede tocada al
/// terminar el cuerpo, y esa verificación corre antes que los tearDown.
Future<void> conRedColgada(Future<void> Function() cuerpo) async {
  debugNetworkImageHttpClientProvider = () => _ClienteColgado();
  try {
    await cuerpo();
  } finally {
    debugNetworkImageHttpClientProvider = null;
  }
}

void main() {
  testWidgets(
    'una carga que se cuelga termina en el placeholder, no en spinner eterno',
    (tester) async {
      await conRedColgada(() async {
        await tester.pumpWidget(_montar(_producto()));
        await tester.pump();

        // Mientras la carga sigue viva se mantiene el estado de carga: una
        // foto que tarda 10 s es lenta, no es un fallo, y rendirse antes
        // cambiaría fotos buenas por placeholders.
        expect(find.byType(CategoryImagePlaceholder), findsNothing);
        await tester.pump(const Duration(seconds: 10));
        expect(find.byType(CategoryImagePlaceholder), findsNothing);

        // Pasado el timeout cae al placeholder de categoría. Este era el bug:
        // como el servidor nunca devuelve un error (el 200 llega, solo que
        // tardísimo), `errorBuilder` no se disparaba nunca y la tarjeta se
        // quedaba en estado de carga indefinidamente.
        await tester.pump(const Duration(seconds: 11));
        expect(find.byType(CategoryImagePlaceholder), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });
    },
  );

  testWidgets('un producto sin fotos va directo al placeholder, sin spinner', (
    tester,
  ) async {
    final sinFotos = Product(
      id: 'p2',
      title: 'Sin fotos',
      price: 50,
      category: _producto().category,
      description: 'desc',
      publishedAgo: 'Ahora',
      seller: _producto().seller,
      imageIcon: Icons.inventory_2,
      imageColor: const Color(0xFF607D8B),
    );

    await tester.pumpWidget(_montar(sinFotos));
    await tester.pump();

    expect(find.byType(CategoryImagePlaceholder), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('el timeout se reinicia cuando la celda recicla con otra URL', (
    tester,
  ) async {
    await conRedColgada(() async {
      await tester.pumpWidget(_montar(_producto()));
      await tester.pump(const Duration(seconds: 15));

      // El grid recicla el State al hacer scroll: llega otra foto al mismo
      // widget. Su reloj arranca de cero, no hereda los 15 s ya corridos.
      final otro = Product(
        id: 'p3',
        title: 'Otro',
        price: 100,
        category: _producto().category,
        description: 'desc',
        publishedAgo: 'Ahora',
        seller: _producto().seller,
        images: const ['/uploads/otra.webp'],
        imageIcon: Icons.inventory_2,
        imageColor: const Color(0xFF607D8B),
      );
      await tester.pumpWidget(_montar(otro));

      await tester.pump(const Duration(seconds: 10));
      expect(
        find.byType(CategoryImagePlaceholder),
        findsNothing,
        reason: 'heredó el timeout de la foto anterior',
      );

      await tester.pump(const Duration(seconds: 11));
      expect(find.byType(CategoryImagePlaceholder), findsOneWidget);
    });
  });
}
