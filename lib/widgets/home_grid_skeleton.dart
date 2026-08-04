import 'package:flutter/material.dart';

import 'product_card_skeleton.dart';

/// Skeleton del grid de productos del home. Usa el mismo
/// [SliverGridDelegateWithFixedCrossAxisCount] que el grid real en
/// `home_screen.dart` (crossAxisCount:2, spacing:12/12, aspectRatio:0.64).
class HomeGridSkeleton extends StatelessWidget {
  const HomeGridSkeleton({super.key});

  static const _itemCount = 6;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _itemCount,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.64,
        ),
        itemBuilder: (context, index) => const ProductCardSkeleton(),
      ),
    );
  }
}
