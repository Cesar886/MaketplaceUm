import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mercadito_um/main.dart';

void main() {
  testWidgets(
    'Mercadito UM renders premium feed, offers, cart and detail view',
    (tester) async {
      await tester.pumpWidget(const MyApp());

      expect(find.text('Mercadito UM'), findsWidgets);

      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();

      expect(find.text('Ofertas del campus'), findsOneWidget);
      expect(find.byIcon(Icons.shopping_bag_rounded), findsWidgets);
      expect(find.byIcon(Icons.add_rounded), findsWidgets);

      await tester.tap(
        find.text('iPad 9na gen con Apple Pencil generico').first,
      );
      await tester.pumpAndSettle();

      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Carrito'), findsWidgets);
      expect(find.text('Vendedor'), findsOneWidget);
    },
  );
}
