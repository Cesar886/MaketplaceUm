import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'badges.dart';

/// Lista de solo lectura con el horario semanal de atención del negocio,
/// resaltando el día actual y si está abierto o cerrado en este momento.
/// Sin fondo/borde propio — vive dentro del bloque expandible de
/// [SellerScheduleAndLocationRow], no como una tarjeta independiente.
class BusinessHoursCard extends StatelessWidget {
  const BusinessHoursCard({
    super.key,
    required this.seller,
    this.showStatusBadge = true,
  });

  final Seller seller;

  /// El badge "Abierto/Cerrado" ya se muestra en el resumen compacto de
  /// [SellerScheduleAndLocationRow]; se omite aquí para no duplicarlo
  /// cuando esta lista se usa dentro del panel expandido.
  final bool showStatusBadge;

  static const _dayNames = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday - 1; // 0=Lunes..6=Domingo
    final isOpen = seller.isOpenNow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showStatusBadge && isOpen != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [OpenStatusBadge(isOpen: isOpen)],
          ),
          const SizedBox(height: 10),
        ],
        ...List.generate(7, (day) {
          final range = seller.businessHours[day];
          final isToday = day == today;
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: isToday
                ? BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _dayNames[day],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    color: isToday ? AppColors.primary : context.colors.ink,
                  ),
                ),
                Text(
                  range != null ? '${range.open}-${range.close}' : 'Cerrado',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: range != null
                        ? (isToday ? AppColors.primary : context.colors.ink)
                        : context.colors.muted,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
