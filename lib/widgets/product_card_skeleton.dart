import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'app_shimmer.dart';

/// Skeleton de una tarjeta de producto para el grid del home, con las
/// mismas dimensiones que [ProductCard] (ver `_GridProductCard` en
/// `product_card.dart`): mismo padding, mismo aspect ratio de imagen,
/// mismas alturas de bloques de texto, incluido el contador de vistas.
/// Sin parámetros — es un placeholder estático, no representa un producto
/// real.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        color: context.colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: AppShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AspectRatio(
                  aspectRatio: 4 / 3.4,
                  child: ShimmerBox(borderRadius: 10),
                ),
                const SizedBox(height: 8),
                const ShimmerBox(width: 60, height: 14),
                const SizedBox(height: 4),
                const ShimmerBox(height: 13, borderRadius: 4),
                const SizedBox(height: 3),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.55,
                  child: const ShimmerBox(height: 13, borderRadius: 4),
                ),
                const SizedBox(height: 2),
                const ShimmerBox(width: 90, height: 11, borderRadius: 4),
                const Spacer(),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Expanded(
                      child: ShimmerBox(height: 11, borderRadius: 4),
                    ),
                    const SizedBox(width: 6),
                    const ShimmerBox(width: 22, height: 11, borderRadius: 4),
                    const SizedBox(width: 6),
                    const ShimmerBox(width: 46, height: 18, borderRadius: 999),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
