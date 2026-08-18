import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  /// Claves, no textos: la lista es `const` y `.tr()` no lo es. Se traducen
  /// al pintarlas, que además es lo que permite cambiar de idioma con la
  /// pantalla abierta.
  static const _faqs = <String>[
    'publish',
    'contact',
    'verification',
    'report',
    'support',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('help.title'.tr())),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: _faqs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final clave = _faqs[index];
            final question = 'help.${clave}_q'.tr();
            final answer = 'help.${clave}_a'.tr();
            return Container(
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.border),
              ),
              child: ExpansionTile(
                title: Text(
                  question,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    answer,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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
