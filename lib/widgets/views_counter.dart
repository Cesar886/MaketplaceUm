import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/number_format.dart';

/// Ícono de ojo + conteo compacto de vistas, reutilizado en la tarjeta del
/// feed (chico, tono sutil) y en el detalle completo (más protagonismo
/// tipográfico). Sirve tanto para productos como para "se busca" — ambos
/// comparten el mismo campo `views` en [Product].
class ViewsCounter extends StatelessWidget {
  const ViewsCounter({super.key, required this.views, this.large = false});

  final int views;

  /// true = tamaño de detalle completo; false = tamaño de tarjeta de feed.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.visibility_outlined, size: large ? 16 : 12, color: color),
        const SizedBox(width: 3),
        Text(
          formatCompactNumber(views),
          style: large
              ? AppTypography.label(13, weight: FontWeight.w600, color: color)
              : AppTypography.body(11, color: color),
        ),
      ],
    );
  }
}
