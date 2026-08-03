import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../widgets/product_card.dart';
import '../widgets/seller_schedule_location_row.dart';
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

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  Seller? _seller;
  List<Product> _products = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : RefreshIndicator(onRefresh: _load, child: _buildContent(context)),
    );
  }

  Widget _buildContent(BuildContext context) {
    final seller = _seller!;
    final hasWhatsapp = (seller.phone ?? '').trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (seller.isBusiness &&
            (seller.businessHours.isNotEmpty || seller.hasLocation)) ...[
          SellerScheduleAndLocationRow(seller: seller),
          const SizedBox(height: 20),
        ],
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
                  Text(seller.name, style: AppTypography.heading(19)),
                  if (seller.verified) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified_rounded,
                      color: AppColors.teal,
                      size: 20,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                seller.major,
                style: const TextStyle(
                  color: AppColors.muted,
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
                        ? '${seller.rating.toStringAsFixed(1)} (${seller.reviews} reseña${seller.reviews == 1 ? '' : 's'})'
                        : 'Sin calificaciones',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (seller.businessDescription != null &&
                  seller.businessDescription!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  seller.businessDescription!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
              if (hasWhatsapp) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openWhatsapp,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Contactar por WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Publicaciones', style: AppTypography.heading(16)),
        const SizedBox(height: 12),
        if (_products.isEmpty)
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _products.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.66,
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
          ),
      ],
    );
  }
}
