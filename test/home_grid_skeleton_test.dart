import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/home_grid_skeleton.dart';
import 'package:mercadito_um/widgets/product_card_skeleton.dart';

void main() {
  testWidgets('HomeGridSkeleton shows 6 ProductCardSkeleton in a 2-column grid '
      'matching the real home grid delegate', (tester) async {
    // Superficie más alta que el default de test: el grid real es tall
    // (childAspectRatio 0.64) y con el tamaño default solo cabe 1 fila
    // visible, de-renderizando (lazy) los ítems restantes.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeGridSkeleton())),
    );

    expect(find.byType(ProductCardSkeleton), findsNWidgets(6));

    final delegate =
        (tester.widget<GridView>(find.byType(GridView)).gridDelegate)
            as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(delegate.crossAxisSpacing, 12);
    expect(delegate.mainAxisSpacing, 12);
    expect(delegate.childAspectRatio, 0.64);
  });
}
