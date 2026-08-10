import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../widgets/auto_refresh.dart';
import '../widgets/product_card.dart';
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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
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
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MaxDiscountHeader(offers: filtered),
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            sliver: _loading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final product = filtered[index];
                      return SizedBox(
                        height: 122,
                        child: ProductCard(
                          product: product,
                          horizontal: true,
                          onTap: () => _openDetail(context, product),
                        ),
                      );
                    },
                  ),
          ),
        ],
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

/// Header con el mayor descuento real de las ofertas visibles.
///
/// Se calcula sobre la lista ya filtrada, no sobre el catálogo completo: si
/// el usuario filtra por una categoría, el porcentaje que anuncia el header
/// tiene que ser uno que de verdad pueda encontrar ahí abajo. Un "-40%"
/// mostrado sobre una lista donde el mejor descuento es del 10% es publicidad
/// engañosa, aunque el 40% exista en otra categoría.
class _MaxDiscountHeader extends StatelessWidget {
  const _MaxDiscountHeader({required this.offers});

  final List<Product> offers;

  /// Mayor descuento en porcentaje entero, o null si ninguna oferta visible
  /// tiene un precio anterior mayor al actual (sin descuento comprobable).
  int? get _maxDiscountPercent {
    int? best;
    for (final product in offers) {
      final previous = product.previousPrice;
      if (previous == null || previous <= 0 || product.price >= previous) {
        continue;
      }
      final percent = (((previous - product.price) / previous) * 100).round();
      if (percent <= 0) continue;
      if (best == null || percent > best) best = percent;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final maxDiscount = _maxDiscountPercent;
    if (maxDiscount == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_offer_rounded, color: AppColors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Hasta -$maxDiscount% de descuento',
                style: const TextStyle(
                  color: AppColors.orange,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${offers.length} ${offers.length == 1 ? 'oferta' : 'ofertas'}',
              style: TextStyle(
                color: context.colors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: selectedCategoryId == category.id,
                label: Text(category.name),
                avatar: Icon(category.icon, size: 18, color: category.color),
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
