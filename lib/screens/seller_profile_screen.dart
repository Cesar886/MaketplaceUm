import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../widgets/badges.dart';
import '../widgets/comments_received_list.dart';
import '../widgets/payment_methods.dart';
import '../widgets/product_card.dart';
import '../widgets/profile_banner.dart';
import '../widgets/seller_profile_skeleton.dart';
import '../widgets/seller_schedule_location_row.dart';
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
        _error = 'No se pudo cargar el perfil. Intenta de nuevo.';
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
    final message =
        'Hola ${seller.name}, vi tu perfil en Mercadito UM y quiero platicarte.';
    final uri = Uri.parse(
      'https://wa.me/$normalized?text=${Uri.encodeComponent(message)}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
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
      appBar: AppBar(title: const Text('Perfil')),
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
                    icon: const FaIcon(FontAwesomeIcons.whatsapp),
                    label: const Text('Contactar por WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.accent,
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
      padding: const EdgeInsets.all(18),
      children: [
        Center(
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ProfileBanner(
                  color: colorDeBannerDeVendedor(
                    seller,
                    Theme.of(context).brightness,
                  ),
                  fadeTo: context.colors.background,
                  child: Center(
                    // Ver la nota del anillo en profile_screen: el borde va
                    // en un contenedor exterior porque el CircleAvatar
                    // recorta su hijo.
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: acentoLinea, width: 3),
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: context.colors.primary.withValues(
                          alpha: 0.12,
                        ),
                        backgroundImage: seller.logoUrl != null
                            ? NetworkImage(ApiService.baseUrl + seller.logoUrl!)
                            : null,
                        child: seller.logoUrl == null
                            ? Text(
                                seller.avatarInitials,
                                style: TextStyle(
                                  color: context.colors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 22,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    seller.name,
                    style: AppTypography.heading(21, color: context.colors.ink),
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
                        : 'Sin calificaciones',
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
              if (seller.respondeRapido || seller.rachaSemanas > 1) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (seller.respondeRapido) const RespondeRapidoBadge(),
                    // Una sola ventana no es una racha: todo el que publicó
                    // algo esta semana tendría el badge y dejaría de
                    // significar constancia.
                    if (seller.rachaSemanas > 1)
                      RachaBadge(semanas: seller.rachaSemanas),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (hasOperationalInfo) ...[
          const SizedBox(height: 28),
          if (seller.businessHours.isNotEmpty || seller.hasLocation) ...[
            SellerScheduleAndLocationRow(seller: seller),
            if (seller.paymentMethods.isNotEmpty) const SizedBox(height: 20),
          ],
          if (seller.paymentMethods.isNotEmpty) ...[
            Text(
              'Métodos de pago aceptados',
              style: AppTypography.heading(16, color: context.colors.ink),
            ),
            const SizedBox(height: 10),
            PaymentMethodsChips(methods: seller.paymentMethods),
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
        if (_tabs.index == 1)
          CommentsReceivedList(
            userId: seller.id,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
          )
        else if (_products.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Sin publicaciones activas',
                style: TextStyle(color: context.colors.muted),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _products.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: columns == 3 ? 0.72 : 0.64,
                ),
                itemBuilder: (context, index) {
                  final product = _products[index];
                  final card = ProductCard(
                    product: product,
                    heroEnabled: false,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProductDetailScreen(product: product),
                      ),
                    ),
                  );
                  if (product.id != seller.productoFijadoId) return card;
                  // La etiqueta explica por qué esta publicación va primero;
                  // sin ella el orden se lee como aleatorio. Va superpuesta
                  // y no apilada encima: la celda del grid tiene proporción
                  // fija, así que una fila extra le robaría altura a la
                  // tarjeta y podría desbordarla.
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
                            border: Border.all(color: context.colors.border),
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
      ],
    );
  }
}
