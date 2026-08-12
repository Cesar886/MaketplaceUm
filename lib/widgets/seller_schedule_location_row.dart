import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models.dart';
import 'badges.dart';
import 'business_hours_card.dart';
import 'static_mini_map.dart';

/// Bloque de ubicación + horario del PERFIL de un negocio (Nivel 1): una
/// fila compacta (mini mapa cuadrado de 84px + resumen del horario de hoy),
/// sin fondo, borde ni sombra de "tarjeta" — se lee como información del
/// perfil, no como un componente separado. El horario completo de la
/// semana se revela solo al tocar "Ver horario semanal". Si al negocio le
/// falta uno de los dos (horario/ubicación), se muestra solo el presente.
/// Reutilizado en el perfil de negocio.
class SellerScheduleAndLocationRow extends StatefulWidget {
  const SellerScheduleAndLocationRow({super.key, required this.seller});

  final Seller seller;

  @override
  State<SellerScheduleAndLocationRow> createState() =>
      _SellerScheduleAndLocationRowState();
}

class _SellerScheduleAndLocationRowState
    extends State<SellerScheduleAndLocationRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final seller = widget.seller;
    final hasHours = seller.businessHours.isNotEmpty;
    final hasLocation = seller.hasLocation;
    if (!hasHours && !hasLocation) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasLocation) ...[
              _MapThumbnail(seller: seller),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: hasHours
                  ? _HoursSummary(
                      seller: seller,
                      expanded: _expanded,
                      onToggle: () => setState(() => _expanded = !_expanded),
                    )
                  : _LocationOnlyLabel(seller: seller),
            ),
          ],
        ),
        if (hasHours)
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: BusinessHoursCard(seller: seller, showStatusBadge: false),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: AppAnimations.fast,
            sizeCurve: Curves.easeOut,
          ),
      ],
    );
  }
}

/// Resumen compacto: badge abierto/cerrado + horario de hoy + acción para
/// desplegar la semana completa. Sin fondo propio.
class _HoursSummary extends StatelessWidget {
  const _HoursSummary({
    required this.seller,
    required this.expanded,
    required this.onToggle,
  });

  final Seller seller;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday - 1; // 0=Lunes..6=Domingo
    final range = seller.businessHours[today];
    final isOpen = seller.isOpenNow;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Horario de hoy',
                  style: AppTypography.label(12, color: context.colors.muted),
                ),
                if (isOpen != null) ...[
                  const SizedBox(width: 8),
                  OpenStatusBadge(isOpen: isOpen),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              range != null ? '${range.open} – ${range.close}' : 'Cerrado hoy',
              style: AppTypography.heading(16, color: context.colors.ink),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  expanded ? 'Ocultar horario semanal' : 'Ver horario semanal',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 17,
                  color: context.colors.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta cuando el negocio solo tiene ubicación (sin horario): junto al
/// mini mapa, solo un enlace de texto — sin badge ni panel expandible.
class _LocationOnlyLabel extends StatelessWidget {
  const _LocationOnlyLabel({required this.seller});

  final Seller seller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ubicación',
          style: AppTypography.label(12, color: context.colors.muted),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_rounded,
              size: 16,
              color: context.colors.primary,
            ),
            SizedBox(width: 4),
            Text(
              'Ver en Maps',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.colors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Mini mapa cuadrado y pequeño (84px), esquinas redondeadas, sin borde ni
/// sombra — solo un ícono discreto de "abrir" en la esquina indica que es
/// tocable. Toda la miniatura abre Maps al tocarla.
class _MapThumbnail extends StatelessWidget {
  const _MapThumbnail({required this.seller});

  final Seller seller;

  static const _size = 84.0;
  static const _radius = 14.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: SizedBox(
        width: _size,
        height: _size,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: seller.hasLocation
                ? () => _openInMaps(seller.locationLat!, seller.locationLng!)
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StaticMiniMap(
                  lat: seller.locationLat,
                  lng: seller.locationLng,
                  height: _size,
                  borderRadius: 0,
                  showOpenInMapsButton: false,
                ),
                if (seller.hasLocation)
                  Positioned(
                    right: 5,
                    bottom: 5,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.open_in_new_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
