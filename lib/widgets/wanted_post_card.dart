import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';

/// Tarjeta de "búsqueda" (WantedPost) — mismo lenguaje visual que
/// [ProductCard] (radio, sombra, padding) para que ambas convivan en el
/// mismo feed del home sin desentonar.
class WantedPostCard extends StatelessWidget {
  const WantedPostCard({
    super.key,
    required this.post,
    required this.category,
    this.onTap,
    this.width,
  });

  final WantedPost post;
  final MarketplaceCategory? category;
  final VoidCallback? onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        color: context.colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: context.colors.accent.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          splashColor: context.colors.accent.withValues(alpha: 0.06),
          highlightColor: context.colors.accent.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 4 / 3.4,
                    child: Container(
                      color: (category?.color ?? context.colors.accent)
                          .withValues(alpha: 0.10),
                      alignment: Alignment.center,
                      child: Icon(
                        category?.icon ?? Icons.category_rounded,
                        size: 34,
                        color: category?.color ?? context.colors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _SeBuscaTag(post: post),
                const SizedBox(height: 4),
                Text(
                  post.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label(
                    13.5,
                    weight: FontWeight.w700,
                    color: context.colors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  post.description ?? 'wanted.no_description'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(11.5, color: context.colors.muted),
                ),
                const Spacer(),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (category != null) ...[
                      Icon(category!.icon, size: 12, color: category!.color),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        relativeTimeFromIso(post.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body(
                          11,
                          color: context.colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (width == null) return card;
    return SizedBox(width: width, child: card);
  }
}

class _SeBuscaTag extends StatelessWidget {
  const _SeBuscaTag({required this.post});

  final WantedPost post;

  @override
  Widget build(BuildContext context) {
    final priceMin = post.priceMin;
    final priceMax = post.priceMax;
    String label = 'wanted.badge'.tr();
    if (priceMin != null && priceMax != null) {
      label =
          '${Product.formatPrice(priceMin)} - ${Product.formatPrice(priceMax)}';
    } else if (priceMax != null) {
      label = 'wanted.up_to'.tr(
        namedArgs: {'price': Product.formatPrice(priceMax)},
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.label(
          12,
          weight: FontWeight.w800,
          color: context.colors.accent,
        ),
      ),
    );
  }
}
