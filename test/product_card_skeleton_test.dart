import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/app_shimmer.dart';
import 'package:mercadito_um/widgets/product_card_skeleton.dart';

void main() {
  // Ancho/alto realistas de una celda del grid real (2 columnas,
  // ver ProductGridMetrics), no el tamaño completo de pantalla — evita un
  // overflow artificial que no ocurre dentro del SliverGrid real.
  const cellSize = Size(170, 265);

  testWidgets('ProductCardSkeleton renders inside a shimmer wrapper', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: cellSize,
              child: const ProductCardSkeleton(),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ProductCardSkeleton), findsOneWidget);
    expect(find.byType(AppShimmer), findsOneWidget);
    expect(find.byType(ShimmerBox), findsAtLeastNWidgets(6));
  });

  testWidgets('ProductCardSkeleton image block uses a 4/3.4 aspect ratio', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: cellSize,
              child: const ProductCardSkeleton(),
            ),
          ),
        ),
      ),
    );

    final aspectRatio = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(aspectRatio.aspectRatio, closeTo(4 / 3.4, 0.001));
  });
}
