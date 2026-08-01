import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'badges.dart';
import 'mock_product_image.dart';
import 'price_tag.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.width,
    this.horizontal = false,
    this.heroEnabled = true,
    this.animationValue,
  });

  final Product product;
  final VoidCallback? onTap;
  final double? width;
  final bool horizontal;
  final bool heroEnabled;

  /// 0.0 → invisible, 1.0 → fully visible. Null = sin animación.
  final double? animationValue;

  @override
  Widget build(BuildContext context) {
    Widget card = _buildCard(context);

    if (animationValue != null) {
      final anim = animationValue!.clamp(0.0, 1.0);
      card = Opacity(
        opacity: Curves.easeOut.transform(anim),
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - Curves.easeOutCubic.transform(anim))),
          child: card,
        ),
      );
    }

    if (width == null) return card;
    return SizedBox(width: width, child: card);
  }

  Widget _buildCard(BuildContext context) {
    final hasAccent = product.isOffer || product.isFeatured;
    final borderColor = product.isOffer
        ? AppColors.amber.withValues(alpha: 0.35)
        : product.isFeatured
            ? AppColors.gold.withValues(alpha: 0.35)
            : Colors.transparent;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: hasAccent ? AppShadows.lifted : AppShadows.soft,
      ),
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor, width: hasAccent ? 1.5 : 0),
        ),
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.primary.withValues(alpha: 0.06),
          highlightColor: AppColors.primary.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: horizontal
                ? _HorizontalProductCard(product: product, heroEnabled: heroEnabled)
                : _GridProductCard(product: product, heroEnabled: heroEnabled),
          ),
        ),
      ),
    );
  }
}

class _GridProductCard extends StatelessWidget {
  const _GridProductCard({required this.product, required this.heroEnabled});

  final Product product;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroProductImage(
          product: product,
          enabled: heroEnabled,
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: MockProductImage(product: product, height: double.infinity),
          ),
        ),
        const SizedBox(height: 9),
        PriceTag(product: product),
        const SizedBox(height: 5),
        Text(
          product.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.label(13.5, weight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          product.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.body(12, color: AppColors.muted),
        ),
        const Spacer(),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                product.publishedAgo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(11, color: AppColors.muted),
              ),
            ),
            if (product.availability != null)
              AvailabilityBadge(availability: product.availability!),
          ],
        ),
      ],
    );
  }
}

class _HorizontalProductCard extends StatelessWidget {
  const _HorizontalProductCard({
    required this.product,
    required this.heroEnabled,
  });

  final Product product;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: _HeroProductImage(
            product: product,
            enabled: heroEnabled,
            child: MockProductImage(product: product, height: 96),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PriceTag(product: product),
              const SizedBox(height: 5),
              Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label(13.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                product.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(12, color: AppColors.muted),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(
                    product.category.icon,
                    size: 14,
                    color: product.category.color,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      product.category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(11, color: AppColors.muted),
                    ),
                  ),
                  Text(
                    product.publishedAgo,
                    style: AppTypography.body(11, color: AppColors.muted),
                  ),
                  if (product.availability != null) ...[
                    const SizedBox(width: 6),
                    AvailabilityBadge(availability: product.availability!),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroProductImage extends StatelessWidget {
  const _HeroProductImage({
    required this.product,
    required this.enabled,
    required this.child,
  });

  final Product product;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: child,
    );

    if (!product.isAvailable) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: Colors.white.withValues(alpha: 0.65),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    'Agotado',
                    style: AppTypography.label(13, weight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!enabled) return content;
    return Hero(tag: 'product-${product.id}', child: content);
  }
}
