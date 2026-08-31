import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../services/chat_socket_service.dart';
import '../services/presence_service.dart';
import '../utils/estado_conexion.dart';
import '../widgets/badges.dart';
import '../widgets/comments_received_list.dart';
import '../widgets/payment_methods.dart';
import '../widgets/product_card.dart';
import '../widgets/product_grid_metrics.dart';
import '../widgets/profile_banner.dart';
import '../widgets/seller_profile_skeleton.dart';
import '../widgets/seller_schedule_location_row.dart';
import '../widgets/online_status_avatar.dart';
import '../widgets/social_links_row.dart';
import '../widgets/user_role.dart';
import 'product_detail_screen.dart';

/// El color del banner del perfil: el swatch del VENDEDOR, resuelto contra
/// [brightness], nunca el de quien mira. Es una función y no un `context.
/// colors.primary` inline a propósito — así queda testeable sin depender de
/// qué tema tenga la app de quien abre la pantalla, que es justo el bug que
/// se busca prevenir (que el banner "sangre" el acento del visitante hacia
/// el perfil ajeno).
Color colorDeBannerDeVendedor(Seller seller, Brightness brightness) =>
    AppColorSet.of(AccentSwatch.porId(seller.colorAcento), brightness).primary;

/// Mueve la publicación fijada al frente conservando el orden del resto.
///
/// Si el ID fijado no está en la lista, devuelve la lista intacta. El backend
/// ya verifica que el producto exista y sea del vendedor, pero aquí además
/// pudo haberse filtrado por no estar disponible (agotado, pausado), y en ese
/// caso fijarlo no debe resucitarlo en el perfil.
List<Product> ordenarConFijadoPrimero(
  List<Product> productos,
  String? fijadoId,
) {
  if (fijadoId == null) return productos;
  final indice = productos.indexWhere((p) => p.id == fijadoId);
  if (indice <= 0) return productos;
  return [
    productos[indice],
    ...productos.sublist(0, indice),
    ...productos.sublist(indice + 1),
  ];
}

/// Perfil público de un vendedor/negocio: nombre, logo, rating y sus
/// publicaciones activas. No requiere sesión — cualquiera puede verlo y
/// contactar por WhatsApp desde acá, igual que desde el detalle de producto.
class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({super.key, required this.sellerId});

  final String sellerId;

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen>
    with SingleTickerProviderStateMixin {
  Seller? _seller;
  List<Product> _products = [];
  bool _loading = true;
  String? _error;

  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    // La pestaña no vive en un TabBarView (ver _buildContent), así que el
    // contenido no se reconstruye solo al cambiarla.
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    // La conexión es única y compartida: una sala que no se abandona sigue
    // recibiendo eventos de alguien que ya nadie mira.
    ChatSocketService.instance.unsubscribePresence([widget.sellerId]);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getSeller(widget.sellerId),
        ApiService.getProducts(seller: widget.sellerId),
      ]);
      if (!mounted) return;
      final seller = results[0] as Seller;
      // Semilla + suscripción: el REST deja el estado correcto para la
      // primera pintura y el socket se encarga de los cambios mientras el
      // perfil siga abierto.
      context.read<PresenceService>().sembrar(seller.id, seller.estadoConexion);
      ChatSocketService.instance.subscribePresence([seller.id]);
      setState(() {
        _seller = seller;
        _products = ordenarConFijadoPrimero(
          (results[1] as List<Product>).where((p) => p.isAvailable).toList(),
          seller.productoFijadoId,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'seller.load_error'.tr();
        _loading = false;
      });
    }
  }

  Future<void> _openWhatsapp() async {
    final seller = _seller;
    final phone = seller?.phone?.trim();
    if (seller == null || phone == null || phone.isEmpty) return;
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final normalized = digits.length == 10 ? '52$digits' : digits;
    final message = 'seller.whatsapp_message'.tr(
      namedArgs: {'seller': seller.name},
    );
    final uri = Uri.parse(
      'https://wa.me/$normalized?text=${Uri.encodeComponent(message)}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('product.whatsapp_error'.tr())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final seller = _seller;
    final showWhatsappBar =
        !_loading &&
        _error == null &&
        seller != null &&
        (seller.phone ?? '').trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text('nav.profile'.tr())),
      body: AnimatedSwitcher(
        duration: AppAnimations.medium,
        child: _loading
            ? const SellerProfileSkeleton(key: ValueKey('seller-skeleton'))
            : _error != null
            ? Center(
                key: const ValueKey('seller-error'),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : RefreshIndicator(
                key: const ValueKey('seller-content'),
                onRefresh: _load,
                child: _buildContent(context),
              ),
      ),
      bottomNavigationBar: showWhatsappBar
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _openWhatsapp,
                    icon: const FaIcon(
                      FontAwesomeIcons.whatsapp,
                      color: Colors.white,
                    ),
                    label: Text('product.contact_whatsapp'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildContent(BuildContext context) {
    final seller = _seller!;
    // `watch` para que el punto se encienda y se apague solo mientras el
    // perfil está abierto, sin recargar.
    final estadoConexion = context.watch<PresenceService>().estadoDe(seller.id);
    // El acento de ESTA pantalla es el del vendedor que se está viendo, no
    // el de quien mira: el color es parte de su perfil, así que su tienda se
    // ve igual desde cualquier teléfono.
    final acento = AccentSwatch.porId(seller.colorAcento);
    final acentoLinea = acento.line(Theme.of(context).brightness);
    final hasOperationalInfo =
        seller.businessHours.isNotEmpty ||
        seller.hasLocation ||
        seller.paymentMethods.isNotEmpty;
    return ListView(
      // Sin padding aquí: el banner necesita llegar a las tres esquinas
      // visibles del body (izquierda, derecha, arriba) sin el margen que un
      // padding externo le metería. El resto del contenido recupera su
      // padding de 18 más abajo, ya fuera del banner.
      padding: EdgeInsets.zero,
      children: [
        SizedBox(
          width: double.infinity,
          child: ProfileBanner(
            color: colorDeBannerDeVendedor(
              seller,
              Theme.of(context).brightness,
            ),
            fadeTo: context.colors.background,
            // El fade ahora arranca DESPUÉS de los badges (ver comentario en
            // ProfileBanner): con nombre + calificación + descripción +
            // badges dentro de `child`, el color sólido ya cubre todo ese
            // bloque solo, y esta franja queda pegada justo debajo, antes de
            // la sección de mapa.
            extraFade: 40,
            // Esquinas superiores cuadradas: el banner está pegado al borde
            // superior del body, así que redondearlas ahí se vería como una
            // esquina flotando en el aire. Las inferiores sí se redondean
            // porque ahí el banner sí termina en medio del contenido.
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            child: Padding(
              // Top de 28 (no 12) para que el avatar no quede colgando del
              // borde superior del banner/AppBar: lo baja lo suficiente para
              // leerse centrado dentro del área de color.
              padding: const EdgeInsets.fromLTRB(18, 28, 18, 14),
              child: Column(
                children: [
                  OnlineStatusAvatar(
                    radius: 40,
                    iniciales: seller.avatarInitials,
                    imageUrl: seller.logoUrl != null
                        ? ApiService.baseUrl + seller.logoUrl!
                        : null,
                    enLinea: estadoConexion.enLinea,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        seller.name,
                        style: AppTypography.heading(
                          21,
                          color: context.colors.ink,
                        ),
                      ),
                      if (seller.verified) ...[
                        const SizedBox(width: 6),
                        InsigniaVerificada.desdeTipo(
                          seller.tipoCuenta,
                          compact: true,
                          size: 20,
                        ),
                      ],
                    ],
                  ),
                  SubtituloRol(
                    seller: seller,
                    espacioArriba: 6,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // "Activo hace 5 min" solo cuando NO está en línea: con el
                  // punto verde delante, repetirlo en texto sería ruido. Y si
                  // no hay dato (o es de hace más de una semana) la línea
                  // entera desaparece en vez de dejar un hueco.
                  if (!estadoConexion.enLinea) ...[
                    Builder(
                      builder: (context) {
                        final etiqueta = etiquetaUltimaActividad(
                          estadoConexion.ultimaActividad,
                        );
                        if (etiqueta == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            etiqueta,
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_rounded,
                        color: context.colors.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        seller.reviews > 0
                            ? '${seller.rating.toStringAsFixed(1)} (${seller.reviews})'
                            : 'home.no_ratings'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  if (seller.businessDescription != null &&
                      seller.businessDescription!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      seller.businessDescription!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colors.muted),
                    ),
                  ],
                  if (seller.respondeRapido ||
                      seller.rachaSemanas > 1 ||
                      seller.resolvioElEnigma) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (seller.respondeRapido) const RespondeRapidoBadge(),
                        // Una sola ventana no es una racha: todo el que
                        // publicó algo esta semana tendría el badge y
                        // dejaría de significar constancia.
                        if (seller.rachaSemanas > 1)
                          RachaBadge(semanas: seller.rachaSemanas),
                        // Va al final de la fila: es la más rara de todas y
                        // se descubre después de leer las que sí se explican
                        // solas.
                        if (seller.enigmaPosicion != null)
                          InsigniaEnigma(posicion: seller.enigmaPosicion!),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Center(child: SocialLinksRow(seller: seller)),
        if (buildSocialLinkEntries(seller).isNotEmpty)
          const SizedBox(height: 16),
        if (hasOperationalInfo) ...[
          const SizedBox(height: 28),
          if (seller.businessHours.isNotEmpty || seller.hasLocation) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SellerScheduleAndLocationRow(seller: seller),
            ),
            if (seller.paymentMethods.isNotEmpty) const SizedBox(height: 20),
          ],
          if (seller.paymentMethods.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'seller.payment_methods'.tr(),
                    style: AppTypography.heading(16, color: context.colors.ink),
                  ),
                  const SizedBox(height: 10),
                  PaymentMethodsChips(methods: seller.paymentMethods),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 24),
        // Pestañas planas: sin TabBarView a propósito. Un TabBarView necesita
        // altura acotada y obligaría a anidar un scroll dentro de este
        // ListView; así la página entera sigue siendo UN solo scroll y el
        // encabezado del vendedor se va con él, que es como se comportaba
        // antes de que hubiera pestañas.
        TabBar(
          controller: _tabs,
          labelStyle: AppTypography.heading(14.5, color: context.colors.ink),
          unselectedLabelStyle: AppTypography.body(
            14.5,
            color: context.colors.muted,
          ),
          labelColor: context.colors.ink,
          unselectedLabelColor: context.colors.muted,
          // El indicador SÍ comunica estado (qué pestaña está activa), así
          // que usa la variante de línea del swatch y no el relleno: el
          // pastel directo daría 1.4:1 sobre el fondo claro.
          indicatorColor: acentoLinea,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 2,
          dividerColor: context.colors.border.withValues(alpha: 0.5),
          tabs: const [
            Tab(text: 'Publicaciones'),
            Tab(text: 'Comentarios'),
          ],
        ),
        const SizedBox(height: 16),
        // IndexedStack y no Offstage: con Offstage, el hijo oculto reporta
        // tamaño CERO a este ListView, así que la altura total del scroll
        // saltaba entre la de la grilla de productos y la (mucho más corta)
        // lista de comentarios cada vez que se cambiaba de pestaña — eso era
        // lo que empujaba el scroll de vuelta arriba. IndexedStack sí
        // mantiene montados ambos bloques (mismo motivo que antes: no perder
        // el estado ya cargado), pero se dimensiona con la altura del hijo
        // más grande de los dos SIEMPRE, sin importar cuál esté visible, así
        // que la altura del scroll no cambia al cambiar de pestaña.
        IndexedStack(
          index: _tabs.index,
          children: [
            _products.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 24,
                    ),
                    child: Center(
                      child: Text(
                        'seller.no_listings'.tr(),
                        style: TextStyle(color: context.colors.muted),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = ProductGridMetrics.columnsFor(
                        constraints.maxWidth,
                      );
                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _products.length,
                        gridDelegate: ProductGridMetrics.delegateFor(columns),
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          final card = ProductCard(
                            product: product,
                            heroEnabled: false,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ProductDetailScreen(product: product),
                              ),
                            ),
                          );
                          if (product.id != seller.productoFijadoId) {
                            return card;
                          }
                          // La etiqueta explica por qué esta publicación va
                          // primero; sin ella el orden se lee como aleatorio.
                          // Va superpuesta y no apilada encima: la celda del
                          // grid tiene proporción fija, así que una fila
                          // extra le robaría altura a la tarjeta y podría
                          // desbordarla.
                          return Stack(
                            children: [
                              Positioned.fill(child: card),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.colors.surface,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: context.colors.border,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.push_pin_rounded,
                                        size: 11,
                                        color: acentoLinea,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Fijado',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: context.colors.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
            CommentsReceivedList(
              userId: seller.id,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Mismo padding lateral que usa el resto del perfil (nombre,
              // descripción, mapa, métodos de pago): 18, para que la lista
              // de comentarios quede alineada con el resto del contenido en
              // vez de pegarse a las orillas de la pantalla.
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
          ],
        ),
      ],
    );
  }
}
