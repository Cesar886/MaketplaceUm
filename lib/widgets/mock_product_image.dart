import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
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
    // Si hay imágenes reales subidas, mostrarlas
    if (product.images.isNotEmpty) {
      final index = photoIndex < product.images.length ? photoIndex : 0;
      final imageUrl = '${ApiService.baseUrl}${product.images[index]}';

      return ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Image.network(
              imageUrl,
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _buildMockIcon(context),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: height,
                  color: context.colors.surfaceMuted,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
            if (showFeaturedBadge && (product.isOffer || product.isFeatured))
              Positioned(
                right: 8,
                top: 8,
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
      );
    }

    // Sin imágenes reales: mock icon
    return _buildMockIcon(context);
  }

  Widget _buildMockIcon(BuildContext context) {
    final tintAmount = 0.08 + (photoIndex * 0.03).clamp(0, 0.09);
    final background = Color.lerp(
      context.colors.surface,
      product.imageColor,
      tintAmount,
    )!;
    final accent = Color.lerp(product.imageColor, context.colors.accent, 0.14)!;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: accent.withValues(alpha: 0.10)),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -26,
              child: Icon(
                product.imageIcon,
                size: 128,
                color: accent.withValues(alpha: 0.07),
              ),
            ),
            Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: context.colors.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.12)),
                ),
                child: Icon(product.imageIcon, size: 32, color: accent),
              ),
            ),
            if (showFeaturedBadge && (product.isOffer || product.isFeatured))
              Positioned(
                right: 8,
                top: 8,
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
