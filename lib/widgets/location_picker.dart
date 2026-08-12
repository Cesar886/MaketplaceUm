import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../utils/geo_utils.dart';

/// Selector de ubicación interactivo: mapa real (OpenStreetMap vía
/// flutter_map) donde el usuario toca para colocar/mover un pin. Usado al
/// configurar la ubicación de perfil de un negocio (Nivel 1) o al elegir
/// una ubicación puntual para un producto/búsqueda (Nivel 2). Se muestra
/// como pantalla completa (push) y retorna el `LatLng` elegido al hacer pop,
/// o `null` si se cancela.
///
/// A diferencia de [StaticMiniMap], este SÍ es interactivo (pan/zoom) —
/// pensado para usarse una sola vez por flujo, no dentro de listas.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.title = 'Elige una ubicación',
  });

  final double? initialLat;
  final double? initialLng;
  final String title;

  /// Abre el selector y retorna el punto elegido, o null si se cancela.
  static Future<ll.LatLng?> open(
    BuildContext context, {
    double? initialLat,
    double? initialLng,
    String title = 'Elige una ubicación',
  }) {
    return Navigator.of(context).push<ll.LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLat: initialLat,
          initialLng: initialLng,
          title: title,
        ),
      ),
    );
  }

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late ll.LatLng _picked;
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _picked = (widget.initialLat != null && widget.initialLng != null)
        ? ll.LatLng(widget.initialLat!, widget.initialLng!)
        : const ll.LatLng(campusLat, campusLng);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _picked,
              initialZoom: 15,
              onTap: (tapPosition, point) {
                setState(() => _picked = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mercaditoum.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _picked,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.95),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Toca el mapa para colocar el pin',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(_picked),
                      child: const Text('Confirmar ubicación'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
