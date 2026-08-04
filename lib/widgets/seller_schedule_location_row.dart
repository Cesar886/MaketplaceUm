import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models.dart';
import 'business_hours_card.dart';
import 'static_mini_map.dart';

/// Fila de 2 columnas (horario | mini mapa con "Ver en Maps" superpuesto)
/// para la ubicación de PERFIL de un negocio (Nivel 1). Ambas cards son
/// cuadradas (1:1) y de igual altura. Si al negocio le falta horario o
/// ubicación, la columna presente ocupa el ancho completo — nunca se
/// muestra una columna vacía junto a la otra.
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
      // Mismo flex (ancho igual) en ambas columnas + AspectRatio 1:1: las
      // dos cards quedan cuadradas y, por tener el mismo ancho, también
      // de la misma altura entre sí — sin necesitar IntrinsicHeight.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: BusinessHoursCard(seller: seller, compact: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: _LocationCard(seller: seller),
            ),
          ),
        ],
      );
    }
    if (hasHours) return BusinessHoursCard(seller: seller);
    return AspectRatio(aspectRatio: 16 / 9, child: _LocationCard(seller: seller));
  }
}

/// Card del mapa: la imagen ocupa la card completa de esquina a esquina
/// (sin padding, con las 4 esquinas redondeadas vía [ClipRRect]) y la
/// etiqueta "Ver en Maps" flota sobre la imagen sin fondo de botón/pill —
/// solo ícono + texto blanco con un scrim de degradado sutil en la franja
/// inferior para que se lea bien sin importar el contenido del mapa debajo.
class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.seller});

  final Seller seller;

  static const _cardRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: AppShadows.soft,
      ),
      // El borde va en foregroundDecoration (no en decoration): un
      // BoxDecoration con `border` en `decoration` le agrega
      // automáticamente al Container un padding interno igual al ancho
      // del borde (`BoxDecoration.padding` = `border.dimensions`), lo que
      // encogía el mapa ~1px por lado y dejaba ver el fondo blanco del
      // Container alrededor — exactamente el "margen" reportado.
      // foregroundDecoration no aplica ese padding: el mapa ocupa el
      // Container completo y el borde se pinta nítido encima.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: context.colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_cardRadius),
        child: Stack(
          children: [
            if (seller.hasLocation)
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => _ViewInMapsLabel._openInMaps(
                      seller.locationLat!,
                      seller.locationLng!,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => StaticMiniMap(
                  lat: seller.locationLat,
                  lng: seller.locationLng,
                  height: constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : 140,
                  borderRadius: 0,
                  showOpenInMapsButton: false,
                ),
              ),
            ),
            if (seller.hasLocation) ...[
              // Scrim inferior sutil (transparente → negro tenue): los
              // tiles de OpenStreetMap suelen ser casi blancos, así que un
              // text-shadow solo no siempre alcanza para contraste
              // confiable — el degradado da una base oscura consistente
              // sin verse como un bloque/botón sólido.
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 48,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black38],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ViewInMapsLabel(
                  lat: seller.locationLat!,
                  lng: seller.locationLng!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Solo ícono + texto (sin fondo, sin pill) — se apoya en el scrim de
/// [_LocationCard] y en una sombra de texto sutil para contrastar sobre
/// cualquier mapa, no en un color de fondo propio. El tap de toda la card
/// lo maneja el `InkWell` en [_LocationCard]; esta etiqueta es solo visual.
class _ViewInMapsLabel extends StatelessWidget {
  const _ViewInMapsLabel({required this.lat, required this.lng});

  final double lat;
  final double lng;

  static const _shadow = [
    Shadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 15, color: Colors.white, shadows: _shadow),
            SizedBox(width: 6),
            Text(
              'Ver en Maps',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: _shadow,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
