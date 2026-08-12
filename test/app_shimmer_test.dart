import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/app_shimmer.dart';
import 'package:shimmer/shimmer.dart';

void main() {
  testWidgets('AppShimmer wraps its child in a Shimmer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppShimmer(child: ShimmerBox(width: 40, height: 40)),
        ),
      ),
    );

    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.byType(ShimmerBox), findsOneWidget);
  });

  testWidgets('ShimmerBox applies the requested border radius', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShimmerBox(width: 20, height: 20, borderRadius: 12),
        ),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(12));
  });
}
