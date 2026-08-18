import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/favorite_products_service.dart';
import '../widgets/auto_refresh.dart';
import '../widgets/badges.dart';
import '../widgets/mock_product_image.dart';
import 'auth/login_screen.dart';
import 'chat_screen.dart';
import 'product_detail_screen.dart';

/// Pantalla que muestra los productos favoritos del usuario.
/// Hace las veces de "carrito" — es exclusiva por usuario.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with AutoRefreshMixin {
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  Future<void> onAutoRefresh() => _loadFavorites();

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    try {
      final ids = await FavoriteProductsService.getFavoriteIds();
      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          _products = [];
          _loading = false;
        });
        return;
      }

      final all = await ApiService.getProducts();
      final Map<String, Product> productMap = {};
      for (final p in all) {
        productMap[p.id] = p;
      }

      final favorites = <Product>[];
      for (final id in ids) {
        final p = productMap[id];
        if (p != null) favorites.add(p);
      }

      if (!mounted) return;
      setState(() {
        _products = favorites;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openChat(BuildContext context, Product product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: '',
          productId: product.id,
          sellerId: product.seller.id,
          product: product,
        ),
      ),
    );
  }

  Future<void> _removeFavorite(String productId) async {
    await FavoriteProductsService.removeFavorite(productId);
    setState(() => _products.removeWhere((p) => p.id == productId));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (_loading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text('nav.favorites'.tr())),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.favorite_border_rounded,
                  size: 64,
                  color: context.colors.muted,
                ),
                const SizedBox(height: 20),
                Text(
                  'favorites.title'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  'favorites.login_prompt'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.colors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                    ),
                    child: Text('auth.login_button'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('nav.favorites'.tr())),
      body: _products.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadFavorites,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                itemCount: _products.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final product = _products[index];
                  return _FavoriteItemTile(
                    product: product,
                    onTap: () => _openDetail(context, product),
                    onChat: () => _openChat(context, product),
                    onRemove: () => _removeFavorite(product.id),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border_rounded,
              size: 64,
              color: context.colors.muted.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'favorites.empty'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.muted,
                fontWeight: FontWeight.w600,
                fontSize: 15,
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
        .then((_) => _loadFavorites());
  }
}

class _FavoriteItemTile extends StatelessWidget {
  const _FavoriteItemTile({
    required this.product,
    required this.onTap,
    required this.onChat,
    required this.onRemove,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onChat;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Imagen ──────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: MockProductImage(product: product),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // ─── Info ────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Product.formatPrice(product.price),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: context.colors.accent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              product.category.icon,
                              size: 14,
                              color: normalizeCategoryColor(
                                product.category.color,
                                Theme.of(context).brightness,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                product.category.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // ─── Botón quitar de favoritos ──────────────
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.favorite_rounded),
                    color: AppColors.danger,
                    tooltip: 'favorites.remove'.tr(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ─── Botones inferiores ─────────────────────────
              Row(
                children: [
                  productStatusBadge(product),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: onChat,
                    icon: const Icon(Icons.chat_rounded, size: 16),
                    label: Text('nav.chat'.tr()),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
