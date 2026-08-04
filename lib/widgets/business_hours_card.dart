import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'badges.dart';

/// Tarjeta de solo lectura con el horario semanal de atención del negocio,
/// resaltando el día actual y si está abierto o cerrado en este momento.
/// Reutilizada en el perfil de negocio y en el detalle de producto.
class BusinessHoursCard extends StatelessWidget {
  const BusinessHoursCard({super.key, required this.seller, this.compact = false});

  final Seller seller;

  /// Modo compacto: fuente y espaciados reducidos para que los 7 días
  /// quepan dentro de una card cuadrada junto al mini mapa (ver
  /// seller_schedule_location_row.dart). Fuera de ese contexto se usa el
  /// tamaño cómodo por defecto.
  final bool compact;

  // Abreviados a propósito: junto al mini mapa el ancho disponible por
  // columna no alcanza para nombres completos + rango horario sin cortar
  // texto (ver seller_schedule_location_row.dart).
  static const _dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday - 1; // 0=Lunes..6=Domingo
    final isOpen = seller.isOpenNow;
    final fontSize = compact ? 10.5 : 13.0;

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isOpen != null) ...[
            OpenStatusBadge(isOpen: isOpen),
            SizedBox(height: compact ? 5 : 10),
          ],
          ...List.generate(7, (day) {
            final range = seller.businessHours[day];
            final isToday = day == today;
            return Container(
              margin: EdgeInsets.symmetric(vertical: compact ? 0.5 : 2),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 6,
                vertical: compact ? 1 : 4,
              ),
              decoration: isToday
                  ? BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(6),
                    )
                  : null,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      _dayNames[day],
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                        color: isToday
                            ? AppColors.primary
                            : context.colors.ink,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        range != null
                            ? '${range.open}-${range.close}'
                            : 'Cerrado',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                          color: range != null
                              ? (isToday ? AppColors.primary : context.colors.ink)
                              : context.colors.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
