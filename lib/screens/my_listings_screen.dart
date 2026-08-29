import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../features/highlight/destacar_flag.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/auto_refresh.dart';
import '../widgets/badges.dart';
import '../widgets/mock_product_image.dart';
import 'profile/highlight_plans_screen.dart';
import 'publish_product_screen.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen>
    with AutoRefreshMixin {
  List<Product> _listings = [];
  bool _loading = true;
  bool _loadError = false;

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
      setState(() {
        _loading = false;
        _loadError = false;
      });
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
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
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

  Future<void> _openPublish({Product? editingProduct}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublishProductScreen(editingProduct: editingProduct),
      ),
    );
    if (mounted) _loadListings();
  }

  // TODO: Destacar publicaciones pendiente para próxima actualización - no
  // eliminar. Este navegador queda sin disparador visible mientras
  // kDestacarHabilitado sea false (el botón que lo llama está oculto); se
  // reactiva solo al poner la bandera en true
  // (ver features/highlight/destacar_flag.dart).
  Future<void> _openHighlightPlans() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HighlightPlansScreen()));
    if (mounted) _loadListings();
  }

  Future<void> _deleteListing(Product product) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('listings.delete_confirm_title'.tr()),
        content: Text(
          'listings.delete_confirm_body'.tr(
            namedArgs: {'title': product.title},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.deleteProduct(product.id);
      if (!mounted) return;
      setState(() => _listings.removeWhere((p) => p.id == product.id));
      messenger.showSnackBar(
        SnackBar(content: Text('listings.deleted'.tr())),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('listings.delete_error'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text('profile.my_listings'.tr()),
        actions: [
          IconButton(
            tooltip: 'listings.new_listing'.tr(),
            onPressed: () => _openPublish(),
            icon: const Icon(Icons.add_circle_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadListings,
                child: _loadError
                    ? _ErrorState(onRetry: _loadListings)
                    : _listings.isEmpty
                    ? _EmptyState(onCreate: () => _openPublish())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                        children: [
                          Text(
                            'listings.subtitle'.tr(),
                            style: TextStyle(
                              color: context.colors.muted,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _StatsRow(listings: _listings),
                          const SizedBox(height: 24),
                          for (final product in _listings) ...[
                            _MyListingTile(
                              product: product,
                              fijado: product.id == _fijadoId,
                              onFijar: _fijando
                                  ? null
                                  : () => _alternarFijado(product),
                              onEdit: () =>
                                  _openPublish(editingProduct: product),
                              onDelete: () => _deleteListing(product),
                              onHighlight: _openHighlightPlans,
                            ),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: context.colors.accentTint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 40,
                      color: context.colors.accent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'listings.empty_title'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'listings.empty_subtitle'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add_rounded),
                    label: Text('listings.empty_cta'.tr()),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.colors.accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 40,
                    color: context.colors.muted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'listings.load_error'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('common.retry'.tr()),
                  ),
                ],
              ),
            ),
          ),
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
            label: 'listings.stat_active'.tr(),
            value: '$active',
            icon: Icons.check_circle_rounded,
            color: AppColors.success,
          ),
        ),
        // TODO: Destacar publicaciones pendiente para próxima actualización
        // - no eliminar. El contador "Destacadas" queda oculto mientras
        // kDestacarHabilitado sea false; vuelve solo al poner la bandera en
        // true (ver features/highlight/destacar_flag.dart).
        if (kDestacarHabilitado) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'listings.stat_featured'.tr(),
              value: '$featured',
              icon: Icons.star_rounded,
              color: context.colors.accent,
            ),
          ),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'listings.stat_expired'.tr(),
            value: '$expired',
            icon: Icons.hourglass_bottom_rounded,
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
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
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
              fontSize: 12,
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
    required this.onEdit,
    required this.onDelete,
    required this.onHighlight,
  });

  final Product product;
  final bool fijado;

  /// null mientras hay un cambio de fijado en vuelo, para no encimar dos
  /// PATCH cuyo orden de llegada no está garantizado.
  final VoidCallback? onFijar;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onHighlight;

  @override
  Widget build(BuildContext context) {
    final status = product.status ?? ListingStatus.active;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 84,
                        height: 84,
                        child: MockProductImage(
                          product: product,
                          height: 84,
                          showFeaturedBadge: false,
                        ),
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
                              PopupMenuButton<_ListingAction>(
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  size: 20,
                                  color: context.colors.muted,
                                ),
                                onSelected: (action) {
                                  switch (action) {
                                    case _ListingAction.edit:
                                      onEdit();
                                      break;
                                    case _ListingAction.delete:
                                      onDelete();
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: _ListingAction.edit,
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.edit_rounded,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Text('listings.edit_action'.tr()),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: _ListingAction.delete,
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: AppColors.danger,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'common.delete'.tr(),
                                          style: const TextStyle(
                                            color: AppColors.danger,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (fijado) ...[
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 14,
                                  color: context.colors.accent,
                                ),
                                const SizedBox(width: 6),
                              ],
                              StatusBadge(status: status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            Product.formatPrice(product.price),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: context.colors.accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.publishedAgo,
                            style: TextStyle(
                              color: context.colors.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
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
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: IconButton(
                        onPressed: onFijar,
                        tooltip: fijado
                            ? 'listings.unpin_action'.tr()
                            : 'listings.pin_action'.tr(),
                        icon: Icon(
                          fijado
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          color: fijado
                              ? context.colors.accent
                              : context.colors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: Text('listings.edit_action'.tr()),
                      ),
                    ),
                    // TODO: Destacar publicaciones pendiente para próxima
                    // actualización - no eliminar. El botón
                    // "Destacar/Extender" (única entrada a los planes desde
                    // Mis publicaciones) queda oculto mientras
                    // kDestacarHabilitado sea false; vuelve solo al poner la
                    // bandera en true (ver features/highlight/destacar_flag.dart).
                    if (kDestacarHabilitado) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onHighlight,
                          icon: const Icon(Icons.star_rounded, size: 18),
                          label: Text(
                            status == ListingStatus.featured
                                ? 'listings.extend'.tr()
                                : 'listings.highlight'.tr(),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.accent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ListingAction { edit, delete }
