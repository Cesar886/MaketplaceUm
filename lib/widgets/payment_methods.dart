import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Catálogo fijo de métodos de pago. Íconos genéricos de Material —
/// deliberadamente NO se usan logos de marca (PayPal, Binance, etc.) para
/// evitar problemas de uso no autorizado de marcas registradas.
class PaymentMethodOption {
  const PaymentMethodOption(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

const List<PaymentMethodOption> kPaymentMethodCatalog = [
  PaymentMethodOption('efectivo', 'Efectivo', Icons.payments_rounded),
  PaymentMethodOption(
    'transferencia',
    'Transferencia',
    Icons.account_balance_rounded,
  ),
  PaymentMethodOption(
    'paypal',
    'PayPal',
    Icons.account_balance_wallet_rounded,
  ),
  PaymentMethodOption('cripto', 'Cripto', Icons.currency_bitcoin_rounded),
];

PaymentMethodOption? paymentMethodById(String id) {
  for (final option in kPaymentMethodCatalog) {
    if (option.id == id) return option;
  }
  return null;
}

/// Selector interactivo de métodos de pago: chips con ícono + nombre que se
/// marcan al tocar. Reutilizado en registro, edición de perfil y
/// publicación/edición de producto o búsqueda — un solo widget, un solo
/// lugar donde vive el catálogo y el estilo visual.
class PaymentMethodsSelector extends StatelessWidget {
  const PaymentMethodsSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.showError = false,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// Si es true, resalta el widget con un aviso de "selecciona al menos
  /// uno" — lo controla la pantalla que lo usa tras intentar avanzar/guardar
  /// con la selección vacía.
  final bool showError;

  void _toggle(String id, bool value) {
    final next = Set<String>.of(selected);
    if (value) {
      next.add(id);
    } else {
      next.remove(id);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in kPaymentMethodCatalog)
              FilterChip(
                avatar: Icon(
                  option.icon,
                  size: 18,
                  color: selected.contains(option.id)
                      ? AppColors.primary
                      : context.colors.muted,
                ),
                label: Text(option.label),
                selected: selected.contains(option.id),
                showCheckmark: true,
                checkmarkColor: AppColors.primary,
                selectedColor: AppColors.primary.withValues(alpha: 0.12),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected.contains(option.id)
                      ? AppColors.primary
                      : context.colors.ink,
                ),
                side: BorderSide(
                  color: selected.contains(option.id)
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : (showError
                            ? AppColors.danger.withValues(alpha: 0.5)
                            : context.colors.border),
                ),
                onSelected: (value) => _toggle(option.id, value),
              ),
          ],
        ),
        if (showError) ...[
          const SizedBox(height: 6),
          Text(
            'Selecciona al menos un método de pago',
            style: TextStyle(color: AppColors.danger, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Muestra de métodos de pago en modo solo-lectura: pills con ícono + texto
/// corto en una fila (wrap si no caben todos). Usado en el detalle de
/// producto y en el perfil de vendedor.
class PaymentMethodsChips extends StatelessWidget {
  const PaymentMethodsChips({super.key, required this.methods});

  final List<String> methods;

  @override
  Widget build(BuildContext context) {
    final options = methods
        .map(paymentMethodById)
        .whereType<PaymentMethodOption>()
        .toList();
    if (options.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(option.icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  option.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
