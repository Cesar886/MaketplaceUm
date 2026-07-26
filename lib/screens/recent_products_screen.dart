import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../services/recent_products_service.dart';
import '../widgets/mock_product_image.dart';
import 'product_detail_screen.dart';

/// Pantalla que muestra los últimos productos que el usuario ha visto.
class RecentProductsScreen extends StatefulWidget {
  const RecentProductsScreen({super.key});

  @override
  State<RecentProductsScreen> createState() => _RecentProductsScreenState();
}

class _RecentProductsScreenState extends State<RecentProductsScreen> {
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecentProducts();
  }

  Future<void> _loadRecentProducts() async {
    setState(() => _loading = true);
    try {
      final ids = await RecentProductsService.getRecentIds();
      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          _products = [];
          _loading = false;
        });
        return;
      }

      // Cargar todos los productos y filtrar por IDs recientes
      final all = await ApiService.getProducts();
      final Map<String, Product> productMap = {};
      for (final p in all) {
        productMap[p.id] = p;
      }

      final recent = <Product>[];
      for (final id in ids) {
        final p = productMap[id];
        if (p != null) recent.add(p);
      }

      if (!mounted) return;
      setState(() {
        _products = recent;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar historial'),
        content: const Text(
          '¿Eliminar todos los productos vistos recientemente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await RecentProductsService.clearAll();
    if (!mounted) return;
    setState(() => _products = []);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Historial limpiado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vistos recientemente'),
        actions: [
          if (_products.isNotEmpty)
            IconButton(
              onPressed: _clearHistory,
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Limpiar historial',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 64,
                          color: AppColors.muted.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Aún no has visto ningún producto.\n¡Explora el mercado!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRecentProducts,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                    itemCount: _products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final product = _products[index];
                      return _RecentProductTile(
                        product: product,
                        onTap: () => _openDetail(context, product),
                      );
                    },
                  ),
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
}

class _RecentProductTile extends StatelessWidget {
  const _RecentProductTile({
    required this.product,
    required this.onTap,
  });

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // ─── Imagen del producto ─────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: MockProductImage(product: product),
                ),
              ),
              const SizedBox(width: 14),
              // ─── Info ────────────────────────────────────────
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          product.category.icon,
                          size: 14,
                          color: product.category.color,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            product.category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
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
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
