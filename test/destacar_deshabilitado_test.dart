// La feature de "destacar publicación" está apagada tras
// `kDestacarHabilitado` (ver lib/features/highlight/destacar_flag.dart), y el
// requisito no era solo quitar el botón de comprar el plan: una publicación
// que quedó con `isFeatured = true` en la base NO debe seguir luciendo como
// destacada mientras la feature no exista.
//
// Estos tests atan el badge a la bandera en vez de darlo por ausente, así que
// siguen siendo correctos el día que la bandera vuelva a `true`: lo que
// verifican es que badge y bandera no puedan separarse.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/features/highlight/destacar_flag.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/badges.dart';
import 'package:mercadito_um/widgets/mock_product_image.dart';
import 'package:mercadito_um/widgets/product_card.dart';

void main() {
  Product producto({bool destacado = true, bool oferta = false}) {
    return Product.fromJson({
      'id': 'p_destacado',
      'title': 'Sudadera Champion talla grande',
      'price': 350,
      if (oferta) 'previousPrice': 500,
      if (oferta) 'isOffer': true,
      if (oferta) 'discountLabel': '-30%',
      'description': 'Poco uso',
      'publishedAgo': 'hace 2 días',
      'seller': 's_1',
      'categoryObj': {'id': 'clothes', 'name': 'Ropa', 'emoji': '👕'},
      'images': <String>[],
      'extras': <dynamic>[],
      'featured': destacado,
      'atributos': <String, dynamic>{},
    });
  }

  Widget envolver(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SizedBox(width: 200, child: child),
      ),
    );
  }

  /// Cuántos badges de destacado debería haber: ninguno con la feature
  /// apagada, uno cuando vuelva.
  final esperadoBadge = kDestacarHabilitado ? findsOneWidget : findsNothing;

  testWidgets('la foto de una publicación destacada no lleva badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      envolver(MockProductImage(product: producto(), height: 120)),
    );

    expect(find.byType(FeaturedBadge), esperadoBadge);
  });

  testWidgets('la tarjeta del feed tampoco lo pinta', (tester) async {
    await tester.pumpWidget(
      envolver(ProductCard(product: producto(), heroEnabled: false)),
    );

    expect(find.byType(FeaturedBadge), esperadoBadge);
  });

  testWidgets('el realce dorado de la tarjeta también sigue a la bandera', (
    tester,
  ) async {
    // Borde y sombra elevada son el otro "esto está destacado": sin ellos el
    // badge se va pero la tarjeta sigue destacándose sobre las demás.
    await tester.pumpWidget(
      envolver(ProductCard(product: producto(), heroEnabled: false)),
    );

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(ProductCard),
        matching: find.byType(Material),
      ),
    );
    final borde = (material.shape as RoundedRectangleBorder).side;

    if (kDestacarHabilitado) {
      expect(borde.color, isNot(Colors.transparent));
    } else {
      expect(borde.color, Colors.transparent);
    }
  });

  testWidgets('el badge de oferta NO se ve afectado por la bandera', (
    tester,
  ) async {
    // La bandera apaga el destacado, no la oferta: si se hubiera colado en el
    // mismo `if`, un descuento real dejaría de anunciarse.
    await tester.pumpWidget(
      envolver(
        MockProductImage(
          product: producto(destacado: false, oferta: true),
          height: 120,
        ),
      ),
    );

    expect(find.byType(OfferCornerTag), findsOneWidget);
  });
}
