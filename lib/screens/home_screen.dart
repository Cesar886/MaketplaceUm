import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../mock_data.dart';
import '../models.dart';
import '../widgets/app_logo.dart';
import '../widgets/product_card.dart';
import '../widgets/section_header.dart';
import 'cart_screen.dart';
import 'offers_screen.dart';
import 'product_detail_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final featured = mockProducts
        .where((product) => product.isFeatured)
        .toList();
    final offers = mockProducts.where((product) => product.isOffer).toList();
    final recent = mockProducts
        .where((product) => !product.isFeatured)
        .toList();

    return SafeArea(
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
                        itemCount: mockCartItems.fold<int>(
                          0,
                          (sum, item) => sum + item.quantity,
                        ),
                        onTap: () => _openCart(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _MarketPulse(
                    productsCount: mockProducts.length,
                    offersCount: offers.length,
                  ),
                  const SizedBox(height: 16),
                  _SearchBox(onTap: () => _openSearch(context)),
                  const SizedBox(height: 18),
                  _CategoryScroller(categories: mockCategories),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: SectionHeader(
                title: 'Ofertas del campus',
                actionLabel: 'Ver todas',
                onAction: () => _openOffers(context),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 268,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                scrollDirection: Axis.horizontal,
                itemCount: offers.take(8).length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final product = offers[index];
                  return ProductCard(
                    product: product,
                    width: 200,
                    heroEnabled: false,
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
                title: 'Destacados',
                actionLabel: 'Premium',
                onAction: () => _showMockMessage(
                  context,
                  'Publicaciones destacadas pagadas',
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 286,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                scrollDirection: Axis.horizontal,
                itemCount: featured.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final product = featured[index];
                  return ProductCard(
                    product: product,
                    width: 218,
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
                    childAspectRatio: 0.60,
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
    );
  }

  void _openDetail(BuildContext context, Product product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SearchScreen()));
  }

  void _openCart(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CartScreen()));
  }

  void _openOffers(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const OffersScreen()));
  }

  void _showMockMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CartHeaderButton extends StatelessWidget {
  const _CartHeaderButton({required this.itemCount, required this.onTap});

  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      icon: Badge.count(
        count: itemCount,
        backgroundColor: AppColors.orange,
        child: const Icon(Icons.shopping_bag_rounded),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.premiumBorder.withValues(alpha: 0.7),
        ),
        boxShadow: AppShadows.lifted,
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
          Container(
            width: 1,
            height: 42,
            color: Colors.white.withValues(alpha: 0.16),
          ),
          Expanded(
            child: _PulseMetric(
              value: '$offersCount',
              label: 'Ofertas',
              icon: Icons.local_offer_rounded,
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: Colors.white.withValues(alpha: 0.16),
          ),
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
        Icon(icon, color: AppColors.gold, size: 20),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
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
                    fontWeight: FontWeight.w700,
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
  const _CategoryScroller({required this.categories});

  final List<MarketplaceCategory> categories;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        padding: const EdgeInsets.only(left: 2),
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final category = categories[index];
          return Column(
            children: [
              Material(
                color: category.color.withValues(alpha: 0.12),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Categoria: ${category.name}')),
                  ),
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: Center(
                      child: Text(
                        category.emoji,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 64,
                child: Text(
                  category.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
