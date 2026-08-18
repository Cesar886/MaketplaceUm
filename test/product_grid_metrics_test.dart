// Las métricas de la cuadrícula de productos viven en UN solo lugar.
//
// Antes estaban copiadas en cinco: los dos grids reales (home y perfil de
// vendedor), sus dos skeletons, y los tests. Cambiar el alto de la celda en
// home_screen.dart y olvidar el resto no rompía nada visible al desarrollar
// —cada archivo compilaba igual— pero dejaba el skeleton midiendo distinto
// que el grid que lo reemplaza, así que las tarjetas saltaban al terminar de
// cargar. Fue exactamente lo que pasó: el skeleton del perfil se quedó en
// 0.66 cuando su grid ya iba en 0.62, y el docstring del skeleton del home
// decía 0.58, un valor que ya no usaba nadie.
//
// Estos tests amarran a los consumidores a la constante compartida.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/home_grid_skeleton.dart';
import 'package:mercadito_um/widgets/product_grid_metrics.dart';
import 'package:mercadito_um/widgets/seller_profile_skeleton.dart';

SliverGridDelegateWithFixedCrossAxisCount _delegateDe(WidgetTester tester) {
  return tester.widget<GridView>(find.byType(GridView)).gridDelegate
      as SliverGridDelegateWithFixedCrossAxisCount;
}

void main() {
  group('ProductGridMetrics', () {
    test('dos columnas en teléfono y tres a partir del punto de corte', () {
      expect(ProductGridMetrics.columnsFor(390), 2);
      expect(ProductGridMetrics.columnsFor(719), 2);
      expect(ProductGridMetrics.columnsFor(720), 3);
      expect(ProductGridMetrics.columnsFor(1024), 3);
    });

    test('la celda de tres columnas es menos alta que la de dos', () {
      // Con tres columnas la celda es más angosta pero el contenido no
      // encoge en la misma proporción, así que necesita menos alto relativo.
      expect(
        ProductGridMetrics.aspectRatioFor(3),
        greaterThan(ProductGridMetrics.aspectRatioFor(2)),
      );
    });

    test('el delegate refleja las columnas que se le piden', () {
      final dos = ProductGridMetrics.delegateFor(2);
      expect(dos.crossAxisCount, 2);
      expect(dos.childAspectRatio, ProductGridMetrics.aspectRatioFor(2));
      expect(dos.mainAxisSpacing, ProductGridMetrics.spacing);
      expect(dos.crossAxisSpacing, ProductGridMetrics.spacing);

      expect(ProductGridMetrics.delegateFor(3).crossAxisCount, 3);
    });
  });

  group('los skeletons miden igual que el grid que reemplazan', () {
    testWidgets('HomeGridSkeleton', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HomeGridSkeleton())),
      );

      final delegate = _delegateDe(tester);
      expect(delegate.crossAxisCount, 2);
      expect(delegate.childAspectRatio, ProductGridMetrics.aspectRatioFor(2));
      expect(delegate.mainAxisSpacing, ProductGridMetrics.spacing);
      expect(delegate.crossAxisSpacing, ProductGridMetrics.spacing);
    });

    testWidgets('SellerProfileSkeleton', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SellerProfileSkeleton())),
      );

      final delegate = _delegateDe(tester);
      expect(delegate.crossAxisCount, 2);
      expect(delegate.childAspectRatio, ProductGridMetrics.aspectRatioFor(2));
      expect(delegate.mainAxisSpacing, ProductGridMetrics.spacing);
      expect(delegate.crossAxisSpacing, ProductGridMetrics.spacing);
    });
  });
}
