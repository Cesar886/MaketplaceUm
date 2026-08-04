import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/product_card_skeleton.dart';
import 'package:mercadito_um/widgets/seller_profile_skeleton.dart';

void main() {
  testWidgets(
    'SellerProfileSkeleton shows a circular avatar block and a 4-item '
    'product grid matching the real seller grid delegate',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SellerProfileSkeleton())),
      );

      final circleFinder = find.byWidgetPredicate(
        (w) => w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(circleFinder, findsWidgets);

      expect(find.byType(ProductCardSkeleton), findsNWidgets(4));

      final delegate =
          (tester.widget<GridView>(find.byType(GridView)).gridDelegate)
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);
      expect(delegate.childAspectRatio, 0.66);
    },
  );
}
