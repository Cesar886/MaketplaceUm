import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_error.dart';
import '../services/api_service.dart';
import '../services/favorite_products_service.dart';
import '../services/recent_products_service.dart';
import '../services/view_cooldown.dart';
import '../widgets/badges.dart';
import '../widgets/payment_methods.dart';
import '../widgets/product_carousel_section.dart';
import '../widgets/product_comments_section.dart';
import '../widgets/product_image_carousel.dart';
import '../widgets/price_tag.dart';
import '../widgets/user_role.dart';
import '../widgets/views_counter.dart';
import 'auth/login_screen.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'publish_product_screen.dart';
import 'qr_display_screen.dart';
import 'seller_profile_screen.dart';
import 'wanted_post_screen.dart';

/// Convierte cualquier excepción en un mensaje apto para mostrar al usuario.
///
/// Se conserva el nombre porque ya lo usan varios puntos de esta pantalla,
/// pero la lógica vive en `services/api_error.dart`: la versión anterior
/// filtraba con una lista negra de nombres de excepción, que dejaba pasar
/// todo lo que no estuviera en la lista (un `HandshakeException`, o un
/// `ClientException` con la IP y el puerto dentro).
String friendlyErrorMessage(
  Object error, {
  String fallback = 'Ocurrió un error. Intenta de nuevo.',
}) {
  return mensajeDeError(error, fallback: fallback);
}

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    this.irAComentarios = false,
  });

  final Product product;

  /// Abre la pantalla ya desplazada hasta la sección de comentarios. Lo usan
  /// el deep link de la notificación push ("comentaron tu publicación") y la
  /// pestaña "Comentarios" del perfil: en ambos casos se viene POR un
  /// comentario, y aterrizar arriba del todo obliga a buscarlo a mano.
  final bool irAComentarios;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

/// Fondo oscuro y sólido para los íconos flotantes sobre el carrusel de
/// fotos — asegura contraste legible sin importar qué tan clara o
/// ruidosa sea la imagen de fondo.
final ButtonStyle _appBarIconButtonStyle = IconButton.styleFrom(
  backgroundColor: Colors.black.withValues(alpha: 0.45),
  foregroundColor: Colors.white,
);

class _ProductDetailScreenState extends State<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  late bool _favorite = widget.product.isFavorite;
  late Product _product;
  double? _lowest30d;
  late final AnimationController _priceTagController;

  /// Los dos carruseles del detalle. Llegan en la misma respuesta que el
  /// producto ([ApiService.getProductDetail]), así que comparten su estado de
  /// carga: no hay un spinner propio por sección.
  List<Product> _relacionados = const [];
  List<Product> _otrosDelVendedor = const [];
  bool _cargandoDetalle = true;

  /// Ancla de la sección de comentarios para [widget.irAComentarios].
  final GlobalKey _comentariosKey = GlobalKey();

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
    _registerViewIfNeeded();
    if (widget.irAComentarios) _desplazarAComentarios();
  }

  /// Lleva la vista hasta el hilo de comentarios.
  ///
  /// Espera un frame extra tras el primero a propósito: en el primero la
  /// sección todavía está pintando su esqueleto de carga, que es más corto
  /// que el contenido real, y el desplazamiento quedaría a media altura
  /// cuando lleguen los comentarios.
  void _desplazarAComentarios() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(AppAnimations.medium);
      if (!mounted) return;
      final contexto = _comentariosKey.currentContext;
      if (contexto == null) return;
      await Scrollable.ensureVisible(
        contexto,
        duration: AppAnimations.slow,
        curve: AppAnimations.easeOut,
        alignment: 0.1,
      );
    });
  }

  /// Registra una vista de detalle (fire-and-forget, no bloquea la UI),
  /// salvo que el cooldown local diga que ya se contó una vista reciente
  /// para esta publicación.
  Future<void> _registerViewIfNeeded() async {
    final id = widget.product.id;
    final shouldRegister = await ViewCooldown.shouldRegisterView(id);
    if (!shouldRegister) return;
    await ViewCooldown.markViewed(id);

    final auth = context.read<AuthProvider>();
    final userId = await AnonymousId.resolve(
      isLoggedIn: auth.isLoggedIn,
      backendSellerId: auth.backendSellerId,
    );

    if (widget.product.isWantedPost) {
      ApiService.registerWantedPostView(id, userId: userId);
    } else {
      ApiService.registerProductView(id, userId: userId);
    }
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
      // Un "se busca" no lleva carruseles: no hay producto parecido que
      // recomendar ni catálogo del vendedor que enseñar.
      if (mounted) setState(() => _cargandoDetalle = false);
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
      final fresh = await ApiService.getProductDetail(
        product.id,
        userId: userId,
      );
      if (!mounted) return;
      setState(() {
        _product = fresh.product;
        _relacionados = fresh.relatedProducts;
        _otrosDelVendedor = fresh.sellerOtherProducts;
        _cargandoDetalle = false;
      });
      _fetchPriceHistory();
    } catch (_) {
      // Si falla, mantenemos los datos locales y las secciones nuevas
      // simplemente no aparecen: son un extra, no el contenido de la
      // pantalla, y un mensaje de error ahí abajo solo daría ruido.
      if (mounted) setState(() => _cargandoDetalle = false);
    }
  }

  /// Abre otra publicación desde uno de los carruseles. Va como push (no
  /// como reemplazo) para que el botón de atrás devuelva a la publicación
  /// desde la que se saltó, que es de donde venía el interés.
  void _abrirPublicacion(Product otro) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(product: otro),
      ),
    );
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
                style: _appBarIconButtonStyle,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            actions: [
              IconButton.filled(
                style: _appBarIconButtonStyle,
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
                  color: _favorite ? AppColors.danger : Colors.white,
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
                    IconButton.filled(
                      style: _appBarIconButtonStyle,
                      onPressed: () => _editWantedPost(context),
                      icon: const Icon(Icons.edit_rounded),
                    )
                  else
                    const SizedBox.shrink()
                else ...[
                  IconButton.filled(
                    style: _appBarIconButtonStyle,
                    onPressed: () => _editProduct(context),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton.filled(
                    style: _appBarIconButtonStyle,
                    onPressed: () => _confirmDelete(context),
                    icon: const Icon(
                      Icons.delete_rounded,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ],
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton.filled(
                  style: _appBarIconButtonStyle,
                  onPressed: () => _shareProduct(context),
                  icon: const Icon(Icons.share_rounded),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'product-${product.id}',
                child: ProductImageCarousel(product: product),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.title,
                          style: AppTypography.heading(
                            20,
                            color: context.colors.ink,
                          ),
                        ),
                      ),
                      if (product.isFeatured)
                        const Padding(
                          padding: EdgeInsets.only(left: 10, top: 2),
                          child: FeaturedBadge(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        product.category.icon,
                        size: 13,
                        color: product.category.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        product.category.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: product.category.color,
                        ),
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
                                          color: context.colors.primary
                                              .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.edit_rounded,
                                          size: 18,
                                          color: context.colors.primary,
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
                      else
                        productStatusBadge(product),
                      if (!product.isWantedPost &&
                          product.isAvailable &&
                          product.stockQuantity != null &&
                          product.stockQuantity! > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${product.stockQuantity} en stock',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: context.colors.primary,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ViewsCounter(views: product.views, large: true),
                      ),
                    ],
                  ),
                  // ─── Descripción ──────────────────────────────────
                  const SizedBox(height: 22),
                  const _SectionHeader(
                    icon: Icons.notes_rounded,
                    label: 'Descripción',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.description,
                    style: AppTypography.body(
                      15.5,
                      color: context.colors.muted,
                    ),
                  ),
                  // ─── Extras opcionales — cambian lo que se paga ──
                  if (product.extras.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    for (final extra in product.extras) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 15,
                              color: context.colors.muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                extra.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: context.colors.ink,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            Text(
                              '+${Product.formatPrice(extra.extraPrice)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: context.colors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  // ─── Calificaciones del producto — no aplica a "se busca" ──────
                  if (!product.isWantedPost) ...[
                    const SizedBox(height: 24),
                    const _SectionHeader(
                      icon: Icons.star_rounded,
                      label: 'Califica este Producto',
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
                    // ─── También te puede interesar ─────────────────
                    // Se omite entera si no hay nada relacionado: ni el
                    // encabezado ni el espacio, para no dejar un hueco.
                    if (_cargandoDetalle || _relacionados.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      ProductCarouselSection(
                        title: 'También te puede interesar',
                        products: _relacionados,
                        loading: _cargandoDetalle,
                        onProductTap: _abrirPublicacion,
                        // El mismo padding lateral que envuelve a toda la
                        // columna del detalle: la fila lo recupera para que
                        // las tarjetas entren y salgan por el borde.
                        bleed: 18,
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  _SectionHeader(
                    icon: Icons.storefront_rounded,
                    label: product.isWantedPost ? 'Publicado por' : 'Vendedor',
                  ),
                  const SizedBox(height: 10),
                  _SellerCard(
                    seller: product.seller,
                    otherProducts: _otrosDelVendedor,
                    onProductTap: _abrirPublicacion,
                  ),
                  const SizedBox(height: 24),
                  // ─── Compartir ──────────────────────────────────────
                  const _SectionHeader(
                    icon: Icons.ios_share_rounded,
                    label: 'Compartir',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _shareProduct(context),
                          icon: const Icon(Icons.ios_share_rounded, size: 18),
                          label: const Text('Compartir enlace'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.outlined(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => QrDisplayScreen(
                              data: _qrData,
                              title: product.title,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.qr_code_rounded),
                        tooltip: 'Mostrar código QR',
                      ),
                    ],
                  ),
                  // ─── Comentarios — no aplica a "se busca" ──────────
                  // Una publicación "se busca" no es un producto que alguien
                  // haya comprado, así que un hilo de comentarios ahí no
                  // respalda a nadie; para eso ya existe responder al post.
                  if (!product.isWantedPost) ...[
                    const SizedBox(height: 28),
                    ProductCommentsSection(
                      key: _comentariosKey,
                      productId: product.id,
                      productOwnerId: product.seller.id,
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Reporte enviado. Revisaremos la publicación.',
                          ),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.muted,
                    ),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Reportar publicacion'),
                  ),
                  const SizedBox(height: 16),
                  // Resolver búsqueda (solo visible para el dueño). El estado
                  // de un producto (disponible/apartado/vendido/...) ya no se
                  // cambia aquí — el dueño lo hace desde "Editar producto";
                  // en este detalle todos ven solo el badge de solo lectura.
                  if (product.isWantedPost &&
                      context.read<AuthProvider>().backendSellerId ==
                          product.seller.id &&
                      product.wantedStatus != 'resuelta')
                    _ResolveWantedButton(onResolve: _resolveWantedPost),
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
          decoration: BoxDecoration(
            color: context.colors.surface,
            border: Border(top: BorderSide(color: context.colors.border)),
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
                color: _favorite ? AppColors.danger : context.colors.primary,
              ),
              if (_hasWhatsappContact) ...[
                const SizedBox(width: 10),
                IconButton.outlined(
                  onPressed: () => _openWhatsapp(context),
                  icon: const FaIcon(FontAwesomeIcons.whatsapp),
                  color: context.colors.accent,
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

/// Encabezado de sección consistente — ícono + label, usado en toda la
/// pantalla de detalle para que las secciones se lean como un solo sistema.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.colors.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTypography.heading(15, color: context.colors.ink),
        ),
      ],
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
      style: AppTypography.heading(18, color: context.colors.accent),
    );
  }
}

/// Badge de estado para "se busca": abierta o resuelta.
class _WantedStatusBadge extends StatelessWidget {
  const _WantedStatusBadge({required this.resolved});

  final bool resolved;

  @override
  Widget build(BuildContext context) {
    final color = resolved ? context.colors.muted : AppColors.success;
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
  const _SellerCard({
    required this.seller,
    this.otherProducts = const [],
    required this.onProductTap,
  });

  final Seller seller;

  /// Otras publicaciones activas de este vendedor. Van DENTRO de la tarjeta,
  /// no en un bloque aparte debajo: son parte de conocer al vendedor, y como
  /// sección propia competirían con "También te puede interesar" en vez de
  /// complementarla. Vacío = la tarjeta se queda exactamente como estaba.
  final List<Product> otherProducts;

  final void Function(Product product) onProductTap;

  /// El link "Ver ubicación y horarios" solo tiene sentido si el perfil del
  /// vendedor tiene algo que mostrar ahí — evita llevar a una pantalla sin
  /// nada útil que enseñar (ver [SellerProfileScreen]).
  bool get _hasScheduleOrLocation =>
      seller.businessHours.isNotEmpty || seller.hasLocation;

  @override
  Widget build(BuildContext context) {
    final isOpen = seller.isOpenNow;
    final hasReviews = seller.reviews > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: seller.id.isEmpty
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SellerProfileScreen(sellerId: seller.id),
              ),
            ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border),
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.colors.primary.withValues(alpha: 0.18),
                      width: 1.5,
                    ),
                  ),
                  child: CircleAvatar(
                    backgroundColor: context.colors.primary.withValues(
                      alpha: 0.10,
                    ),
                    child: seller.logoUrl != null && seller.logoUrl!.isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              '${ApiService.baseUrl}${seller.logoUrl}',
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Text(
                                seller.avatarInitials,
                                style: TextStyle(
                                  color: context.colors.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        : Text(
                            seller.avatarInitials,
                            style: TextStyle(
                              color: context.colors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
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
                              style: AppTypography.heading(
                                16,
                                color: context.colors.ink,
                              ),
                            ),
                          ),
                          if (seller.verified)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: InsigniaVerificada.desdeTipo(
                                seller.tipoCuenta,
                                compact: true,
                                size: 17,
                              ),
                            ),
                        ],
                      ),
                      SubtituloRol(
                        seller: seller,
                        espacioArriba: 3,
                        maxLines: 1,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: hasReviews
                                  ? context.colors.accent.withValues(
                                      alpha: 0.12,
                                    )
                                  : context.colors.surfaceMuted,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  hasReviews
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  color: hasReviews
                                      ? context.colors.accent
                                      : context.colors.muted,
                                  size: 14,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  hasReviews
                                      ? '${seller.rating.toStringAsFixed(1)} (${seller.reviews})'
                                      : 'Sin calificaciones',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                    color: hasReviews
                                        ? context.colors.ink
                                        : context.colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isOpen != null) OpenStatusBadge(isOpen: isOpen),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colors.muted.withValues(alpha: 0.6),
                  size: 22,
                ),
              ],
            ),
            if (_hasScheduleOrLocation) ...[
              const SizedBox(height: 14),
              Container(height: 1, color: context.colors.border),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: context.colors.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ver ubicación y horarios',
                    style: TextStyle(
                      color: context.colors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
            // ─── Más publicaciones de este vendedor ─────────────────
            // Sin esqueleto de carga, a diferencia de "También te puede
            // interesar": la tarjeta del vendedor ya está llena de contenido
            // real, y un shimmer dentro haría parecer que la tarjeta entera
            // sigue cargando. Aparece cuando llega la respuesta o no aparece.
            if (otherProducts.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(height: 1, color: context.colors.border),
              const SizedBox(height: 14),
              ProductCarouselSection(
                title: 'Más de ${seller.name}',
                icon: Icons.storefront_rounded,
                products: otherProducts,
                onProductTap: onProductTap,
                compact: true,
              ),
            ],
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
        color: context.colors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasReviews ? Icons.star_rounded : Icons.star_border_rounded,
            size: 15,
            color: context.colors.accent,
          ),
          if (hasReviews) ...[
            const SizedBox(width: 3),
            Text(
              rating.toStringAsFixed(1),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: context.colors.ink,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '($reviews)',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: context.colors.muted,
              ),
            ),
          ],
        ],
      ),
    );
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
          const SizedBox.shrink()
        else
          // Interactivo: permite al usuario calificar
          _InteractiveStarRating(product: product, onRated: onRated),
      ],
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
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
                      color: context.colors.accent,
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
        if (widget.product.effectivePaymentMethods.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final id in widget.product.effectivePaymentMethods)
                if (paymentMethodById(id) != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Icon(
                      paymentMethodById(id)!.icon,
                      size: 20,
                      color: context.colors.muted,
                    ),
                  ),
            ],
          ),
      ],
    );
  }
}
