import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/chat_socket_service.dart';
import '../services/presence_service.dart';
import '../widgets/comments_received_list.dart';
import '../widgets/payment_methods.dart';
import '../widgets/product_card.dart';
import '../widgets/product_grid_metrics.dart';
import '../widgets/seller_profile_header.dart';
import '../widgets/seller_profile_skeleton.dart';
import '../widgets/seller_schedule_location_row.dart';
import '../widgets/social_links_row.dart';
import 'chat_screen.dart';
import 'product_detail_screen.dart';

/// El color del banner del perfil: el swatch del VENDEDOR, resuelto contra
/// [brightness], nunca el de quien mira. Es una función y no un `context.
/// colors.primary` inline a propósito — así queda testeable sin depender de
/// qué tema tenga la app de quien abre la pantalla, que es justo el bug que
/// se busca prevenir (que el banner "sangre" el acento del visitante hacia
/// el perfil ajeno).
Color colorDeBannerDeVendedor(Seller seller, Brightness brightness) =>
    AppColorSet.of(AccentSwatch.porId(seller.colorAcento), brightness).primary;

/// El tema COMPLETO del perfil público: el swatch de [seller] resuelto
/// contra [brightness].
///
/// Es el mismo criterio de [colorDeBannerDeVendedor] llevado a la pantalla
/// entera — el acento es del vendedor, el claro/oscuro de quien mira — y por
/// la misma razón vive suelto aquí: así se comprueba sin montar la pantalla.
///
/// Con [seller] todavía en null (mientras carga) cae al swatch de marca y no
/// al del visitante: el esqueleto no debe adelantar un color que a lo mejor
/// no es el que va a llegar.
ThemeData temaDeVendedor(Seller? seller, Brightness brightness) {
  final swatch = AccentSwatch.porId(seller?.colorAcento);
  return brightness == Brightness.dark
      ? AppTheme.dark(swatch)
      : AppTheme.light(swatch);
}

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

  Future<void> _openChat() async {
    final seller = _seller;
    if (seller == null) return;
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn && auth.backendSellerId == seller.id) return;

    // Busca primero si ya existe un hilo directo con este vendedor: si el
    // botón siempre abriera con conversationId vacío, un mensaje anterior
    // quedaría invisible hasta escribir uno nuevo (ver ApiService.
    // getDirectConversationId).
    String conversationId = '';
    try {
      conversationId =
          await ApiService.getDirectConversationId(seller.id) ?? '';
    } catch (_) {
      // Sin conexión o error: se abre igual con hilo vacío, como antes.
    }
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          sellerId: seller.id,
          otherUser: ChatUser.deSeller(seller),
        ),
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final seller = _seller;
    final hasPhone = (seller?.phone ?? '').trim().isNotEmpty;
    final showContactBar = !_loading && _error == null && seller != null;
    // Toda la pantalla se pinta con el acento del VENDEDOR: AppBar, botón de
    // contactar, pestañas, enlaces. Su tienda se ve igual desde cualquier
    // teléfono, y el color deja de ser un adorno del banner para ser la
    // identidad de quien la abre.
    //
    // Lo que NO se hereda es claro/oscuro: eso no es la marca de nadie sino
    // cómo mira el teléfono quien entra (y de noche, o con el ahorro de
    // batería puesto, forzar un fondo claro ajeno sería hostil). Por eso el
    // tema se arma con el brillo de quien mira y el swatch del vendedor.
    //
    // Es AnimatedTheme y no Theme por el momento de la carga: mientras no
    // hay datos el swatch es el de por defecto, y al llegar el perfil el
    // cambio de color entra como transición en vez de un parpadeo seco.
    return AnimatedTheme(
      data: temaDeVendedor(seller, Theme.of(context).brightness),
      duration: AppAnimations.medium,
      // El Builder es lo que deja que el Scaffold y todo lo de dentro lean
      // el tema recién puesto: sin él seguirían viendo el del visitante,
      // que es el que hay por encima de este widget.
      child: Builder(
        builder: (context) => _buildScaffold(
          context,
          seller: seller,
          hasPhone: hasPhone,
          showContactBar: showContactBar,
        ),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required Seller? seller,
    required bool hasPhone,
    required bool showContactBar,
  }) {
    final colores = context.colors;
    // La banda de marca se dibuja por DEBAJO de la AppBar (ver
    // extendBodyBehindAppBar): la barra deja de tener fondo propio y el
    // degradado y su brillo arrancan desde arriba del todo, sin la línea que
    // antes marcaba dónde terminaba una y empezaba la otra.
    //
    // Mientras carga, el bloque de arriba es el del esqueleto, que ocupa el
    // mismo sitio: la barra sigue sin fondo también ahí, y así al terminar de
    // cargar no da un salto de color justo mientras el cuerpo hace su
    // transición. Lo único que cambia entonces es su tinta, porque el gris
    // del esqueleto pide texto oscuro y la banda del vendedor a lo mejor no.
    //
    // Con un error sí no hay nada detrás, solo el fondo de página: ahí la
    // barra vuelve a ser opaca y normal.
    final hayBanda = _error == null;
    final colorBanda = seller == null
        ? colores.primary
        : colorDeBannerDeVendedor(seller, Theme.of(context).brightness);
    final sobreBanda = _loading || seller == null
        ? colores.ink
        : tintaSobreBanda(colorBanda);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        // La AppBar conserva siempre el color de marca del encabezado. Antes
        // se desvanecía hacia la superficie al hacer scroll, lo que hacía que
        // el header acabara blanco aunque el perfil tuviera otro acento.
        child: Builder(
          builder: (context) {
            final fondo = hayBanda ? colorBanda : colores.surface;
            final tinta = hayBanda ? sobreBanda : colores.ink;
            // El título y los íconos se pasan uno por uno y no solo con
            // foregroundColor: el AppBarTheme de la app ya trae un
            // titleTextStyle y un iconTheme con color propio (el onPrimary
            // del tema), y esos le ganan a foregroundColor. Sobre la banda
            // del VENDEDOR ese color puede no tener contraste.
            final estiloTitulo = Theme.of(context).appBarTheme.titleTextStyle;
            return AppBar(
              title: Text('nav.profile'.tr()),
              backgroundColor: fondo,
              foregroundColor: tinta,
              titleTextStyle: estiloTitulo?.copyWith(color: tinta),
              iconTheme: IconThemeData(color: tinta),
              actionsIconTheme: IconThemeData(color: tinta),
              elevation: 0,
              // Sin la sombra ni el tinte que Material le pone sola a la
              // barra al pasarle contenido por debajo: los dos volverían a
              // dibujar el borde que se está quitando.
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              // Los íconos del sistema van con la tinta de la barra: sobre
              // una banda oscura, los oscuros por defecto desaparecen.
              systemOverlayStyle: tinta.computeLuminance() > 0.5
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
            );
          },
        ),
      ),
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
      bottomNavigationBar: showContactBar
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      // El chat siempre es el contacto principal. Cuando hay
                      // WhatsApp conserva siete décimos de la fila; sin
                      // teléfono ocupa la fila completa.
                      Expanded(
                        flex: hasPhone ? 7 : 1,
                        child: ElevatedButton.icon(
                          onPressed: _openChat,
                          // Ícono y texto van en onPrimary y ya no en blanco
                          // fijo: el acento lo elige el vendedor, y con los
                          // swatches claros (durazno, celeste) el blanco sobre
                          // su color se queda sin contraste.
                          icon: Icon(
                            Icons.chat_bubble,
                            color: context.colors.onPrimary,
                          ),
                          label: Text('product.contact_chat'.tr()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.primary,
                            foregroundColor: context.colors.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      if (hasPhone) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: Tooltip(
                            message: 'product.contact_whatsapp'.tr(),
                            child: OutlinedButton(
                              onPressed: _openWhatsapp,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.colors.primary,
                                side: BorderSide(color: context.colors.primary),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const FaIcon(FontAwesomeIcons.whatsapp),
                            ),
                          ),
                        ),
                      ],
                    ],
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
        SellerProfileHeader(
          seller: seller,
          estadoConexion: estadoConexion,
          colorBanner: colorDeBannerDeVendedor(
            seller,
            Theme.of(context).brightness,
          ),
          // El hueco que la banda le reserva a lo que tiene encima: barra de
          // estado y AppBar. La banda las cubre a las dos, así que sin esto
          // el avatar nacería debajo del título.
          espacioSuperior: MediaQuery.paddingOf(context).top + kToolbarHeight,
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
              child: _AcceptedPaymentMethodsSection(
                methods: seller.paymentMethods,
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

/// Métodos de pago aceptados en el perfil público, presentados como
/// información breve sin tarjeta, fondo ni apariencia de acción tocable.
class _AcceptedPaymentMethodsSection extends StatelessWidget {
  const _AcceptedPaymentMethodsSection({required this.methods});

  final List<String> methods;

  @override
  Widget build(BuildContext context) {
    final hasValidMethod = methods.any((id) => paymentMethodById(id) != null);
    if (!hasValidMethod) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              size: 18,
              color: context.colors.muted,
            ),
            const SizedBox(width: 8),
            Text(
              'seller.payment_methods'.tr(),
              style: AppTypography.heading(16, color: context.colors.ink),
            ),
          ],
        ),
        const SizedBox(height: 10),
        PaymentMethodsChips(methods: methods),
      ],
    );
  }
}
