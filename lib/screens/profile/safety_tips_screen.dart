import 'package:flutter/material.dart';

import '../../app_theme.dart';

class SafetyTipsScreen extends StatelessWidget {
  const SafetyTipsScreen({super.key});

  static const _tips = <(IconData, String, String)>[
    (
      Icons.badge_rounded,
      'Verifica el perfil antes de reunirte',
      'Revisa la calificación, las opiniones y si el vendedor tiene el badge '
          'de verificación antes de coordinar una entrega.',
    ),
    (
      Icons.location_on_rounded,
      'Reúnete en zonas públicas del campus',
      'Prefiere lugares concurridos como bibliotecas, cafeterías o entradas '
          'de edificios. Evita zonas aisladas o fuera del campus.',
    ),
    (
      Icons.inventory_2_rounded,
      'Revisa el producto antes de pagar',
      'Comprueba que el artículo coincide con la publicación y que funciona '
          'correctamente antes de completar el pago.',
    ),
    (
      Icons.payments_rounded,
      'Desconfía de pagos por adelantado fuera de la app',
      'No transfieras dinero por adelantado a cuentas externas. Realiza el '
          'intercambio en persona, producto y pago al mismo tiempo.',
    ),
    (
      Icons.report_rounded,
      'Reporta cualquier comportamiento sospechoso',
      'Si un usuario te pide datos personales, presiona para salir de la '
          'app o parece una estafa, repórtalo desde su perfil o contacta a soporte.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confianza y seguridad')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: _tips.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final (icon, title, description) = _tips[index];
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
