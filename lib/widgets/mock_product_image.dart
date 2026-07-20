import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'badges.dart';

class MockProductImage extends StatelessWidget {
  const MockProductImage({
    super.key,
    required this.product,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.showFeaturedBadge = true,
    this.photoIndex = 0,
  });

  final Product product;
  final double? height;
  final BorderRadius borderRadius;
  final bool showFeaturedBadge;
  final int photoIndex;

  @override
  Widget build(BuildContext context) {
    final colorShift = photoIndex * 0.08;
    final base = product.imageColor;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base.withValues(alpha: 0.95 - colorShift.clamp(0, 0.2)),
              AppColors.primaryDark.withValues(alpha: 0.86),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              bottom: -24,
              child: Icon(
                product.imageIcon,
                size: 132,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            Center(
              child: Icon(product.imageIcon, size: 58, color: Colors.white),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      product.category.icon,
                      size: 14,
                      color: product.category.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      product.category.name,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showFeaturedBadge && (product.isOffer || product.isFeatured))
              Positioned(
                right: 10,
                top: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (product.isOffer)
                      OfferBadge(label: product.discountLabel, compact: true),
                    if (product.isOffer && product.isFeatured)
                      const SizedBox(height: 6),
                    if (product.isFeatured) const FeaturedBadge(compact: true),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
