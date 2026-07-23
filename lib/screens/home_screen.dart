import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/product_card.dart';
import '../widgets/section_header.dart';
import 'main_shell.dart';
import 'product_detail_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> _products = [];
  List<MarketplaceCategory> _categories = [];
  List<CartItem> _cart = [];
  List<HighlightPlan> _highlightPlans = [];
  bool _loading = true;
  bool _hasPublished = false;
  String? _error;
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getProducts(),
        ApiService.getCategories(),
        ApiService.getCart(),
        ApiService.getHighlightPlans(),
      ]);
      if (!mounted) return;

      // Verificar si el usuario ha publicado artículos
      final auth = context.read<AuthProvider>();
      bool hasPublished = false;
      if (auth.isLoggedIn) {
        try {
          final listings = await ApiService.getListings();
          hasPublished = listings.isNotEmpty;
        } catch (_) {
          // Si falla, asumir que no ha publicado
        }
      }

      setState(() {
        _products = results[0] as List<Product>;
        _categories = results[1] as List<MarketplaceCategory>;
        _cart = results[2] as List<CartItem>;
        _highlightPlans = results[3] as List<HighlightPlan>;
        _hasPublished = hasPublished;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  int get _cartCount =>
      _cart.fold<int>(0, (sum, item) => sum + item.quantity);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 48, color: AppColors.danger),
                const SizedBox(height: 16),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final filtered = _selectedCategoryId == null
        ? _products
        : _products.where((p) => p.category.id == _selectedCategoryId).toList();
    final featured = filtered.where((p) => p.isFeatured).toList();
    final offers = filtered.where((p) => p.isOffer).toList();
    final recent = filtered.where((p) => !p.isFeatured).toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: AppLogo(size: 44)),
                        _CartHeaderButton(
                          itemCount: _cartCount,
                          onTap: () =>
                              _openCart(context).then((_) => _loadData()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _MarketPulse(
                      productsCount: _products.length,
                      offersCount: offers.length,
                    ),
                    const SizedBox(height: 14),
                    _SearchBox(onTap: () => _openSearch(context)),
                    const SizedBox(height: 18),
                    _CategoryScroller(
                      categories: _categories,
                      selectedCategoryId: _selectedCategoryId,
                      onCategoryTap: (id) {
                        if (_selectedCategoryId == id) {
                          // Tap en la misma categoría → limpiar filtro
                          setState(() => _selectedCategoryId = null);
                        } else {
                          setState(() => _selectedCategoryId = id);
                        }
                      },
                    ),
                    if (_selectedCategoryId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _CategoryFilterChip(
                          category: _categories.firstWhere(
                            (c) => c.id == _selectedCategoryId,
                            orElse: () => _categories.first,
                          ),
                          onClear: () =>
                              setState(() => _selectedCategoryId = null),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_highlightPlans.isNotEmpty && _hasPublished)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: _HighlightPlansBanner(plans: _highlightPlans),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                child: SectionHeader(
                  title: 'Destacados',
                  actionLabel: 'Ver planes',
                  onAction: () => _showHighlightPlansSheet(context),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 280,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  scrollDirection: Axis.horizontal,
                  itemCount: featured.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final product = featured[index];
                    return ProductCard(
                      product: product,
                      width: 216,
                      onTap: () => _openDetail(context, product),
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                child: SectionHeader(
                  title: 'Publicaciones recientes',
                  actionLabel: 'Ordenar',
                  onAction: () =>
                      _showMockMessage(context, 'Ordenamiento visual'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final columns = width >= 720 ? 3 : 2;
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: columns == 3 ? 0.72 : 0.64,
                    ),
                    itemCount: recent.length,
                    itemBuilder: (context, index) {
                      final product = recent[index];
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

  Future<void> _openDetail(BuildContext context, Product product) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    ).then((_) => _loadData());
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SearchScreen()));
  }

  Future<void> _openCart(BuildContext context) {
    // Switch to cart tab (index 3) in MainShell
    final shell = context.findAncestorStateOfType<MainShellState>();
    shell?.selectTab(3);
    return Future.value();
  }

  void _showMockMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showHighlightPlansSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Planes para destacar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pensados para estudiantes y negocios fijos: precios bajos, visibilidad por tiempo y un plan mensual para aparecer siempre arriba.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                for (final plan in _highlightPlans) ...[
                  _HighlightPlanTile(plan: plan),
                  if (plan != _highlightPlans.last) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HighlightPlansBanner extends StatelessWidget {
  const _HighlightPlansBanner({required this.plans});

  final List<HighlightPlan> plans;

  @override
  Widget build(BuildContext context) {
    final topPlan = plans.first;

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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Destaca sin pagar de más',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Desde ${topPlan.price} por ${topPlan.days == 1 ? '24h' : '${topPlan.days} días'}; también hay plan mensual.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final plan in plans)
                _HighlightPlanChip(
                  label: plan.title,
                  value: plan.price,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HighlightPlanChip extends StatelessWidget {
  const _HighlightPlanChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$label · $value',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}

class _HighlightPlanTile extends StatelessWidget {
  const _HighlightPlanTile({required this.plan});

  final HighlightPlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            plan.days == 30 ? Icons.calendar_month_rounded : Icons.schedule_rounded,
            color: AppColors.orange,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  plan.description,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            plan.price,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartHeaderButton extends StatelessWidget {
  const _CartHeaderButton({required this.itemCount, required this.onTap});

  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onTap,
      icon: Badge.count(
        count: itemCount,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.shopping_bag_outlined),
      ),
    );
  }
}

class _MarketPulse extends StatelessWidget {
  const _MarketPulse({required this.productsCount, required this.offersCount});

  final int productsCount;
  final int offersCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PulseMetric(
              value: '$productsCount',
              label: 'Publicaciones',
              icon: Icons.storefront_rounded,
            ),
          ),
          const _MetricDivider(),
          Expanded(
            child: _PulseMetric(
              value: '$offersCount',
              label: 'Ofertas',
              icon: Icons.local_offer_rounded,
            ),
          ),
          const _MetricDivider(),
          const Expanded(
            child: _PulseMetric(
              value: '4.8',
              label: 'Confianza',
              icon: Icons.star_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 38, color: AppColors.border);
  }
}

class _PulseMetric extends StatelessWidget {
  const _PulseMetric({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primary, size: 19),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  const _CategoryFilterChip({
    required this.category,
    required this.onClear,
  });

  final MarketplaceCategory category;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(category.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            category.name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: AppColors.muted),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Buscar libros, laptops, tutorias...',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.tune_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryScroller extends StatelessWidget {
  const _CategoryScroller({
    required this.categories,
    this.selectedCategoryId,
    this.onCategoryTap,
  });

  final List<MarketplaceCategory> categories;
  final String? selectedCategoryId;
  final void Function(String)? onCategoryTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        padding: const EdgeInsets.only(left: 2),
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.id == selectedCategoryId;
          return InkWell(
            onTap: () => onCategoryTap?.call(category.id),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 68,
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.10)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? AppColors.primary : AppColors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        category.emoji,
                        style: const TextStyle(fontSize: 27),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    category.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? AppColors.primary : AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
