import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_service.dart';
import 'product_card.dart';
import 'product_card_skeleton.dart';
import 'product_grid_metrics.dart';

/// Feed progresivo al final del detalle.
///
/// Descarga una sola lista rankeada y revela sus elementos en lotes conforme
/// la persona se acerca al final. Así el scroll y la composición del grid son
/// fluidos, sin disparar una petición por cada pocos píxeles recorridos.
class MoreProductsSection extends StatefulWidget {
  const MoreProductsSection({
    super.key,
    required this.currentProductId,
    required this.onProductTap,
    required this.onCategoryTap,
    this.excludedProductIds = const {},
  });

  final String currentProductId;
  final Set<String> excludedProductIds;
  final ValueChanged<Product> onProductTap;
  final ValueChanged<MarketplaceCategory> onCategoryTap;

  @override
  State<MoreProductsSection> createState() => _MoreProductsSectionState();
}

class _MoreProductsSectionState extends State<MoreProductsSection> {
  static const _batchSize = 6;
  static const _feedLimit = 60;

  List<Product> _products = const [];
  int _visibleCount = _batchSize;
  bool _loading = true;
  bool _failed = false;
  ScrollPosition? _scrollPosition;

  List<Product> get _filteredProducts => _products
      .where(
        (product) =>
            product.id != widget.currentProductId &&
            !widget.excludedProductIds.contains(product.id),
      )
      .toList(growable: false);

  List<MarketplaceCategory> get _topCategories {
    final counts = <String, int>{};
    final categories = <String, MarketplaceCategory>{};
    for (final product in _filteredProducts) {
      final category = product.category;
      categories[category.id] = category;
      counts.update(category.id, (count) => count + 1, ifAbsent: () => 1);
    }
    final ranked = categories.values.toList()
      ..sort((a, b) {
        final byCount = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
        return byCount != 0 ? byCount : a.name.compareTo(b.name);
      });
    return ranked.take(3).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _scrollPosition)) return;
    _scrollPosition?.removeListener(_onScroll);
    _scrollPosition = position;
    _scrollPosition?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onScroll);
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final auth = context.read<AuthProvider>();
      final deviceId = await AnonymousId.get();
      final products = await ApiService.getFeed(
        deviceId: deviceId,
        userId: auth.isLoggedIn ? auth.backendSellerId : null,
        limit: _feedLimit,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
        _visibleCount = _batchSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _onScroll() {
    final position = _scrollPosition;
    if (position == null || _loading || _failed) return;
    if (position.extentAfter > 520) return;

    final total = _filteredProducts.length;
    if (_visibleCount >= total) return;
    setState(() {
      _visibleCount = math.min(_visibleCount + _batchSize, total);
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = _filteredProducts;
    if (!_loading && !_failed && products.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 19,
              color: context.colors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'product.more_for_you'.tr(),
                style: AppTypography.heading(17, color: context.colors.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'product.more_for_you_hint'.tr(),
          style: TextStyle(
            color: context.colors.muted,
            fontSize: 12.5,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const _LoadingGrid()
        else if (_failed)
          _LoadError(onRetry: _load)
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = ProductGridMetrics.columnsFor(
                constraints.maxWidth,
              );
              final visible = products.take(_visibleCount).toList();
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: ProductGridMetrics.delegateFor(columns),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final product = visible[index];
                  return ProductCard(
                    product: product,
                    heroEnabled: false,
                    onTap: () => widget.onProductTap(product),
                  );
                },
              );
            },
          ),
          if (_visibleCount < products.length) ...[
            const SizedBox(height: 18),
            Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.primary,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 26),
            _ExploreCategories(
              categories: _topCategories,
              onTap: widget.onCategoryTap,
            ),
          ],
        ],
      ],
    );
  }
}

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ProductGridMetrics.columnsFor(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: ProductGridMetrics.delegateFor(columns),
          itemCount: 4,
          itemBuilder: (_, _) => const ProductCardSkeleton(),
        );
      },
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text('product.more_retry'.tr()),
      ),
    );
  }
}

class _ExploreCategories extends StatelessWidget {
  const _ExploreCategories({required this.categories, required this.onTap});

  final List<MarketplaceCategory> categories;
  final ValueChanged<MarketplaceCategory> onTap;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.grid_view_rounded,
                  size: 17,
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'product.explore_categories'.tr(),
                      style: TextStyle(
                        color: context.colors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'product.explore_categories_hint'.tr(),
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < categories.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: _CategoryCard(
                    category: categories[index],
                    onTap: () => onTap(categories[index]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final MarketplaceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = normalizeCategoryColor(
      category.color,
      Theme.of(context).brightness,
    );
    return Material(
      color: color.withValues(alpha: 0.075),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: color.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 11, 7, 10),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(category.icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                category.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.ink,
                  fontSize: 11.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Icon(Icons.arrow_forward_rounded, size: 13, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
