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
/// Deliberadamente NO muestra el precio unitario: ya lo pinta la etiqueta
/// grande del detalle, unos centímetros más arriba, y repetirlo dejaba dos
/// precios compitiendo en la misma pantalla. El total solo aparece cuando la
/// cantidad pasa de 1, que es justo cuando deja de poder deducirse de ahí.
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

  /// Arranca el checkout con la cantidad elegida. La orden la crea la pantalla
  /// contenedora porque se crea contra el servidor y su ciclo de vida (y sus
  /// errores) son suyos.
  final ValueChanged<int> onPagar;

  /// Hay una orden creándose. Bloquea el botón y lo pone en carga.
  final bool pagando;

  @override
  State<PayWithCardSection> createState() => _PayWithCardSectionState();
}

class _PayWithCardSectionState extends State<PayWithCardSection> {
  VendorPaymentMethods? _metodos;

  /// Unidades a comprar. Nunca baja de 1 ni pasa de [_maximo].
  int _cantidad = 1;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Cuántas unidades se pueden pedir como mucho, o null si no hay tope.
  ///
  /// `stock_quantity` null son las publicaciones anteriores al control de
  /// stock: el backend tampoco les pone techo (ver la comprobación de stock en
  /// `/api/orders`), así que ponerlo aquí inventaría un límite que no existe.
  int? get _maximo {
    final stock = widget.product.stockQuantity;
    if (stock == null || stock <= 0) return null;
    return stock;
  }

  void _cambiarCantidad(int delta) {
    final maximo = _maximo;
    var nueva = _cantidad + delta;
    if (nueva < 1) nueva = 1;
    if (maximo != null && nueva > maximo) nueva = maximo;
    if (nueva == _cantidad) return;
    setState(() => _cantidad = nueva);
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
    // `puedeCobrarEnLaApp` y no `aceptaTarjeta`: la condición es que su
    // cuenta COBRE por algún carril, no que haya marcado el checkbox de
    // 'tarjeta' en su perfil. Es literalmente lo que exige
    // /payments/checkout, y ser más estricto aquí le esconde ventas a un
    // vendedor que sí puede cobrarlas.
    //
    // Incluye el pago con la cuenta de Mercado Pago del comprador porque hay
    // un caso —cuenta conectada cuyo OAuth no devolvió public key— en el que
    // ese es el ÚNICO carril que funciona. Mirar solo la tarjeta dejaría a
    // ese vendedor sin ninguna puerta al checkout: la opción existiría en la
    // pantalla de pago y no habría forma de llegar a ella.
    final metodos = _metodos;
    if (metodos?.puedeCobrarEnLaApp != true) return const SizedBox.shrink();

    // Prometer "tarjeta" a quien solo puede pagar con su cuenta de Mercado
    // Pago es mandarlo al checkout a encontrarse esa opción apagada.
    final soloCuentaMp = !metodos!.puedeCobrarConTarjeta;

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

          // Cantidad. Se omite cuando no hay nada que elegir —bloqueado, o una
          // única unidad en stock— porque un stepper que no se puede mover es
          // ruido: ocupa una fila para no ofrecer ninguna decisión.
          if (bloqueo == null && _maximo != 1) ...[
            _SelectorDeCantidad(
              cantidad: _cantidad,
              maximo: _maximo,
              habilitado: !widget.pagando,
              onCambiar: _cambiarCantidad,
            ),
            // El total solo cuando deja de ser deducible de la etiqueta de
            // arriba. Con una unidad sería el mismo número dos veces.
            if (_cantidad > 1) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Total',
                    style: AppTypography.body(13, color: colors.muted),
                  ),
                  const Spacer(),
                  Text(
                    Product.formatPrice(widget.product.price * _cantidad),
                    style: AppTypography.label(
                      16,
                      weight: FontWeight.w800,
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
          ],

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (widget.pagando || bloqueo != null)
                  ? null
                  : () => widget.onPagar(_cantidad),
              icon: widget.pagando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      soloCuentaMp
                          ? Icons.account_balance_wallet_rounded
                          : Icons.credit_card_rounded,
                      size: 19,
                    ),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                // Sin estilo propio: el foreground lo pone el tema del botón,
                // y fijarlo aquí lo dejaría ilegible al cambiar de swatch.
                // El label no nombra el carril: el método real se elige en el
                // checkout, y prometer "tarjeta" aquí se cae en las cuentas
                // que solo cobran con Mercado Pago. Quien sí distingue es el
                // icono, que no promete nada.
                child: Text(
                  widget.pagando ? 'Preparando tu pago…' : 'Pagar ahora',
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

/// Stepper de cantidad: "−  2  +" con la etiqueta a la izquierda.
///
/// Sin caja propia ni bordes: vive dentro de la tarjeta de pago y otra caja
/// anidada sería una frontera de más. Lo que separa esta fila del botón es el
/// aire, no una línea.
class _SelectorDeCantidad extends StatelessWidget {
  const _SelectorDeCantidad({
    required this.cantidad,
    required this.maximo,
    required this.habilitado,
    required this.onCambiar,
  });

  final int cantidad;

  /// Tope de unidades, o null si el producto no lleva control de stock.
  final int? maximo;

  final bool habilitado;
  final ValueChanged<int> onCambiar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final puedeBajar = habilitado && cantidad > 1;
    final puedeSubir = habilitado && (maximo == null || cantidad < maximo!);

    return Row(
      children: [
        Text('Cantidad', style: AppTypography.body(13, color: colors.muted)),
        const Spacer(),
        _PasoCantidad(
          icon: Icons.remove_rounded,
          tooltip: 'Quitar una unidad',
          onPressed: puedeBajar ? () => onCambiar(-1) : null,
        ),
        // Ancho fijo para que el número no empuje los botones al pasar de una
        // cifra a dos: el stepper se queda quieto mientras se toca.
        SizedBox(
          width: 44,
          child: Text(
            '$cantidad',
            textAlign: TextAlign.center,
            style: AppTypography.label(
              17,
              weight: FontWeight.w800,
              color: colors.ink,
            ),
          ),
        ),
        _PasoCantidad(
          icon: Icons.add_rounded,
          tooltip: 'Agregar una unidad',
          onPressed: puedeSubir ? () => onCambiar(1) : null,
        ),
      ],
    );
  }
}

/// Uno de los dos botones del stepper. Un disco teñido, sin borde.
class _PasoCantidad extends StatelessWidget {
  const _PasoCantidad({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activo = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        // Apagado no se pinta gris: se pinta MÁS tenue del mismo tinte. Un
        // gris nuevo mete un color que no está en la paleta.
        color: colors.accentTint.withValues(alpha: activo ? 1 : 0.4),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 18,
              color: activo
                  ? colors.accent
                  : colors.muted.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }
}
