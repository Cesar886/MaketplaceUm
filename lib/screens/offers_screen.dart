import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../widgets/auto_refresh.dart';
import '../widgets/product_card.dart';
import '../widgets/product_card_skeleton.dart';
import '../widgets/product_grid_metrics.dart';
import 'product_detail_screen.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> with AutoRefreshMixin {
  String? _selectedCategoryId;
  List<Product> _offers = [];
  List<MarketplaceCategory> _categories = [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  Future<void> onAutoRefresh() => _loadData(silent: true);

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && _offers.isEmpty) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getProducts(offer: true),
        ApiService.getCategoriesRanked(),
      ]);
      if (!mounted) return;
      setState(() {
        _offers = results[0] as List<Product>;
        _categories = results[1] as List<MarketplaceCategory>;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = _offers.isEmpty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _offers.where((product) {
      final matchesCategory =
          _selectedCategoryId == null ||
          product.category.id == _selectedCategoryId;
      return matchesCategory;
    }).toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadData,
        color: context.colors.accent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'offers.title'.tr(),
                      style: AppTypography.heading(
                        24,
                        color: context.colors.ink,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'offers.browse_category'.tr(),
                            style: AppTypography.heading(
                              15,
                              color: context.colors.ink,
                            ),
                          ),
                        ),
                        if (!_loading) _ResultsCount(count: filtered.length),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _OfferCategoryChips(
                      categories: _categories,
                      selectedCategoryId: _selectedCategoryId,
                      onSelected: (id) =>
                          setState(() => _selectedCategoryId = id),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const _OffersSkeletonGrid()
            else if (_loadFailed)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _OffersState(
                  icon: Icons.cloud_off_rounded,
                  title: 'offers.load_error_title'.tr(),
                  subtitle: 'offers.load_error_body'.tr(),
                  actionLabel: 'common.retry'.tr(),
                  onAction: _loadData,
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _OffersState(
                  icon: Icons.local_offer_outlined,
                  title: _selectedCategoryId == null
                      ? 'offers.empty_title'.tr()
                      : 'offers.empty_category_title'.tr(),
                  subtitle: _selectedCategoryId == null
                      ? 'offers.empty_body'.tr()
                      : 'offers.empty_category_body'.tr(),
                  actionLabel: _selectedCategoryId == null
                      ? null
                      : 'offers.view_all'.tr(),
                  actionIcon: Icons.grid_view_rounded,
                  onAction: _selectedCategoryId == null
                      ? null
                      : () => setState(() => _selectedCategoryId = null),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = ProductGridMetrics.columnsFor(
                      constraints.crossAxisExtent,
                    );
                    return SliverGrid.builder(
                      gridDelegate: ProductGridMetrics.delegateFor(columns),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final product = filtered[index];
                        // La misma tarjeta vertical y las mismas métricas que
                        // usa el feed de Home. Cualquier ajuste futuro al card
                        // o al grid se refleja aquí automáticamente.
                        return ProductCard(
                          product: product,
                          onTap: () => _openDetail(context, product),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, Product product) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ProductDetailScreen(product: product),
          ),
        )
        .then((_) => _loadData(silent: true));
  }
}

class _ResultsCount extends StatelessWidget {
  const _ResultsCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'offers.results'.plural(count),
        style: TextStyle(
          color: context.colors.mutedStrong,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OfferCategoryChips extends StatelessWidget {
  const _OfferCategoryChips({
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  final List<MarketplaceCategory> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selectedCategoryId == null,
              label: Text('offers.all'.tr()),
              avatar: Icon(
                Icons.grid_view_rounded,
                size: 17,
                color: context.colors.accent,
              ),
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: selectedCategoryId == category.id,
                label: Text(category.name),
                avatar: Icon(
                  category.icon,
                  size: 18,
                  color: normalizeCategoryColor(
                    category.color,
                    Theme.of(context).brightness,
                  ),
                ),
                onSelected: (selected) {
                  // Solo cuenta como interés cuando se selecciona; volver a
                  // tocar para deseleccionar no es una señal de curiosidad.
                  if (selected) ApiService.registerCategoryTap(category.id);
                  onSelected(selected ? category.id : null);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _OffersSkeletonGrid extends StatelessWidget {
  const _OffersSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final columns = ProductGridMetrics.columnsFor(
            constraints.crossAxisExtent,
          );
          return SliverGrid.builder(
            gridDelegate: ProductGridMetrics.delegateFor(columns),
            itemCount: columns * 2,
            itemBuilder: (_, _) => const ProductCardSkeleton(),
          );
        },
      ),
    );
  }
}

class _OffersState extends StatelessWidget {
  const _OffersState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.actionIcon = Icons.refresh_rounded,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: context.colors.accentTint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: context.colors.accent, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.heading(18, color: context.colors.ink),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.body(13, color: context.colors.muted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
