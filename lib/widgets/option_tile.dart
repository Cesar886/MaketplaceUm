import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Fila de menú con icono, título, subtítulo y chevron.
///
/// La comparten el perfil y configuración: son la misma lista de opciones
/// partida en dos pantallas, así que el estilo vive en un solo lugar para
/// que no se desincronicen.
class OptionTile extends StatelessWidget {
  const OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.destructivo = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// Reemplaza el chevron. Sirve para las filas que muestran un valor en vez
  /// de navegar (el idioma actual, la versión de la app).
  final Widget? trailing;

  /// Pinta la fila en rojo. Reservado para acciones que no se deshacen, como
  /// eliminar la cuenta.
  final bool destructivo;

  @override
  Widget build(BuildContext context) {
    final color = destructivo ? AppColors.danger : context.colors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: destructivo ? AppColors.danger : context.colors.ink,
          ),
        ),
        subtitle: Text(subtitle, style: TextStyle(color: context.colors.muted)),
        trailing:
            trailing ??
            Icon(Icons.chevron_right_rounded, color: context.colors.muted),
        onTap:
            onTap ??
            () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(
              SnackBar(
                content: Text(
                  'common.not_implemented'.tr(namedArgs: {'title': title}),
                ),
              ),
            ),
      ),
    );
  }
}
