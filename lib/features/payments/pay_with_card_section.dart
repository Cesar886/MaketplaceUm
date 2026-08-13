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
///
/// Deliberadamente NO muestra el precio: ya lo pinta la etiqueta grande del
/// detalle, unos centímetros más arriba, y repetirlo dejaba dos precios
/// compitiendo en la misma pantalla.
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

  /// Por qué no se puede pagar ahora mismo, o null si sí se puede.
  ///
  /// Es una comprobación de cortesía sobre datos ya cargados: la de verdad la
  /// hace `/payments/checkout` contra el servidor, que es el único que no
  /// depende de la hora del dispositivo ni de un stock que pudo cambiar hace
  /// un segundo.
  String? _motivoDeBloqueo() {
    final product = widget.product;

    final stock = product.stockQuantity;
    if (stock != null && stock <= 0) {
      return 'Agotado. Este producto no tiene unidades disponibles.';
    }

    if (product.seller.isOpenNow == false) {
      return 'Cerrado ahora mismo. No se pueden procesar pagos hasta que '
          'el vendedor vuelva a abrir.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // `puedeCobrarConTarjeta` y no `aceptaTarjeta`: la condición es que su
    // cuenta COBRE, no que haya marcado el checkbox de 'tarjeta' en su
    // perfil. Es literalmente lo que exige /payments/checkout, y ser más
    // estricto aquí le esconde ventas a un vendedor que sí puede cobrarlas.
    if (_metodos?.puedeCobrarConTarjeta != true) return const SizedBox.shrink();

    final colors = context.colors;
    // Cerrado o agotado NO ocultan la sección, la deshabilitan con el motivo.
    // Si desapareciera, el comprador no entendería por qué y creería que el
    // producto no se vende; así sabe que puede volver, y cuándo.
    final bloqueo = _motivoDeBloqueo();

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

          if (bloqueo != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bloqueo,
                      style: AppTypography.body(12.5, color: colors.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (widget.pagando || bloqueo != null)
                  ? null
                  : widget.onPagar,
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
