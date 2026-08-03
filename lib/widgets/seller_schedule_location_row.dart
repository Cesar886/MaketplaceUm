import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../utils/geo_utils.dart';
import 'business_hours_card.dart';
import 'static_mini_map.dart';

/// Fila de 2 columnas (horario | mini mapa + "Ver en Maps" + distancia al
/// campus) para la ubicación de PERFIL de un negocio (Nivel 1). Si al
/// negocio le falta horario o ubicación, la columna presente ocupa el
/// ancho completo — nunca se muestra una columna vacía junto a la otra.
/// Reutilizado en el perfil de negocio y en el detalle de producto.
class SellerScheduleAndLocationRow extends StatelessWidget {
  const SellerScheduleAndLocationRow({super.key, required this.seller});

  final Seller seller;

  @override
  Widget build(BuildContext context) {
    final hasHours = seller.businessHours.isNotEmpty;
    final hasLocation = seller.hasLocation;
    if (!hasHours && !hasLocation) return const SizedBox.shrink();

    if (hasHours && hasLocation) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: BusinessHoursCard(seller: seller)),
          const SizedBox(width: 12),
          Expanded(child: _LocationColumn(seller: seller)),
        ],
      );
    }
    if (hasHours) return BusinessHoursCard(seller: seller);
    return _LocationColumn(seller: seller);
  }
}

class _LocationColumn extends StatelessWidget {
  const _LocationColumn({required this.seller});

  final Seller seller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaticMiniMap(lat: seller.locationLat, lng: seller.locationLng),
        if (seller.hasLocation) ...[
          const SizedBox(height: 6),
          Text(
            campusDistanceLabel(seller.locationLat!, seller.locationLng!),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.muted,
            ),
          ),
        ],
      ],
    );
  }
}
