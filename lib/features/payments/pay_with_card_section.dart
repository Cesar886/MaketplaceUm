import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models.dart';
import 'payment_models.dart';
import 'payments_api.dart';

/// Sección de pago con tarjeta dentro del detalle de un producto.
///
/// Solo existe si el vendedor puede cobrar con tarjeta AHORA MISMO, y esa es
/// la razón de que consulte al backend en vez de mirar `paymentMethods`: que
/// el vendedor anuncie "tarjeta" no significa que su cuenta de Mercado Pago
/// siga conectada. Un botón de pagar que lleva a un cobro imposible es peor
/// que no ofrecer el pago.
///
/// Cuando no aplica —vendedor sin tarjeta, cuenta caída, o la consulta
/// falló— no se dibuja NADA: ni placeholder, ni mensaje, ni el hueco. El
/// detalle de producto no es el sitio donde explicarle al comprador la
/// situación administrativa del vendedor.
class PayWithCardSection extends StatefulWidget {
  const PayWithCardSection({
    super.key,
    required this.product,
    required this.onPagar,
    required this.pagando,
    this.cargarMetodos,
  });

  final Product product;

  /// Sustituible solo para pruebas: por defecto pregunta al backend.
  final Future<VendorPaymentMethods> Function(String vendorId)? cargarMetodos;

  /// Arranca el checkout. La crea la pantalla contenedora porque la orden se
  /// crea contra el servidor y su ciclo de vida (y sus errores) son suyos.
  final VoidCallback onPagar;

  /// Hay una orden creándose. Bloquea el botón y lo pone en carga.
  final bool pagando;

  @override
  State<PayWithCardSection> createState() => _PayWithCardSectionState();
}

class _PayWithCardSectionState extends State<PayWithCardSection> {
  VendorPaymentMethods? _metodos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final cargar = widget.cargarMetodos ?? PaymentsApi.getMetodosDeVendedor;
      final metodos = await cargar(widget.product.seller.id);
      if (!mounted) return;
      setState(() => _metodos = metodos);
    } catch (_) {
      // Sin respuesta no se ofrece pagar. Es el fallo seguro: ofrecerlo y que
      // el cobro reviente después cuesta más que no haberlo ofrecido.
      if (!mounted) return;
      setState(() => _metodos = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_metodos?.aceptaTarjeta != true) return const SizedBox.shrink();

    final colors = context.colors;
    final product = widget.product;
    final enOferta = product.isOffer && product.previousPrice != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accentTintBorder),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge de encabezado: el mismo lenguaje de píldora teñida que usan
          // los badges del perfil del vendedor.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colors.accentTint,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.accentTintBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 12, color: colors.accent),
                const SizedBox(width: 5),
                Text(
                  'PAGO SEGURO',
                  style: AppTypography.label(
                    10.5,
                    weight: FontWeight.w800,
                    color: colors.accent,
                  ).copyWith(letterSpacing: 0.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // El precio final, con la misma jerarquía que en el resto de la
          // app: el precio anterior tachado cede protagonismo al que se paga.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Product.formatPrice(product.price),
                style: AppTypography.price(30, color: colors.ink),
              ),
              if (enOferta) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    Product.formatPrice(product.previousPrice!),
                    style: AppTypography.body(
                      15,
                      color: colors.muted,
                    ).copyWith(decoration: TextDecoration.lineThrough),
                  ),
                ),
                if (product.discountLabel != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        product.discountLabel!,
                        style: AppTypography.label(
                          11.5,
                          weight: FontWeight.w800,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Total a pagar con tarjeta',
            style: AppTypography.body(12.5, color: colors.muted),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: widget.pagando ? null : widget.onPagar,
              icon: widget.pagando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.credit_card_rounded, size: 19),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                // Sin estilo propio: el foreground lo pone el tema del botón,
                // y fijarlo aquí lo dejaría ilegible al cambiar de swatch.
                child: Text(
                  widget.pagando ? 'Preparando tu pago…' : 'Pagar con tarjeta',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 13, color: colors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Procesado por Mercado Pago. Tus datos de tarjeta no pasan '
                  'por Mercadito UM.',
                  style: AppTypography.body(11.5, color: colors.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
