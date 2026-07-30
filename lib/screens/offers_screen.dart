import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../widgets/auto_refresh.dart';
import '../widgets/product_card.dart';
import '../widgets/section_header.dart';
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
        ApiService.getCategories(),
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
                  Text(
                    'Ofertas',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Precios especiales publicados por estudiantes esta semana.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _OfferHeroBand(offers: _offers.take(3).toList()),
                  const SizedBox(height: 16),
                  _OfferCategoryChips(
                    categories: _categories,
                    selectedCategoryId: _selectedCategoryId,
                    onSelected: (id) =>
                        setState(() => _selectedCategoryId = id),
                  ),
                  const SizedBox(height: 18),
                  SectionHeader(
                    title: _loading
                        ? 'Cargando...'
                        : '${filtered.length} ofertas activas'),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            sliver: _loading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()))
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    ).then((_) => _loadData(silent: true));
  }
}

class _OfferHeroBand extends StatelessWidget {
  const _OfferHeroBand({required this.offers});

  final List<Product> offers;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_offer_rounded,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Precios de oportunidad',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.orange.withValues(alpha: 0.18),
                  ),
                ),
                child: const Text(
                  'Hasta -25%',
                  style: TextStyle(
                    color: AppColors.orange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final product in offers)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Icon(product.category.icon,
                      color: AppColors.primary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      product.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Product.formatPrice(product.price),
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
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
              label: const Text('Todas'),
              avatar: const Icon(Icons.sell_rounded, size: 18),
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: selectedCategoryId == category.id,
                label: Text(category.name),
                avatar: Icon(category.icon, size: 18, color: category.color),
                onSelected: (_) => onSelected(category.id),
              ),
            ),
        ],
      ),
    );
  }
}
