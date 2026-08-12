import 'package:flutter/material.dart';

import 'app_shimmer.dart';
import 'product_card_skeleton.dart';

/// Skeleton del perfil de vendedor: identidad (avatar + nombre + carrera +
/// rating), botón de WhatsApp, bloque de horario/ubicación, íconos de
/// métodos de pago, y grid de publicaciones — mismo orden y proporciones
/// que `_SellerProfileScreenState._buildContent` en `seller_profile_screen.dart`.
class SellerProfileSkeleton extends StatelessWidget {
  const SellerProfileSkeleton({super.key});

  static const _productCount = 4;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView(
        padding: const EdgeInsets.all(18),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Center(
            child: Column(
              children: [
                // 92 = avatar de 80 + 3px de padding + 3px del anillo de
                // acento por lado. Si el anillo cambia de grosor, este número
                // cambia con él o la cabecera salta al terminar de cargar.
                const ShimmerBox(width: 92, height: 92, shape: BoxShape.circle),
                const SizedBox(height: 12),
                const ShimmerBox(width: 140, height: 19, borderRadius: 4),
                const SizedBox(height: 8),
                const ShimmerBox(width: 100, height: 14, borderRadius: 4),
                const SizedBox(height: 10),
                const ShimmerBox(width: 120, height: 16, borderRadius: 4),
                const SizedBox(height: 16),
                const ShimmerBox(
                  width: double.infinity,
                  height: 52,
                  borderRadius: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const ShimmerBox(
            width: double.infinity,
            height: 96,
            borderRadius: 16,
          ),
          const SizedBox(height: 20),
          const ShimmerBox(width: 180, height: 16, borderRadius: 4),
          const SizedBox(height: 10),
          Row(
            children: List.generate(
              4,
              (i) => Padding(
                padding: EdgeInsets.only(right: i == 3 ? 0 : 18),
                child: const ShimmerBox(
                  width: 20,
                  height: 20,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const ShimmerBox(width: 130, height: 16, borderRadius: 4),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _productCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.66,
            ),
            itemBuilder: (context, index) => const ProductCardSkeleton(),
          ),
        ],
      ),
    );
  }
}
