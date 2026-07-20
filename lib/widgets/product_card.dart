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
    final borderColor = product.isOffer
        ? AppColors.orange.withValues(alpha: 0.72)
        : product.isFeatured
        ? AppColors.premiumBorder
        : AppColors.border;

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: product.isFeatured || product.isOffer
            ? AppShadows.soft
            : null,
      ),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
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
        const SizedBox(height: 10),
        _PriceBlock(product: product),
        const SizedBox(height: 5),
        Text(
          product.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, height: 1.15),
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
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (product.isOffer)
              OfferBadge(label: product.discountLabel, compact: true)
            else if (product.isFeatured)
              const FeaturedBadge(compact: true),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _PriceBlock(product: product)),
                  if (product.isOffer)
                    OfferBadge(label: product.discountLabel, compact: true)
                  else if (product.isFeatured)
                    const FeaturedBadge(compact: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  height: 1.15,
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    product.publishedAgo,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
          product.price,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.primaryDark,
          ),
        ),
        if (product.previousPrice != null)
          Text(
            product.previousPrice!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }
}
