import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_service.dart';
import '../services/favorite_products_service.dart';
import '../services/recent_products_service.dart';
import '../widgets/badges.dart';
import '../widgets/mock_product_image.dart';
import '../widgets/price_tag.dart';
import 'auth/login_screen.dart';
import 'main_shell.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'publish_product_screen.dart';
import 'qr_display_screen.dart';
import 'seller_profile_screen.dart';
import 'wanted_post_screen.dart';

/// Convierte cualquier excepción en un mensaje apto para mostrar al usuario.
/// Nunca se debe mostrar un stack trace o el texto crudo de una excepción
/// (p. ej. errores de SQL) directamente en la UI.
String friendlyErrorMessage(
  Object error, {
  String fallback = 'Ocurrió un error. Intenta de nuevo.',
}) {
  var message = error.toString();
  if (message.startsWith('Exception: ')) {
    message = message.substring('Exception: '.length);
  }
  final looksTechnical =
      message.isEmpty ||
      message.length > 140 ||
      RegExp(
        r'SQLITE|constraint|SocketException|FormatException|_TypeError|Instance of',
        caseSensitive: false,
      ).hasMatch(message);
  return looksTechnical ? fallback : message;
}

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  int _photoIndex = 0;
  late bool _favorite = widget.product.isFavorite;
  late Product _product;
  double? _lowest30d;
  late final AnimationController _priceTagController;

  Product get product => _product;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _priceTagController = AnimationController(
      vsync: this,
      duration: AppAnimations.medium,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _priceTagController.forward();
    });
    // Registrar el producto como visto recientemente
    RecentProductsService.addRecent(widget.product.id);
    // Cargar estado de favorito desde el servicio local (usuario exclusivo)
    FavoriteProductsService.isFavorite(widget.product.id).then((isFav) {
      if (mounted) setState(() => _favorite = isFav);
    });
    // Refrescar desde la API para traer datos que la lista no incluye
    // (p. ej. tu propia calificación previa), en vez de confiar solo en
    // el objeto que llegó por navegación. Esto también dispara el fetch
    // del historial de precios.
    _refreshProductFromApi();
  }

  @override
  void dispose() {
    _priceTagController.dispose();
    super.dispose();
  }

  Future<void> _fetchPriceHistory() async {
    try {
      final history = await ApiService.getPriceHistory(widget.product.id);
      final lowest = history['lowest_30d'];
      if (lowest != null && mounted) {
        setState(() {
          _lowest30d = (lowest as num).toDouble();
        });
      }
    } catch (_) {}
  }

  /// Refresca la publicación desde la API y actualiza el estado local.
  /// Para "se busca" no hay historial de precios ni rating, así que solo
  /// se refresca el post (estado abierta/resuelta, etc.).
  Future<void> _refreshProductFromApi() async {
    if (product.isWantedPost) {
      try {
        final fresh = await ApiService.getWantedPost(product.id);
        if (!mounted) return;
        setState(() => _product = Product.fromWantedPost(fresh));
      } catch (_) {
        // Si falla, mantenemos los datos locales
      }
      return;
    }
    try {
      final auth = context.read<AuthProvider>();
      final userId = await AnonymousId.resolve(
        isLoggedIn: auth.isLoggedIn,
        backendSellerId: auth.backendSellerId,
      );
      final fresh = await ApiService.getProduct(product.id, userId: userId);
      if (!mounted) return;
      setState(() {
        _product = fresh;
      });
      _fetchPriceHistory();
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
                  final nowFav = await FavoriteProductsService.toggleFavorite(
                    widget.product.id,
                  );
                  if (!mounted) return;
                  setState(() => _favorite = nowFav);
                }),
                icon: Icon(
                  _favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
              // Botones editar/eliminar: solo visibles si la publicación es del usuario
              // actual. "se busca" no tiene endpoint de borrado con esta forma (no hay
              // DELETE /api/wanted/:id), así que ese ícono solo aplica a producto; el
              // de editar sí aplica a ambos, cada uno a su propia pantalla de edición.
              if (context.read<AuthProvider>().backendSellerId ==
                  product.seller.id) ...[
                if (product.isWantedPost)
                  if (product.wantedStatus != 'resuelta')
                    IconButton.filledTonal(
                      onPressed: () => _editWantedPost(context),
                      icon: const Icon(Icons.edit_rounded),
                    )
                  else
                    const SizedBox.shrink()
                else ...[
                  IconButton.filledTonal(
                    onPressed: () => _editProduct(context),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => _confirmDelete(context),
                    icon: const Icon(Icons.delete_rounded),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                  ),
                ],
              ],
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton.filledTonal(
                  onPressed: () => _shareProduct(context),
                  icon: const Icon(Icons.share_rounded),
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
                          style: AppTypography.heading(20),
                        ),
                      ),
                      if (product.isFeatured)
                        const Padding(
                          padding: EdgeInsets.only(left: 10, top: 2),
                          child: FeaturedBadge(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (product.isWantedPost)
                    _BudgetTag(product: product)
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          // FittedBox: si el precio con descuento + botón editar no
                          // caben en el espacio que deja la columna de calificación,
                          // se achica en vez de desbordar la fila en pantallas chicas.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedPriceTag(
                                  product: product,
                                  animation: _priceTagController,
                                  large: true,
                                ),
                                // Botón editar precio (solo dueño)
                                if (context
                                        .read<AuthProvider>()
                                        .backendSellerId ==
                                    product.seller.id)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 10),
                                    child: InkWell(
                                      onTap: () =>
                                          _showEditPriceDialog(context),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.edit_rounded,
                                          size: 18,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        _CompactRating(
                          rating: product.productRating,
                          reviews: product.productReviews,
                        ),
                      ],
                    ),
                  if (!product.isWantedPost &&
                      _lowest30d != null &&
                      product.price > _lowest30d!) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.trending_down_rounded,
                          size: 14,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Mínimo en 30 días: ${Product.formatPrice(_lowest30d!)}',
                          style: AppTypography.label(
                            12,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
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
                      // Badge de estado: disponibilidad para producto, abierta/resuelta para "se busca"
                      if (product.isWantedPost)
                        _WantedStatusBadge(resolved: !product.isAvailable)
                      else if (!product.isAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.block_rounded,
                                size: 12,
                                color: AppColors.danger,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Agotado',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (product.availability != null)
                        AvailabilityBadge(availability: product.availability!),
                      if (!product.isWantedPost &&
                          product.isAvailable &&
                          product.stockQuantity != null &&
                          product.stockQuantity! > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${product.stockQuantity} en stock',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  // ─── Extras opcionales — justo debajo del precio: cambian lo que se paga ──
                  if (product.extras.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const _SectionHeader(
                      icon: Icons.add_box_rounded,
                      label: 'Extras opcionales',
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
                                    color: AppColors.primary.withValues(
                                      alpha: 0.08,
                                    ),
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
                                    color: AppColors.primaryDark.withValues(
                                      alpha: 0.06,
                                    ),
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
                  ],
                  // ─── Días disponibles ────────────────────────────
                  if (product.availableDays.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const _SectionHeader(
                      icon: Icons.event_available_rounded,
                      label: 'Días disponibles',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var day = 0; day < 7; day++)
                          _DayChip(
                            label: _dayNames[day],
                            selected: product.availableDays.contains(day),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  const _SectionHeader(
                    icon: Icons.notes_rounded,
                    label: 'Descripción',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.description,
                    style: AppTypography.body(15.5, color: AppColors.muted),
                  ),
                  // ─── Calificaciones del producto — no aplica a "se busca" ──────
                  if (!product.isWantedPost) ...[
                    const SizedBox(height: 24),
                    const _SectionHeader(
                      icon: Icons.star_rounded,
                      label: 'Calificación',
                    ),
                    const SizedBox(height: 10),
                    _ProductRatingSection(
                      product: product,
                      isOwner:
                          context.read<AuthProvider>().backendSellerId ==
                          product.seller.id,
                      onRated: (updatedProduct) {
                        setState(() {
                          _product = updatedProduct;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                  _SectionHeader(
                    icon: Icons.storefront_rounded,
                    label: product.isWantedPost ? 'Publicado por' : 'Vendedor',
                  ),
                  const SizedBox(height: 10),
                  _SellerCard(seller: product.seller),
                  const SizedBox(height: 24),
                  // ─── Código QR + Compartir ─────────────────────────
                  const _SectionHeader(
                    icon: Icons.qr_code_rounded,
                    label: 'Compartir',
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
                                  icon: const Icon(
                                    Icons.share_rounded,
                                    size: 18,
                                  ),
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
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => QrDisplayScreen(
                                    data: _qrData,
                                    title: product.title,
                                  ),
                                ),
                              );
                            },
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
                        ),
                      ],
                    ),
                  ),
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
                  // Selector de estado / resolver búsqueda (solo visible para el dueño)
                  if (context.read<AuthProvider>().backendSellerId ==
                      product.seller.id)
                    if (product.isWantedPost)
                      if (product.wantedStatus != 'resuelta')
                        _ResolveWantedButton(onResolve: _resolveWantedPost)
                      else
                        const SizedBox.shrink()
                    else
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
              // Favoritos se guarda localmente por dispositivo (sin cuenta),
              // así que no debe pedir login — ver FavoriteProductsService.
              IconButton.outlined(
                onPressed: () async {
                  final nowFav = await FavoriteProductsService.toggleFavorite(
                    widget.product.id,
                  );
                  if (!mounted) return;
                  setState(() => _favorite = nowFav);
                },
                icon: Icon(
                  _favorite
                      ? Icons.favorite_rounded
                      : Icons.bookmark_border_rounded,
                ),
                color: _favorite ? AppColors.danger : AppColors.primary,
              ),
              if (_hasWhatsappContact) ...[
                const SizedBox(width: 10),
                IconButton.outlined(
                  onPressed: () => _openWhatsapp(context),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  color: AppColors.teal,
                  tooltip: 'Contactar por WhatsApp',
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child:
                    context.read<AuthProvider>().backendSellerId ==
                        product.seller.id
                    // Es tu propio producto: no tiene sentido chatear contigo
                    // mismo, así que el CTA principal pasa a ser compartirlo.
                    ? ElevatedButton.icon(
                        onPressed: () => _shareProduct(context),
                        icon: const Icon(Icons.ios_share_rounded),
                        label: Text(
                          product.isWantedPost
                              ? 'Compartir búsqueda'
                              : 'Compartir producto',
                        ),
                      )
                    : product.isWantedPost
                    ? ElevatedButton.icon(
                        onPressed: product.isAvailable
                            ? () => _respondWantedPost(context)
                            : null,
                        icon: const Icon(Icons.chat_rounded),
                        label: Text(
                          product.isAvailable
                              ? 'Responder'
                              : 'Búsqueda resuelta',
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: product.isAvailable
                            ? () => _openChat(context)
                            : null,
                        icon: const Icon(Icons.chat_rounded),
                        label: Text(
                          product.isAvailable ? 'Chat' : 'Agotado por hoy',
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Datos para el código QR de la publicación.
  String get _qrData {
    final scheme = product.isWantedPost ? 'wanted' : 'product';
    return 'mercaditoum://$scheme/${product.id}';
  }

  /// Comparte la publicación usando share_plus.
  void _shareProduct(BuildContext context) {
    final title = product.title;
    final seller = product.seller.name;
    final text = product.isWantedPost
        ? 'Mira esta búsqueda en Mercadito UM:\n\n$title\nPublicado por: $seller'
        : 'Mira este producto en Mercadito UM:\n\n$title - ${Product.formatPrice(product.price)}\nVendedor: $seller';
    Share.share(text);
  }

  /// Contactar por WhatsApp no requiere sesión — solo necesita que el
  /// vendedor tenga un teléfono registrado.
  bool get _hasWhatsappContact =>
      (product.seller.phone ?? '').trim().isNotEmpty;

  /// Abre WhatsApp con el número del vendedor y un mensaje prellenado.
  /// No requiere sesión: es el punto de contacto principal para quien
  /// navega la app sin cuenta.
  Future<void> _openWhatsapp(BuildContext context) async {
    final rawDigits = product.seller.phone!.replaceAll(RegExp(r'[^0-9]'), '');
    if (rawDigits.isEmpty) return;
    // Heurística: números mexicanos suelen guardarse a 10 dígitos sin
    // código de país; WhatsApp lo requiere para el deep link `wa.me`.
    final phone = rawDigits.length == 10 ? '52$rawDigits' : rawDigits;
    final message = product.isWantedPost
        ? 'Hola ${product.seller.name}, vi tu busqueda de "${product.title}" ¿Aún la necesitas?.'
        : 'Hola ${product.seller.name}, me interesa "${product.title}" en Mercadito UM ¿Aún lo tienes?.';
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  Future<void> _openChat(BuildContext context) async {
    // Verificar que no sea su propio producto (solo si tiene sesión)
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn && auth.backendSellerId == product.seller.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No puedes enviarte un mensaje a ti mismo'),
        ),
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

  /// Responde a una publicación "se busca": crea/reusa la conversación en el
  /// backend (a diferencia del chat de producto, acá no se puede navegar con
  /// un conversationId vacío porque el endpoint exige crearla primero) y
  /// navega al chat ya con su id.
  Future<void> _respondWantedPost(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final userId = await AnonymousId.resolve(
      isLoggedIn: auth.isLoggedIn,
      backendSellerId: auth.backendSellerId,
    );
    try {
      final conversationId = await ApiService.respondToWantedPost(
        product.id,
        userId: userId,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(conversationId: conversationId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'No se pudo abrir el chat. Intenta de nuevo.',
            ),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  /// Marca la búsqueda como resuelta (solo el dueño).
  Future<void> _resolveWantedPost() async {
    final auth = context.read<AuthProvider>();
    final userId = await AnonymousId.resolve(
      isLoggedIn: auth.isLoggedIn,
      backendSellerId: auth.backendSellerId,
    );
    try {
      await ApiService.resolveWantedPost(product.id, userId: userId);
      if (!mounted) return;
      await _refreshProductFromApi();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marcada como resuelta')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'No se pudo marcar como resuelta. Intenta de nuevo.',
            ),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _editProduct(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PublishProductScreen(editingProduct: product),
      ),
    );
    if (saved == true) {
      await _refreshProductFromApi();
    }
  }

  /// [product] es un [Product] adaptado desde [WantedPost] (ver
  /// [Product.fromWantedPost]), así que para editar hay que reconstruir el
  /// [WantedPost] original con los campos que [WantedPostScreen] precarga.
  Future<void> _editWantedPost(BuildContext context) async {
    final editingPost = WantedPost(
      id: product.id,
      userId: product.seller.id,
      title: product.title,
      description: product.description.isEmpty ? null : product.description,
      categoryId: product.category.id,
      type: product.wantedKind ?? 'producto',
      priceMin: product.priceMin,
      priceMax: product.priceMax,
      status: product.wantedStatus ?? 'abierta',
      createdAt: '',
    );
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WantedPostScreen(editingPost: editingPost),
      ),
    );
    if (saved == true) {
      await _refreshProductFromApi();
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Producto eliminado')));
      // Volver al inicio
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'No se pudo eliminar el producto. Intenta de nuevo.',
            ),
          ),
          backgroundColor: AppColors.danger,
        ),
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
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
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
      text: product.price.toStringAsFixed(
        product.price == product.price.floor() ? 0 : 2,
      ),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'No se pudo actualizar el precio. Intenta de nuevo.',
            ),
          ),
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

/// Encabezado de sección consistente — ícono + label, usado en toda la
/// pantalla de detalle para que las secciones se lean como un solo sistema.
const _dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.10)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? AppColors.primary : AppColors.muted,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(label, style: AppTypography.heading(15)),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color == AppColors.muted ? AppColors.muted : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reemplaza el precio fijo para publicaciones "se busca": muestra el
/// presupuesto (priceMin/priceMax) si el publicante lo dio, o nada si no.
class _BudgetTag extends StatelessWidget {
  const _BudgetTag({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final min = product.priceMin;
    final max = product.priceMax;
    if (min == null && max == null) return const SizedBox.shrink();
    final String label;
    if (min != null && max != null) {
      label =
          'Presupuesto: ${Product.formatPrice(min)} - ${Product.formatPrice(max)}';
    } else if (max != null) {
      label = 'Presupuesto: hasta ${Product.formatPrice(max)}';
    } else {
      label = 'Presupuesto: desde ${Product.formatPrice(min!)}';
    }
    return Text(
      label,
      style: AppTypography.heading(18, color: AppColors.primaryDark),
    );
  }
}

/// Badge de estado para "se busca": abierta o resuelta.
class _WantedStatusBadge extends StatelessWidget {
  const _WantedStatusBadge({required this.resolved});

  final bool resolved;

  @override
  Widget build(BuildContext context) {
    final color = resolved ? AppColors.muted : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            resolved ? Icons.check_circle_rounded : Icons.search_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            resolved ? 'Resuelta' : 'Abierta',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón para que el dueño de una "se busca" la marque como resuelta.
class _ResolveWantedButton extends StatefulWidget {
  const _ResolveWantedButton({required this.onResolve});

  final Future<void> Function() onResolve;

  @override
  State<_ResolveWantedButton> createState() => _ResolveWantedButtonState();
}

class _ResolveWantedButtonState extends State<_ResolveWantedButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                await widget.onResolve();
                if (mounted) setState(() => _busy = false);
              },
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_outline_rounded),
        label: const Text('Marcar como resuelta'),
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.seller});

  final Seller seller;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: seller.id.isEmpty
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SellerProfileScreen(sellerId: seller.id),
              ),
            ),
      child: Container(
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
      ),
    );
  }
}

/// Etiqueta compacta de calificación — vive en la misma fila que el precio.
class _CompactRating extends StatelessWidget {
  const _CompactRating({required this.rating, required this.reviews});

  final double rating;
  final int reviews;

  @override
  Widget build(BuildContext context) {
    final hasReviews = reviews > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasReviews ? Icons.star_rounded : Icons.star_border_rounded,
            size: 15,
            color: AppColors.gold,
          ),
          if (hasReviews) ...[
            const SizedBox(width: 3),
            Text(
              rating.toStringAsFixed(1),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '($reviews)',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: AppColors.muted,
              ),
            ),
          ],
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
                  await ApiService.updateProductStatus(productId, status.name);
                  if (context.mounted) onChanged(status);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Estado cambiado a "${status.label}"'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          friendlyErrorMessage(
                            e,
                            fallback:
                                'No se pudo cambiar el estado. Intenta de nuevo.',
                          ),
                        ),
                        backgroundColor: AppColors.danger,
                      ),
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
        return AppColors.success;
      case ProductAvailability.reserved:
        return AppColors.orange;
      case ProductAvailability.sold:
        return AppColors.danger;
      case ProductAvailability.negotiating:
        return AppColors.primary;
      case ProductAvailability.paused:
        return AppColors.muted;
      case ProductAvailability.unavailable:
        return AppColors.muted;
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
        if (isOwner)
          // Solo lectura: promedio de estrellas
          Row(
            children: [
              _StarDisplay(rating: product.productRating),
              if (product.productReviews > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '${product.productRating.toStringAsFixed(1)} (${product.productReviews} reseña${product.productReviews == 1 ? '' : 's'})',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          )
        else
          // Interactivo: permite al usuario calificar
          _InteractiveStarRating(product: product, onRated: onRated),
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
  const _InteractiveStarRating({required this.product, required this.onRated});

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
      // Obtener userId (anónimo o de sesión)
      final auth = context.read<AuthProvider>();
      String userId;
      if (auth.isLoggedIn && auth.backendSellerId != null) {
        userId = auth.backendSellerId!;
      } else {
        userId = await AnonymousId.get();
      }

      final updated = await ApiService.rateProduct(
        widget.product.id,
        stars,
        userId: userId,
      );
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
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'No se pudo enviar tu calificación. Intenta de nuevo.',
            ),
          ),
          backgroundColor: AppColors.danger,
        ),
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

/// Transición premium para abrir pantalla de detalle: slide-up + fade con spring easing.
Route<T> springDetailRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: AppAnimations.slow,
    reverseTransitionDuration: AppAnimations.medium,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slide =
          Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: AppAnimations.spring),
          );

      final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.6, curve: Curves.easeOut),
        ),
      );

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}
