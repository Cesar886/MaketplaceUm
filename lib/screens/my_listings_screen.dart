import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/auto_refresh.dart';
import '../widgets/badges.dart';
import '../widgets/mock_product_image.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen>
    with AutoRefreshMixin {
  List<Product> _listings = [];
  bool _loading = true;

  /// Publicación fijada en el perfil. Vive aquí y no en el tile para que al
  /// fijar una se desmarque la anterior en la misma pasada: solo puede haber
  /// una fijada a la vez.
  String? _fijadoId;
  bool _fijando = false;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  @override
  Future<void> onAutoRefresh() => _loadListings();

  Future<void> _loadListings() async {
    final sellerId = context.read<AuthProvider>().backendSellerId;
    if (sellerId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        ApiService.getProducts(seller: sellerId),
        ApiService.getSeller(sellerId),
      ]);
      if (!mounted) return;
      setState(() {
        _listings = results[0] as List<Product>;
        _fijadoId = (results[1] as Seller).productoFijadoId;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Fija la publicación, o la desfija si ya lo estaba. El backend acepta
  /// null como "desfijar" y valida que el producto sea de quien lo manda.
  Future<void> _alternarFijado(Product product) async {
    final sellerId = context.read<AuthProvider>().backendSellerId;
    if (sellerId == null || _fijando) return;
    final messenger = ScaffoldMessenger.of(context);
    final desfijar = _fijadoId == product.id;

    setState(() => _fijando = true);
    try {
      final actualizado = await ApiService.updateSellerProfile(
        sellerId: sellerId,
        productoFijadoId: desfijar ? null : product.id,
      );
      if (!mounted) return;
      setState(() => _fijadoId = actualizado.productoFijadoId);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            desfijar ? 'listings.unpinned'.tr() : 'listings.pinned'.tr(),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('listings.pin_error'.tr())),
      );
    } finally {
      if (mounted) setState(() => _fijando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('profile.my_listings'.tr())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Row(
              children: [
                const Spacer(),
                IconButton.filled(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('listings.new_mock'.tr())),
                  ),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'listings.subtitle'.tr(),
              style: TextStyle(
                color: context.colors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            _StatsRow(listings: _listings),
            const SizedBox(height: 18),
            for (final product in _listings) ...[
              _MyListingTile(
                product: product,
                fijado: product.id == _fijadoId,
                onFijar: _fijando ? null : () => _alternarFijado(product),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.listings});

  final List<Product> listings;

  @override
  Widget build(BuildContext context) {
    final active = listings
        .where((product) => product.status == ListingStatus.active)
        .length;
    final featured = listings
        .where((product) => product.status == ListingStatus.featured)
        .length;
    final expired = listings
        .where((product) => product.status == ListingStatus.expired)
        .length;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Activas',
            value: '$active',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Destacadas',
            value: '$featured',
            color: context.colors.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Expiradas',
            value: '$expired',
            color: AppColors.danger,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyListingTile extends StatelessWidget {
  const _MyListingTile({
    required this.product,
    required this.fijado,
    required this.onFijar,
  });

  final Product product;
  final bool fijado;

  /// null mientras hay un cambio de fijado en vuelo, para no encimar dos
  /// PATCH cuyo orden de llegada no está garantizado.
  final VoidCallback? onFijar;

  @override
  Widget build(BuildContext context) {
    final status = product.status ?? ListingStatus.active;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: MockProductImage(
                  product: product,
                  height: 88,
                  showFeaturedBadge: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (fijado) ...[
                          Icon(
                            Icons.push_pin_rounded,
                            size: 15,
                            color: context.colors.accent,
                          ),
                          const SizedBox(width: 6),
                        ],
                        StatusBadge(status: status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Product.formatPrice(product.price),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.colors.accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.publishedAgo,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Fijar es la única de las tres acciones que ya toca el
              // backend de verdad; renovar y destacar siguen simuladas.
              IconButton(
                onPressed: onFijar,
                tooltip: fijado
                    ? 'listings.unpin_action'.tr()
                    : 'listings.pin_action'.tr(),
                icon: Icon(
                  fijado ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: fijado ? context.colors.accent : context.colors.muted,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _showMockMessage(context, 'listings.renew_mock'.tr()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('listings.renew'.tr()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _showMockMessage(context, 'listings.highlight_mock'.tr()),
                  icon: const Icon(Icons.star_rounded),
                  label: Text(
                    status == ListingStatus.featured
                        ? 'listings.extend'.tr()
                        : 'listings.highlight'.tr(),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMockMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
