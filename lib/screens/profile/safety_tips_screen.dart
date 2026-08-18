import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';

class SafetyTipsScreen extends StatelessWidget {
  const SafetyTipsScreen({super.key});

  /// Icono + clave: el texto se traduce al pintarlo (ver [_faqs] en
  /// help_screen para el mismo motivo).
  static const _tips = <(IconData, String)>[
    (Icons.badge_rounded, 'verify_profile'),
    (Icons.location_on_rounded, 'public_places'),
    (Icons.inventory_2_rounded, 'check_product'),
    (Icons.payments_rounded, 'no_prepayment'),
    (Icons.report_rounded, 'report_suspicious'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('profile.safety'.tr())),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: _tips.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final (icon, clave) = _tips[index];
            final title = 'safety.${clave}_t'.tr();
            final description = 'safety.${clave}_d'.tr();
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.colors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: context.colors.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            color: context.colors.muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
