import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'badges.dart';
import 'mock_product_image.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.width,
    this.horizontal = false,
    this.heroEnabled = true,
  });

  final Product product;
  final VoidCallback? onTap;
  final double? width;
  final bool horizontal;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    final accent = product.isOffer
        ? AppColors.orange
        : product.isFeatured
        ? AppColors.gold
        : AppColors.border;
    final borderColor = product.isOffer || product.isFeatured
        ? accent.withValues(alpha: 0.32)
        : AppColors.border;

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: product.isFeatured || product.isOffer ? AppShadows.lifted : null,
      ),
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: horizontal
                ? _HorizontalProductCard(
                    product: product,
                    heroEnabled: heroEnabled,
                  )
                : _GridProductCard(product: product, heroEnabled: heroEnabled),
          ),
        ),
      ),
    );

    if (width == null) return card;
    return SizedBox(width: width, child: card);
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
          child: MockProductImage(product: product, height: 100),
        ),
        const SizedBox(height: 8),
        _PriceBlock(product: product),
        const SizedBox(height: 4),
        Text(
          product.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.18),
        ),
        const SizedBox(height: 4),
        Text(
          product.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: Text(
                product.publishedAgo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
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
          width: 92,
          child: _HeroProductImage(
            product: product,
            enabled: heroEnabled,
            child: MockProductImage(product: product, height: 92),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PriceBlock(product: product),
              const SizedBox(height: 6),
              Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                product.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(
                    product.category.icon,
                    size: 15,
                    color: product.category.color,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      product.category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    product.publishedAgo,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
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
    if (!enabled) return child;
    return Hero(tag: 'product-${product.id}', child: child);
  }
}

class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 7,
      runSpacing: 1,
      children: [
        Text(
          Product.formatPrice(product.price),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark,
          ),
        ),
        if (product.previousPrice != null)
          Text(
            Product.formatPrice(product.previousPrice!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        if (product.isOffer)
          OfferBadge(label: product.discountLabel, compact: true)
        else if (product.isFeatured)
          const FeaturedBadge(compact: true),
      ],
    );
  }
}
