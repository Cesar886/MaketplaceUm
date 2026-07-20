import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../widgets/badges.dart';
import '../widgets/mock_product_image.dart';
import 'cart_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _photoIndex = 0;
  late bool _favorite = widget.product.isFavorite;

  Product get product => widget.product;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 330,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton.filled(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            actions: [
              IconButton.filledTonal(
                onPressed: () => setState(() => _favorite = !_favorite),
                icon: Icon(
                  _favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const CartScreen()),
                  ),
                  icon: const Icon(Icons.shopping_bag_rounded),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'product-${product.id}',
                child: MockProductImage(
                  product: product,
                  photoIndex: _photoIndex,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PhotoStrip(
                    product: product,
                    selectedIndex: _photoIndex,
                    onSelect: (index) => setState(() => _photoIndex = index),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      if (product.isFeatured)
                        const Padding(
                          padding: EdgeInsets.only(left: 10, top: 2),
                          child: FeaturedBadge(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      Text(
                        product.price,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: AppColors.primaryDark),
                      ),
                      if (product.previousPrice != null)
                        Text(
                          product.previousPrice!,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      if (product.isOffer)
                        OfferBadge(label: product.discountLabel),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoPill(
                        icon: product.category.icon,
                        label: product.category.name,
                        color: product.category.color,
                      ),
                      _InfoPill(
                        icon: Icons.schedule_rounded,
                        label: product.publishedAgo,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Descripcion',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.description,
                    style: const TextStyle(
                      fontSize: 15.5,
                      height: 1.45,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Vendedor',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  _SellerCard(seller: product.seller),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () => _showMockMessage(
                      context,
                      'Reporte guardado como accion visual',
                    ),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Reportar publicacion'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              IconButton.outlined(
                onPressed: () => setState(() => _favorite = !_favorite),
                icon: Icon(
                  _favorite
                      ? Icons.favorite_rounded
                      : Icons.bookmark_border_rounded,
                ),
                color: _favorite ? AppColors.danger : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showMockMessage(
                    context,
                    'Producto agregado al carrito mock',
                  ),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Carrito'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showMockMessage(
                    context,
                    'Contacto por WhatsApp simulado',
                  ),
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF128C7E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMockMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.product,
    required this.selectedIndex,
    required this.onSelect,
  });

  final Product product;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (index) {
        final selected = index == selectedIndex;
        return Padding(
          padding: EdgeInsets.only(right: index == 2 ? 0 : 10),
          child: InkWell(
            onTap: () => onSelect(index),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 72,
              height: 58,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: MockProductImage(
                product: product,
                photoIndex: index,
                showFeaturedBadge: false,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: const Border.fromBorderSide(
          BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.seller});

  final Seller seller;

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
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              seller.avatarInitials,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        seller.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (seller.verified)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.verified_rounded,
                          color: AppColors.teal,
                          size: 18,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  seller.major,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: AppColors.gold,
                      size: 18,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${seller.rating} (${seller.reviews})',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
