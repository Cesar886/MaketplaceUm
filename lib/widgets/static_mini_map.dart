import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mini mapa "estático": una sola imagen de tile de OpenStreetMap (256x256)
/// con un pin superpuesto en la posición exacta de [lat]/[lng], más un
/// botón "Ver en Maps". No es un mapa interactivo (sin pan/zoom) — pensado
/// para usarse repetidas veces dentro de listas/scroll (perfil de negocio,
/// tarjeta/detalle de producto o búsqueda) sin el costo de un mapa embebido.
///
/// Si [lat]/[lng] son null, muestra un placeholder discreto (o nada, si
/// [showPlaceholderWhenEmpty] es false).
class StaticMiniMap extends StatelessWidget {
  const StaticMiniMap({
    super.key,
    required this.lat,
    required this.lng,
    this.height = 140,
    this.zoom = 15,
    this.showOpenInMapsButton = true,
    this.showPlaceholderWhenEmpty = true,
    this.borderRadius = 12,
  });

  final double? lat;
  final double? lng;
  final double height;
  final int zoom;
  final bool showOpenInMapsButton;
  final bool showPlaceholderWhenEmpty;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (lat == null || lng == null) {
      if (!showPlaceholderWhenEmpty) return const SizedBox.shrink();
      return _EmptyPlaceholder(height: height, borderRadius: borderRadius);
    }

    final tile = _TilePixel.fromLatLng(lat!, lng!, zoom);
    final tileUrl =
        'https://tile.openstreetmap.org/$zoom/${tile.xTile}/${tile.yTile}.png';
    const tileSize = 256.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: ClipRect(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // El tile nativo (256x256) casi siempre es más chico que
                    // el contenedor (que ocupa el ancho completo de la
                    // pantalla) — se escala como BoxFit.cover para llenarlo
                    // por completo, en vez de dejarlo "flotando" con franjas
                    // de color sólido a los lados.
                    final scale = max(
                      constraints.maxWidth / tileSize,
                      constraints.maxHeight / tileSize,
                    );
                    final displaySize = tileSize * scale;
                    // Desplaza el tile escalado para que el punto exacto
                    // lat/lng quede centrado en el contenedor, sin importar
                    // el tamaño de este.
                    final left = constraints.maxWidth / 2 - tile.dxFraction * displaySize;
                    final top = constraints.maxHeight / 2 - tile.dyFraction * displaySize;
                    return Stack(
                      children: [
                        Positioned(
                          left: left,
                          top: top,
                          width: displaySize,
                          height: displaySize,
                          child: Image(
                            image: NetworkImage(
                              tileUrl,
                              headers: const {
                                'User-Agent': 'MercaditoUM/1.0 (Flutter app)',
                              },
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 18),
                            child: Icon(Icons.location_on, color: Colors.red, size: 34),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (showOpenInMapsButton)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: InkWell(
                onTap: () => _openInMaps(lat!, lng!),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('Ver en Maps', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
        ],
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

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder({required this.height, required this.borderRadius});

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.location_off_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        size: 28,
      ),
    );
  }
}

/// Conversión lat/lng -> tile OSM (slippy map) + posición fraccional
/// dentro de ese tile, para poder alinear el `Image` de forma que el pin
/// (siempre centrado en pantalla) caiga exactamente sobre la coordenada.
class _TilePixel {
  _TilePixel({
    required this.xTile,
    required this.yTile,
    required this.dxFraction,
    required this.dyFraction,
  });

  final int xTile;
  final int yTile;
  final double dxFraction; // 0..1 dentro del tile
  final double dyFraction; // 0..1 dentro del tile

  factory _TilePixel.fromLatLng(double lat, double lng, int zoom) {
    final n = pow(2, zoom).toDouble();
    final latRad = lat * pi / 180;
    final worldX = (lng + 180) / 360 * n;
    final worldY =
        (1 - (log(tan(latRad) + 1 / cos(latRad)) / pi)) / 2 * n;

    final xTile = worldX.floor();
    final yTile = worldY.floor();

    return _TilePixel(
      xTile: xTile,
      yTile: yTile,
      dxFraction: worldX - xTile,
      dyFraction: worldY - yTile,
    );
  }
}
