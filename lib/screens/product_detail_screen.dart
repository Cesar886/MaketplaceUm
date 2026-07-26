import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/favorite_products_service.dart';
import '../services/recent_products_service.dart';
import '../widgets/badges.dart';
import '../widgets/mock_product_image.dart';
import 'auth/login_screen.dart';
import 'main_shell.dart';
import 'chat_screen.dart';
import 'home_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _photoIndex = 0;
  late bool _favorite = widget.product.isFavorite;
  late Product _product;

  Product get product => _product;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    // Registrar el producto como visto recientemente
    RecentProductsService.addRecent(widget.product.id);
    // Cargar estado de favorito desde el servicio local (usuario exclusivo)
    FavoriteProductsService.isFavorite(widget.product.id).then((isFav) {
      if (mounted) setState(() => _favorite = isFav);
    });
  }

  /// Refresca el producto desde la API y actualiza el estado local.
  Future<void> _refreshProductFromApi() async {
    try {
      final fresh = await ApiService.getProduct(product.id);
      if (!mounted) return;
      setState(() {
        _product = fresh;
      });
    } catch (_) {
      // Si falla, mantenemos los datos locales
    }
  }

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
                onPressed: () => _requireAuth(context, () async {
                  final nowFav =
                      await FavoriteProductsService.toggleFavorite(widget.product.id);
                  if (!mounted) return;
                  setState(() => _favorite = nowFav);
                }),
                icon: Icon(
                  _favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
              // Botón eliminar: solo visible si el producto es del usuario actual
              if (context.read<AuthProvider>().backendSellerId ==
                  product.seller.id)
                IconButton.filledTonal(
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete_rounded),
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton.filledTonal(
                  onPressed: () => _shareProduct(context),
                  icon: const Icon(Icons.share_rounded),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton.filledTonal(
                  onPressed: () {
                    // Navegar al tab de Favoritos (índice 3 en MainShell)
                    final shell = context.findAncestorStateOfType<MainShellState>();
                    if (shell != null) {
                      Navigator.of(context).pop();
                      shell.selectTab(3);
                    }
                  },
                  icon: const Icon(Icons.favorite_rounded),
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
                        Product.formatPrice(product.price),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: AppColors.primaryDark),
                      ),
                      if (product.previousPrice != null)
                        Text(
                          Product.formatPrice(product.previousPrice!),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      if (product.isOffer)
                        OfferBadge(label: product.discountLabel),
                      // Botón editar precio (solo dueño)
                      if (context.read<AuthProvider>().backendSellerId ==
                          product.seller.id)
                        InkWell(
                          onTap: () => _showEditPriceDialog(context),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
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
                      // Badge de disponibilidad
                      if (product.availability != null)
                        _StatusBadge(availability: product.availability!),
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
                  // ─── Extras opcionales ────────────────────────────
                  if (product.extras.isNotEmpty) ...[
                    Text(
                      'Extras opcionales',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          for (final extra in product.extras) ...[
                            Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.add_box_outlined,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    extra.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryDark.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '+${Product.formatPrice(extra.extraPrice)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryDark,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (extra != product.extras.last)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Divider(height: 1, indent: 44),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                  ],
                  // ─── Código QR + Compartir ─────────────────────────
                  Text(
                    'Compartir',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Escanea o comparte',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Muestra este código para que escaneen el producto o comparte el enlace.',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _shareProduct(context),
                                  icon: const Icon(Icons.share_rounded, size: 18),
                                  label: const Text('Compartir'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: QrImageView(
                            data: _qrData,
                            version: QrVersions.auto,
                            size: 100,
                            eyeStyle: QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: AppColors.primaryDark,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  // ─── Calificaciones del producto ─────────────────
                  _ProductRatingSection(
                    product: product,
                    isOwner: context.read<AuthProvider>().backendSellerId ==
                        product.seller.id,
                    onRated: (updatedProduct) {
                      setState(() {
                        _product = updatedProduct;
                      });
                    },
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
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Reporte enviado. Revisaremos la publicación.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Reportar publicacion'),
                  ),
                  const SizedBox(height: 16),
                  // Selector de estado (solo visible para el dueño)
                  if (context.read<AuthProvider>().backendSellerId ==
                      product.seller.id)
                    _StatusSelector(
                      productId: product.id,
                      currentStatus: product.availability,
                      onChanged: (_) => _refreshProductFromApi(),
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
                onPressed: () => _requireAuth(context, () async {
                  final nowFav =
                      await FavoriteProductsService.toggleFavorite(widget.product.id);
                  if (!mounted) return;
                  setState(() => _favorite = nowFav);
                }),
                icon: Icon(
                  _favorite
                      ? Icons.favorite_rounded
                      : Icons.bookmark_border_rounded,
                ),
                color: _favorite ? AppColors.danger : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openChat(context),
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Chat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Datos para el código QR del producto.
  String get _qrData {
    return 'mercaditoum://product/${product.id}';
  }

  /// Comparte el producto usando share_plus.
  void _shareProduct(BuildContext context) {
    final title = product.title;
    final price = Product.formatPrice(product.price);
    final seller = product.seller.name;
    final text = 'Mira este producto en Mercadito UM:\n\n$title - $price\nVendedor: $seller';
    Share.share(text);
  }

  Future<void> _openChat(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      _requireAuth(context, () => _openChat(context));
      return;
    }

    // Verificar que no sea su propio producto
    if (auth.backendSellerId == product.seller.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes enviarte un mensaje a ti mismo')),
      );
      return;
    }

    // Navegar al chat con un conversationId vacío (se creará al enviar el primer mensaje)
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

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Seguro que quieres eliminar "${product.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ApiService.deleteProduct(product.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto eliminado')),
      );
      // Volver al inicio
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar: $e')),
      );
    }
  }

  /// Si no hay sesión activa, pide login. Si sí, ejecuta [action].
  void _requireAuth(BuildContext context, VoidCallback action) {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Inicia sesión para realizar esta acción'),
          action: SnackBarAction(
            label: 'Iniciar sesión',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const LoginScreen()),
              );
            },
          ),
        ),
      );
      return;
    }
    action();
  }

  /// Muestra un diálogo para editar el precio del producto.
  Future<void> _showEditPriceDialog(BuildContext context) async {
    final priceController = TextEditingController(
      text: product.price.toStringAsFixed(product.price == product.price.floor() ? 0 : 2),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar precio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa el nuevo precio para este producto.'),
            const SizedBox(height: 16),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                prefixText: '\$ ',
                labelText: 'Nuevo precio',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(priceController.text);
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Ingresa un precio válido mayor a cero'),
                    backgroundColor: AppColors.danger,
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop(value);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    try {
      await ApiService.updateProduct(product.id, result);
      if (!mounted) return;
      // Refrescar producto completo desde la API para reflejar ofertas, badges, etc.
      await _refreshProductFromApi();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Precio actualizado correctamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
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
              fontWeight: FontWeight.w600,
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
                fontWeight: FontWeight.w700,
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
                          fontWeight: FontWeight.w700,
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
                      seller.reviews > 0
                          ? '${seller.rating.toStringAsFixed(1)} (${seller.reviews} reseña${seller.reviews == 1 ? '' : 's'})'
                          : 'Sin calificaciones',
                      style: const TextStyle(fontWeight: FontWeight.w700),
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

/// Badge que muestra el estado de disponibilidad con color.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.availability});

  final ProductAvailability availability;

  Color get _color {
    switch (availability) {
      case ProductAvailability.available:
        return const Color(0xFF2E7D32);
      case ProductAvailability.reserved:
        return const Color(0xFFE65100);
      case ProductAvailability.sold:
        return const Color(0xFFC62828);
      case ProductAvailability.negotiating:
        return const Color(0xFF1565C0);
      case ProductAvailability.paused:
        return const Color(0xFF6A1B9A);
      case ProductAvailability.unavailable:
        return const Color(0xFF546E7A);
    }
  }

  IconData get _icon {
    switch (availability) {
      case ProductAvailability.available:
        return Icons.check_circle_rounded;
      case ProductAvailability.reserved:
        return Icons.bookmark_rounded;
      case ProductAvailability.sold:
        return Icons.sell_rounded;
      case ProductAvailability.negotiating:
        return Icons.handshake_rounded;
      case ProductAvailability.paused:
        return Icons.pause_circle_rounded;
      case ProductAvailability.unavailable:
        return Icons.block_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 16, color: _color),
          const SizedBox(width: 6),
          Text(
            availability.label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Selector de estado (solo lo ve el dueño del producto).
class _StatusSelector extends StatelessWidget {
  const _StatusSelector({
    required this.productId,
    required this.currentStatus,
    required this.onChanged,
  });

  final String productId;
  final ProductAvailability? currentStatus;
  final ValueChanged<ProductAvailability> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Estado del producto',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ProductAvailability.values.map((status) {
            final selected = status == currentStatus;
            return ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconFor(status),
                    size: 18,
                    color: selected ? Colors.white : _colorFor(status),
                  ),
                  const SizedBox(width: 6),
                  Text(status.label),
                ],
              ),
              selected: selected,
              selectedColor: _colorFor(status),
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (isSelected) async {
                if (!isSelected || selected) return;
                try {
                  await ApiService.updateProductStatus(
                      productId, status.name);
                  if (context.mounted) onChanged(status);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Estado cambiado a "${status.label}"'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Color _colorFor(ProductAvailability status) {
    switch (status) {
      case ProductAvailability.available:
        return const Color(0xFF2E7D32);
      case ProductAvailability.reserved:
        return const Color(0xFFE65100);
      case ProductAvailability.sold:
        return const Color(0xFFC62828);
      case ProductAvailability.negotiating:
        return const Color(0xFF1565C0);
      case ProductAvailability.paused:
        return const Color(0xFF6A1B9A);
      case ProductAvailability.unavailable:
        return const Color(0xFF546E7A);
    }
  }

  IconData _iconFor(ProductAvailability status) {
    switch (status) {
      case ProductAvailability.available:
        return Icons.check_circle_rounded;
      case ProductAvailability.reserved:
        return Icons.bookmark_rounded;
      case ProductAvailability.sold:
        return Icons.sell_rounded;
      case ProductAvailability.negotiating:
        return Icons.handshake_rounded;
      case ProductAvailability.paused:
        return Icons.pause_circle_rounded;
      case ProductAvailability.unavailable:
        return Icons.block_rounded;
    }
  }
}

/// Sección de calificación del producto.
/// Muestra estrellas interactivas si el usuario NO es el dueño,
/// o solo el promedio (solo lectura) si SÍ es el dueño.
class _ProductRatingSection extends StatelessWidget {
  const _ProductRatingSection({
    required this.product,
    required this.isOwner,
    required this.onRated,
  });

  final Product product;
  final bool isOwner;
  final ValueChanged<Product> onRated;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Calificación',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (isOwner)
          // Solo lectura: promedio de estrellas
          Row(
            children: [
              _StarDisplay(rating: product.productRating),
              const SizedBox(width: 8),
              Text(
                product.productReviews > 0
                    ? '${product.productRating.toStringAsFixed(1)} (${product.productReviews} reseña${product.productReviews == 1 ? '' : 's'})'
                    : 'Sin calificaciones aún',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          )
        else
          // Interactivo: permite al usuario calificar
          _InteractiveStarRating(
            product: product,
            onRated: onRated,
          ),
      ],
    );
  }
}

/// Muestra estrellas rellenas según un valor decimal (solo lectura).
class _StarDisplay extends StatelessWidget {
  const _StarDisplay({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        IconData icon;
        if (rating >= starIndex) {
          icon = Icons.star_rounded;
        } else if (rating >= starIndex - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_border_rounded;
        }
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(icon, size: 22, color: AppColors.gold),
        );
      }),
    );
  }
}

/// Estrellas tocables para que el usuario califique el producto.
/// Si ya calificó antes, se pre-selecciona su calificación.
class _InteractiveStarRating extends StatefulWidget {
  const _InteractiveStarRating({
    required this.product,
    required this.onRated,
  });

  final Product product;
  final ValueChanged<Product> onRated;

  @override
  State<_InteractiveStarRating> createState() => _InteractiveStarRatingState();
}

class _InteractiveStarRatingState extends State<_InteractiveStarRating> {
  late int _selectedStars;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _selectedStars = widget.product.userRating ?? 0;
  }

  @override
  void didUpdateWidget(_InteractiveStarRating oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.product.userRating != oldWidget.product.userRating) {
      _selectedStars = widget.product.userRating ?? 0;
    }
  }

  Future<void> _rate(int stars) async {
    if (_sending || stars == _selectedStars) return; // misma calificación
    setState(() => _sending = true);

    try {
      final updated = await ApiService.rateProduct(widget.product.id, stars);
      if (!mounted) return;
      setState(() {
        _selectedStars = stars;
        _sending = false;
      });
      widget.onRated(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                final filled = starIndex <= _selectedStars;
                return GestureDetector(
                  onTap: _sending ? null : () => _rate(starIndex),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 32,
                      color: AppColors.gold,
                    ),
                  ),
                );
              }),
            ),
            if (_sending) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              _selectedStars > 0
                  ? 'Tu calificación: $_selectedStars/5'
                  : 'Toca una estrella para calificar',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 12),
            // Mostrar el promedio general
            if (widget.product.productReviews > 0)
              Text(
                '· Promedio: ${widget.product.productRating.toStringAsFixed(1)} (${widget.product.productReviews})',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
