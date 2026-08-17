import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/payment_methods.dart';
import 'payment_models.dart';
import 'payments_api.dart';

/// Sección de pago del detalle de un producto.
///
/// SIEMPRE se dibuja (mientras la compra tenga sentido: ver
/// `_puedeOfrecerseElPago` en el detalle), y lo que cambia es qué promete:
///
/// * El vendedor cobra en la app AHORA → botón "Pagar ahora".
/// * El vendedor no tiene cuenta de cobros conectada → se explica que el pago
///   se acuerda con él y se listan los métodos que anuncia. Sin botón de
///   pagar: prometer un cobro imposible es peor que no ofrecerlo.
/// * La consulta falló → se dice justo eso, con un reintento. "No pude
///   comprobarlo" y "no cobra en la app" no son lo mismo y no se colapsan.
///
/// Antes, en los dos últimos casos no se dibujaba nada, y el hueco era el
/// problema: el comprador que ve pago en unos productos y en otros no —sin
/// una palabra— asume que la app se rompió, no que ese vendedor cobra de otra
/// forma. Por eso la ausencia de pago en línea ahora se cuenta en vez de
/// esconderse.
///
/// La capacidad real se consulta al backend en vez de leerse de
/// `paymentMethods`: que el vendedor anuncie "tarjeta" no significa que su
/// cuenta de Mercado Pago siga conectada.
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
    this.onContactar,
  });

  final Product product;

  /// Sustituible solo para pruebas: por defecto pregunta al backend.
  final Future<VendorPaymentMethods> Function(String vendorId)? cargarMetodos;

  /// Arranca el checkout con la cantidad elegida. La orden la crea la pantalla
  /// contenedora porque se crea contra el servidor y su ciclo de vida (y sus
  /// errores) son suyos.
  final ValueChanged<int> onPagar;

  /// Abre el chat con el vendedor. Es la única acción que queda cuando no hay
  /// pago en línea, así que la sección no se queda sin salida. Opcional: si no
  /// se pasa, esa variante se dibuja sin botón (informativa).
  final VoidCallback? onContactar;

  /// Hay una orden creándose. Bloquea el botón y lo pone en carga.
  final bool pagando;

  @override
  State<PayWithCardSection> createState() => _PayWithCardSectionState();
}

class _PayWithCardSectionState extends State<PayWithCardSection> {
  VendorPaymentMethods? _metodos;

  /// La consulta sigue en vuelo. Mientras tanto se pinta un esqueleto del
  /// mismo tamaño: si la sección apareciera de golpe, el contenido de abajo
  /// daría un salto justo cuando el comprador está leyéndolo.
  bool _cargando = true;

  /// La consulta terminó en error. Distinto de "no cobra en la app": lleva a
  /// un mensaje distinto y a un reintento.
  bool _fallo = false;

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
    if (!_cargando) setState(() => _cargando = true);
    try {
      final cargar = widget.cargarMetodos ?? PaymentsApi.getMetodosDeVendedor;
      final metodos = await cargar(widget.product.seller.id);
      if (!mounted) return;
      setState(() {
        _metodos = metodos;
        _fallo = false;
        _cargando = false;
      });
    } catch (_) {
      // Sin respuesta no se ofrece pagar. Es el fallo seguro: ofrecerlo y que
      // el cobro reviente después cuesta más que no haberlo ofrecido. Lo que
      // sí se hace es decirlo, porque no es lo mismo que el vendedor no cobre.
      if (!mounted) return;
      setState(() {
        _metodos = null;
        _fallo = true;
        _cargando = false;
      });
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
    if (_cargando) return const _EsqueletoDeSeccion();

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
    if (metodos?.puedeCobrarEnLaApp != true) return _sinPagoEnLinea(context);

    // Prometer "tarjeta" a quien solo puede pagar con su cuenta de Mercado
    // Pago es mandarlo al checkout a encontrarse esa opción apagada.
    final soloCuentaMp = !metodos!.puedeCobrarConTarjeta;

    final colors = context.colors;
    // Cerrado o agotado NO ocultan la sección, la deshabilitan con el motivo.
    // Si desapareciera, el comprador no entendería por qué y creería que el
    // producto no se vende; así sabe que puede volver, y cuándo.
    final bloqueo = _motivoDeBloqueo();

    return _CajaDePago(
      children: [
        // Badge de encabezado: el mismo lenguaje de píldora teñida que usan
        // los badges del perfil del vendedor.
        _PildoraDeSeccion(
          icon: Icons.lock_rounded,
          label: 'PAGO SEGURO',
          color: colors.accent,
          fondo: colors.accentTint,
          borde: colors.accentTintBorder,
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
    );
  }

  /// La variante sin cobro en la app: misma caja, mismo lenguaje visual, pero
  /// sin ninguna promesa de pagar aquí.
  ///
  /// Lo que sustituye al botón no es un hueco: es lo que el comprador SÍ puede
  /// hacer —ver qué acepta el vendedor y escribirle— porque la pregunta que
  /// trae a esta parte de la pantalla ("¿cómo le pago?") tiene respuesta
  /// aunque no haya checkout.
  Widget _sinPagoEnLinea(BuildContext context) {
    final colors = context.colors;

    // 'tarjeta' se cae de la lista a propósito: en esta app significa "cobro
    // por su cuenta de Mercado Pago", que es justo lo que acabamos de
    // comprobar que NO funciona. Anunciarla aquí mandaría al comprador a
    // buscar un botón que no existe.
    final declarados = widget.product.effectivePaymentMethods
        .where((id) => id != 'tarjeta')
        .toList();

    return _CajaDePago(
      // Sin tinte de acento: el dorado es el color de "puedes pagar aquí" y
      // reutilizarlo para lo contrario le quitaría significado.
      borde: colors.border,
      children: [
        _PildoraDeSeccion(
          icon: _fallo ? Icons.wifi_off_rounded : Icons.handshake_rounded,
          label: 'FORMAS DE PAGO',
          color: colors.mutedStrong,
          fondo: colors.surfaceMuted,
          borde: colors.border,
        ),
        const SizedBox(height: 14),
        Text(
          _fallo ? 'No pudimos comprobarlo' : 'Se acuerda con el vendedor',
          style: AppTypography.label(
            15.5,
            weight: FontWeight.w800,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _fallo
              // "No pude comprobarlo" y "no cobra en la app" llevan a acciones
              // distintas —reintentar o escribirle—, así que no se colapsan en
              // un mensaje único.
              ? 'No pudimos consultar los pagos en línea de este vendedor. '
                    'Puedes reintentar o acordar el pago directamente con él.'
              : 'Este vendedor todavía no recibe pagos dentro de la app. '
                    'El pago y la entrega se coordinan directamente con él.',
          style: AppTypography.body(12.5, color: colors.muted),
        ),
        if (declarados.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACEPTA',
                  style: AppTypography.label(
                    9.5,
                    weight: FontWeight.w800,
                    color: colors.muted,
                  ).copyWith(letterSpacing: 0.7),
                ),
                const SizedBox(height: 8),
                PaymentMethodsChips(methods: declarados),
              ],
            ),
          ),
        ],
        if (_fallo || widget.onContactar != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: _fallo
                ? OutlinedButton.icon(
                    onPressed: _cargar,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Reintentar',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: widget.onContactar,
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Acordar pago por chat',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 13, color: colors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Los pagos fuera de la app no pasan por Mercadito UM: '
                'acuérdalos solo con quien te dé confianza.',
                style: AppTypography.body(11.5, color: colors.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// La caja de la sección: una sola definición del fondo, el radio, el borde y
/// la sombra para que las tres variantes (pago, sin pago, cargando) se lean
/// como la MISMA sección cambiando de contenido, y no como tres tarjetas
/// distintas que aparecen y desaparecen.
class _CajaDePago extends StatelessWidget {
  const _CajaDePago({required this.children, this.borde});

  final List<Widget> children;

  /// Color del borde. Por defecto el teñido de acento del pago en línea.
  final Color? borde;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borde ?? colors.accentTintBorder),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Píldora de encabezado de la sección: el mismo lenguaje de badge teñido que
/// usan los del perfil del vendedor.
class _PildoraDeSeccion extends StatelessWidget {
  const _PildoraDeSeccion({
    required this.icon,
    required this.label,
    required this.color,
    required this.fondo,
    required this.borde,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color fondo;
  final Color borde;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borde),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTypography.label(
              10.5,
              weight: FontWeight.w800,
              color: color,
            ).copyWith(letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

/// Lo que se ve mientras se consulta al vendedor.
///
/// Ocupa aproximadamente lo mismo que la sección resuelta a propósito: la
/// alternativa —no dibujar nada hasta que responda el backend— empuja el
/// contenido de abajo justo cuando el comprador está leyéndolo.
class _EsqueletoDeSeccion extends StatelessWidget {
  const _EsqueletoDeSeccion();

  @override
  Widget build(BuildContext context) {
    return _CajaDePago(
      borde: context.colors.border,
      children: [
        const AppShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 108, height: 22, borderRadius: 999),
              SizedBox(height: 14),
              ShimmerBox(width: 170, height: 15),
              SizedBox(height: 8),
              ShimmerBox(width: double.infinity, height: 11),
              SizedBox(height: 18),
              ShimmerBox(width: double.infinity, height: 46, borderRadius: 12),
            ],
          ),
        ),
      ],
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
