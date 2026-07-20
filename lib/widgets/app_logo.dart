import 'package:flutter/material.dart';

import '../app_theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 52, this.showText = true});

  final double size;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.storefront_rounded,
            color: Colors.white,
            size: size * 0.54,
          ),
          Positioned(
            right: size * 0.12,
            bottom: size * 0.1,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: size * 0.08,
                vertical: size * 0.02,
              ),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'UM',
                style: TextStyle(
                  color: AppColors.primaryDark,
                  fontSize: size * 0.14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!showText) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mercadito UM', style: Theme.of(context).textTheme.titleLarge),
            const Text(
              'Compra y vende en campus',
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
