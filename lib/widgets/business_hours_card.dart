import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'badges.dart';

/// Tarjeta de solo lectura con el horario semanal de atención del negocio,
/// resaltando el día actual y si está abierto o cerrado en este momento.
/// Reutilizada en el perfil de negocio y en el detalle de producto.
class BusinessHoursCard extends StatelessWidget {
  const BusinessHoursCard({super.key, required this.seller});

  final Seller seller;

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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOpen != null) ...[
            OpenStatusBadge(isOpen: isOpen),
            const SizedBox(height: 10),
          ],
          ...List.generate(7, (day) {
            final range = seller.businessHours[day];
            final isToday = day == today;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      _dayNames[day],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                        color: isToday
                            ? AppColors.primary
                            : context.colors.ink,
                      ),
                    ),
                  ),
                  Text(
                    range != null ? '${range.open} – ${range.close}' : 'Cerrado',
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
      ),
    );
  }
}
