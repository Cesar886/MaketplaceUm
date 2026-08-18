import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 52,
    this.showText = true,
    this.textColor,
  });

  final double size;
  final bool showText;

  /// Color del wordmark. Por defecto hereda el `titleMedium` del tema (tinta
  /// sobre fondo claro); se pasa explícito cuando el logo va sobre una
  /// superficie de marca oscura, como la banda navy del home.
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/icon/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );

    if (!showText) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'app.name'.tr(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: textColor),
          ),
        ),
      ],
    );
  }
}
