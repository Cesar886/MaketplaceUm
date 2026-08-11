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
              errorBuilder: (_, _, _) => CategoryImagePlaceholder(
                product: product,
                height: height,
                showFeaturedBadge: showFeaturedBadge,
                photoIndex: photoIndex,
              ),
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
            if (showFeaturedBadge && product.isOffer)
              Positioned(
                left: 0,
                top: 0,
                child: OfferCornerTag(label: product.discountLabel ?? 'Oferta'),
              ),
            if (showFeaturedBadge && product.isFeatured)
              const Positioned(
                right: 8,
                top: 8,
                child: FeaturedBadge(compact: true),
              ),
          ],
        ),
      );
    }

    // Sin imágenes reales: mock icon
    return CategoryImagePlaceholder(
      product: product,
      height: height,
      borderRadius: borderRadius,
      showFeaturedBadge: showFeaturedBadge,
      photoIndex: photoIndex,
    );
  }
}

/// Placeholder de categoría — se muestra cuando el producto no tiene
/// imágenes reales subidas. Extraído de [MockProductImage] para poder
/// reutilizarlo también en [ProductImageCarousel] cuando `images` está vacío.
class CategoryImagePlaceholder extends StatelessWidget {
  const CategoryImagePlaceholder({
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
    // El placeholder es ausencia de foto, no un producto más: se dibuja con
    // un ícono lineal fino en navy muy tenue sobre el fondo neutro cálido.
    // El bloque gris sólido de antes competía con las fotos reales de la
    // grilla y hacía que la pantalla se leyera como una plantilla a medio
    // llenar.
    final background = Color.lerp(
      context.colors.surfaceMuted,
      product.imageColor,
      0.05 + (photoIndex * 0.02).clamp(0, 0.06),
    )!;
    final accent = context.colors.accent;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: accent.withValues(alpha: 0.08)),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                product.imageIcon,
                size: 40,
                color: accent.withValues(alpha: 0.15),
              ),
            ),
            if (showFeaturedBadge && product.isOffer)
              Positioned(
                left: 0,
                top: 0,
                child: OfferCornerTag(label: product.discountLabel ?? 'Oferta'),
              ),
            if (showFeaturedBadge && product.isFeatured)
              const Positioned(
                right: 8,
                top: 8,
                child: FeaturedBadge(compact: true),
              ),
          ],
        ),
      ),
    );
  }
}
