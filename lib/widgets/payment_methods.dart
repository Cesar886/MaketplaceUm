import 'package:easy_localization/easy_localization.dart';
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

/// 'transferencia' salió del catálogo cuando la app pasó a cobrar tarjeta de
/// verdad: una transferencia bancaria manual no es algo que la app pueda
/// registrar ni conciliar. Los vendedores que la tenían guardada se migraron
/// en el backend.
///
/// 'tarjeta' es el único método que la app COBRA en lugar de solo anunciar,
/// así que es el único con un requisito: que el vendedor tenga su cuenta de
/// Mercado Pago conectada. Ver [PaymentMethodsSelector.metodosBloqueados].
const List<PaymentMethodOption> kPaymentMethodCatalog = [
  PaymentMethodOption('efectivo', 'Efectivo', Icons.payments_rounded),
  PaymentMethodOption('tarjeta', 'Tarjeta', Icons.credit_card_rounded),
  PaymentMethodOption('paypal', 'PayPal', Icons.account_balance_wallet_rounded),
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
    this.metodosBloqueados = const {},
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// Si es true, resalta el widget con un aviso de "selecciona al menos
  /// uno" — lo controla la pantalla que lo usa tras intentar avanzar/guardar
  /// con la selección vacía.
  final bool showError;

  /// Métodos que este vendedor todavía no puede aceptar, mapeados al motivo
  /// (`{'tarjeta': 'Conecta Mercado Pago para aceptar tarjetas'}`).
  ///
  /// Se muestran apagados y con el motivo debajo en vez de ocultarse: si la
  /// opción desaparece sin más, el vendedor no descubre que existe ni qué
  /// tiene que hacer para habilitarla.
  final Map<String, String> metodosBloqueados;

  void _toggle(String id, bool value) {
    if (metodosBloqueados.containsKey(id)) return;
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
              Builder(
                builder: (context) {
                  final bloqueado = metodosBloqueados.containsKey(option.id);
                  final activo = selected.contains(option.id);
                  final colorTexto = bloqueado
                      ? context.colors.muted
                      : (activo ? context.colors.primary : context.colors.ink);

                  return Opacity(
                    opacity: bloqueado ? 0.55 : 1,
                    child: FilterChip(
                      avatar: Icon(
                        bloqueado ? Icons.lock_outline_rounded : option.icon,
                        size: 18,
                        color: colorTexto,
                      ),
                      label: Text(option.label),
                      selected: activo && !bloqueado,
                      showCheckmark: true,
                      checkmarkColor: context.colors.primary,
                      selectedColor: context.colors.primary.withValues(
                        alpha: 0.12,
                      ),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorTexto,
                      ),
                      side: BorderSide(
                        color: activo && !bloqueado
                            ? context.colors.primary.withValues(alpha: 0.4)
                            : (showError
                                  ? AppColors.danger.withValues(alpha: 0.5)
                                  : context.colors.border),
                      ),
                      // onSelected a null deja el chip inerte y además hace
                      // que TalkBack/VoiceOver lo anuncien como deshabilitado.
                      onSelected: bloqueado
                          ? null
                          : (value) => _toggle(option.id, value),
                    ),
                  );
                },
              ),
          ],
        ),
        for (final entrada in metodosBloqueados.entries) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: context.colors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entrada.value,
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
        if (showError) ...[
          const SizedBox(height: 6),
          Text(
            'publish.error_payment_required'.tr(),
            style: TextStyle(color: AppColors.danger, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Muestra de métodos de pago en modo solo-lectura: ícono + texto corto,
/// sin fondo/borde/sombra, para que se lea como información (lo que el
/// vendedor acepta) y no como botones tocables. Envuelve a una segunda
/// línea con [Wrap] si no caben todos en una sola fila. Usado en el detalle
/// de producto y en el perfil de vendedor.
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
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final option in options)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(option.icon, size: 16, color: context.colors.muted),
              const SizedBox(width: 6),
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.ink,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
