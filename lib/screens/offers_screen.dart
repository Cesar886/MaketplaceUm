import 'package:flutter/material.dart';

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
                onSelected: (selected) =>
                    onSelected(selected ? category.id : null),
              ),
            ),
        ],
      ),
    );
  }
}
