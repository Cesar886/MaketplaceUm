import 'package:flutter/material.dart';

import 'app_shimmer.dart';
import 'product_card_skeleton.dart';
import 'product_grid_metrics.dart';
import 'seller_profile_header.dart';

/// Skeleton del perfil de vendedor: la cabecera (la banda de color con el
/// avatar, nombre, rol y rating dentro), botón de WhatsApp, bloque de
/// horario/ubicación, íconos de métodos de pago, y grid de publicaciones —
/// mismo orden y
/// proporciones que [SellerProfileHeader] y
/// `_SellerProfileScreenState._buildContent` en `seller_profile_screen.dart`.
class SellerProfileSkeleton extends StatelessWidget {
  const SellerProfileSkeleton({super.key});

  static const _productCount = 4;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Misma geometría que SellerProfileHeader: la banda de marca
          // cubre avatar, nombre, rol y calificación, así que aquí es un solo
          // bloque de ese alto. Va sin barras dentro a propósito: el shimmer
          // tiñe todo el subárbol de una vez, y unas barras encima de la
          // banda se leerían como manchas y no como texto por llegar.
          //
          // El 223 es la suma de la cabecera real (22 de aire + 92 de avatar
          // + 14 + 22 de nombre + 5 + 13 de rol + 12 + 17 de métricas + 26 de
          // aire abajo). Si ahí cambian las medidas, cambia aquí o la
          // cabecera salta al terminar de cargar.
          //
          // Se le suma lo que mide la barra de estado más la AppBar porque la
          // pantalla dibuja el body por detrás de las dos (`extendBodyBehind
          // AppBar`), igual que la cabecera real.
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(26),
              bottomRight: Radius.circular(26),
            ),
            child: ShimmerBox(
              width: double.infinity,
              height: 223 + MediaQuery.paddingOf(context).top + kToolbarHeight,
              borderRadius: 0,
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: ShimmerBox(
              width: double.infinity,
              height: 52,
              borderRadius: 12,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  // El grid real de seller_profile_screen usa estas mismas
                  // medidas; leerlas de la constante es lo que evita que el
                  // skeleton vuelva a quedarse atrás (se había quedado en 0.66
                  // cuando el grid ya iba en 0.62, y las tarjetas saltaban al
                  // terminar de cargar).
                  gridDelegate: ProductGridMetrics.delegateFor(2),
                  itemBuilder: (context, index) => const ProductCardSkeleton(),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
