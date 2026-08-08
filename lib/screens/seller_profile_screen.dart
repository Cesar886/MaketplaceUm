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
import '../widgets/seller_profile_skeleton.dart';
import '../widgets/seller_schedule_location_row.dart';
import '../widgets/user_role.dart';
import 'product_detail_screen.dart';

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
      setState(() {
        _seller = results[0] as Seller;
        _products = (results[1] as List<Product>)
            .where((p) => p.isAvailable)
            .toList();
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
                      backgroundColor: AppColors.teal,
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
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                backgroundImage: seller.logoUrl != null
                    ? NetworkImage(ApiService.baseUrl + seller.logoUrl!)
                    : null,
                child: seller.logoUrl == null
                    ? Text(
                        seller.avatarInitials,
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(seller.name, style: AppTypography.heading(21)),
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
                  const Icon(
                    Icons.star_rounded,
                    color: AppColors.gold,
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
              style: AppTypography.heading(16),
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
          labelStyle: AppTypography.heading(14.5),
          unselectedLabelStyle: AppTypography.body(14.5),
          labelColor: context.colors.ink,
          unselectedLabelColor: context.colors.muted,
          indicatorColor: context.colors.accent,
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Sin publicaciones activas',
                style: TextStyle(color: AppColors.muted),
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
                  return ProductCard(
                    product: product,
                    heroEnabled: false,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProductDetailScreen(product: product),
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}
