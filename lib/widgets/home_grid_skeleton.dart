import 'package:flutter/material.dart';

import 'product_card_skeleton.dart';
import 'product_grid_metrics.dart';

/// Skeleton del grid de productos del home.
///
/// Toma sus medidas de [ProductGridMetrics], la misma fuente que el grid
/// real en `home_screen.dart`. Antes las repetía como literales y el
/// docstring llegó a anunciar un aspectRatio de 0.58 que ya no usaba nadie.
class HomeGridSkeleton extends StatelessWidget {
  const HomeGridSkeleton({super.key});

  static const _itemCount = 6;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _itemCount,
        gridDelegate: ProductGridMetrics.delegateFor(2),
        itemBuilder: (context, index) => const ProductCardSkeleton(),
      ),
    );
  }
}
