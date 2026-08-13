import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../services/api_error.dart';
import 'add_card_screen.dart';
import 'mp_tokenizer.dart';
import 'payment_models.dart';
import 'payments_api.dart';

/// Pantalla de pago de UNA orden.
///
/// Una orden es siempre de un vendedor. Si la compra salió de un carrito con
/// varios vendedores, quien navega hasta aquí lo hace una vez por orden (ver
/// [PaymentsApi.crearOrdenesDesdeCarrito]).
///
/// Detalle que parece redundante y no lo es: aunque la tarjeta esté
/// guardada, se pide el CVV y se genera un token NUEVO en cada pago. Es lo
/// que exige Mercado Pago y lo que impide que alguien con acceso a una
/// sesión abierta pueda gastar con tarjetas ajenas.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.orden, this.nombreVendedor});

  final PaymentOrder orden;
  final String? nombreVendedor;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _cvv = TextEditingController();

  /// Métodos y clave pública DEL VENDEDOR de esta orden. Sustituye a la
  /// configuración global de la plataforma: la tokenización tiene que
  /// hacerse con la clave del vendedor que va a cobrar.
  VendorPaymentMethods? _metodos;
  List<SavedCard>? _tarjetas;
  SavedCard? _seleccionada;
  String? _error;
  bool _pagando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cvv.clear();
    _cvv.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      // En vivo y en este orden: si el vendedor ya no puede cobrar con
      // tarjeta, no tiene sentido ni pedir las tarjetas guardadas con él.
      final metodos = await PaymentsApi.getMetodosDeVendedor(
        widget.orden.vendorId,
      );
      final tarjetas = metodos.aceptaTarjeta
          ? await PaymentsApi.getTarjetas(widget.orden.vendorId)
          : <SavedCard>[];
      if (!mounted) return;
      setState(() {
        _metodos = metodos;
        _tarjetas = tarjetas;
        _seleccionada = tarjetas.where((t) => !t.estaVencida).firstOrNull;
        _error = metodos.aceptaTarjeta
            ? null
            : (metodos.porId('tarjeta')?.unavailableReason ??
                  '${widget.nombreVendedor ?? 'Este vendedor'} no acepta pagos con '
                      'tarjeta en la app. Contáctalo por chat para acordar otra forma de pago.');
      });
    } catch (e, s) {
      if (!mounted) return;
      setState(
        () => _error = mensajeDeError(
          e,
          fallback: 'No se pudo preparar el pago.',
          stack: s,
        ),
      );
    }
  }

  Future<void> _agregarTarjeta() async {
    final metodos = _metodos;
    if (metodos == null || !metodos.aceptaTarjeta) return;

    final nueva = await Navigator.push<SavedCard>(
      context,
      MaterialPageRoute(
        builder: (_) => AddCardScreen(
          vendorId: widget.orden.vendorId,
          publicKey: metodos.cardPublicKey!,
          nombreVendedor: widget.nombreVendedor,
        ),
      ),
    );
    if (nueva == null) return;
    await _cargar();
    if (!mounted) return;
    setState(() => _seleccionada = nueva);
  }

  Future<void> _pagar() async {
    final metodos = _metodos;
    final tarjeta = _seleccionada;
    if (metodos == null || !metodos.aceptaTarjeta || tarjeta == null) return;

    if (_cvv.text.length < 3) {
      setState(() => _error = 'Escribe el código de seguridad (CVV).');
      return;
    }

    setState(() {
      _pagando = true;
      _error = null;
    });

    try {
      // Token nuevo por cobro, generado contra la API pública de MP: el CVV
      // va del dispositivo a Mercado Pago sin pasar por nuestro servidor.
      final token = await MpTokenizer.tokenizarTarjetaGuardada(
        publicKey: metodos.cardPublicKey!,
        cardId: tarjeta.id,
        cvv: _cvv.text,
      );

      final resultado = await PaymentsApi.pagar(
        orderId: widget.orden.id,
        cardToken: token,
        paymentMethodId: tarjeta.paymentMethod.isEmpty
            ? null
            : tarjeta.paymentMethod,
      );

      // El CVV no sobrevive al intento de pago, salga como salga.
      _cvv.clear();

      if (!mounted) return;
      final reintentar = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentResultScreen(resultado: resultado),
        ),
      );

      if (!mounted) return;
      if (resultado.estado == EstadoPago.aprobado) {
        Navigator.pop(context, resultado);
      } else {
        setState(() => _pagando = false);
        if (reintentar != true) Navigator.pop(context, resultado);
      }
    } catch (e, s) {
      _cvv.clear();
      if (!mounted) return;
      setState(() {
        _pagando = false;
        _error = mensajeDeError(
          e,
          fallback: 'No se pudo procesar el pago.',
          stack: s,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pagar')),
      body: SafeArea(child: _cuerpo()),
    );
  }

  Widget _cuerpo() {
    final colors = context.colors;

    if (_tarjetas == null) {
      return _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted),
                ),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _ResumenOrden(
          orden: widget.orden,
          nombreVendedor: widget.nombreVendedor,
        ),
        const SizedBox(height: 24),
        Text(
          'Método de pago',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 12),
        if (_tarjetas!.isEmpty)
          _SinTarjetas(onAgregar: _agregarTarjeta)
        else ...[
          for (final tarjeta in _tarjetas!)
            _FilaTarjeta(
              tarjeta: tarjeta,
              seleccionada: _seleccionada?.id == tarjeta.id,
              onSeleccionar: tarjeta.estaVencida
                  ? null
                  : () => setState(() {
                      _seleccionada = tarjeta;
                      _cvv.clear();
                    }),
            ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _agregarTarjeta,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar otra tarjeta'),
          ),
        ],
        if (_seleccionada != null) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _cvv,
            keyboardType: TextInputType.number,
            obscureText: true,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            style: TextStyle(color: colors.ink),
            decoration: InputDecoration(
              labelText:
                  'CVV de la tarjeta terminada en '
                  '${_seleccionada!.lastFourDigits}',
              helperText: 'Se pide en cada compra por seguridad.',
              helperStyle: TextStyle(fontSize: 11, color: colors.muted),
              filled: true,
              fillColor: colors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
            ),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 13, height: 1.4, color: colors.ink),
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: (_seleccionada == null || _pagando) ? null : _pagar,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _pagando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Pagar ${_formatoPrecio(widget.orden.amount)}'),
          ),
        ),
      ],
    );
  }
}

String _formatoPrecio(double valor) {
  final entero = valor.floor();
  final centavos = ((valor - entero) * 100).round().toString().padLeft(2, '0');
  final buffer = StringBuffer();
  final digitos = entero.toString();
  for (var i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digitos[i]);
  }
  return '\$$buffer.$centavos';
}

class _ResumenOrden extends StatelessWidget {
  const _ResumenOrden({required this.orden, this.nombreVendedor});

  final PaymentOrder orden;
  final String? nombreVendedor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nombreVendedor != null) ...[
            Text(
              'Le compras a $nombreVendedor',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
            const SizedBox(height: 10),
          ],
          for (final item in orden.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.quantity > 1
                          ? '${item.quantity}× ${item.title ?? 'Producto'}'
                          : (item.title ?? 'Producto'),
                      style: TextStyle(fontSize: 14, color: colors.ink),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatoPrecio(item.subtotal),
                    style: TextStyle(fontSize: 14, color: colors.mutedStrong),
                  ),
                ],
              ),
            ),
          Divider(color: colors.border, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              Text(
                _formatoPrecio(orden.amount),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilaTarjeta extends StatelessWidget {
  const _FilaTarjeta({
    required this.tarjeta,
    required this.seleccionada,
    required this.onSeleccionar,
  });

  final SavedCard tarjeta;
  final bool seleccionada;
  final VoidCallback? onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vencida = tarjeta.estaVencida;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onSeleccionar,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: seleccionada ? colors.accentTint : colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: seleccionada ? colors.accentTintBorder : colors.border,
              width: seleccionada ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.credit_card,
                size: 22,
                color: vencida ? colors.muted : colors.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tarjeta.marcaLegible} ···· ${tarjeta.lastFourDigits}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: vencida ? colors.muted : colors.ink,
                      ),
                    ),
                    if (tarjeta.vencimiento.isNotEmpty)
                      Text(
                        vencida
                            ? 'Vencida (${tarjeta.vencimiento})'
                            : 'Vence ${tarjeta.vencimiento}',
                        style: TextStyle(
                          fontSize: 12,
                          color: vencida ? colors.danger : colors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (seleccionada)
                Icon(Icons.check_circle, size: 20, color: colors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _SinTarjetas extends StatelessWidget {
  const _SinTarjetas({required this.onAgregar});

  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.credit_card_off_outlined, size: 32, color: colors.muted),
          const SizedBox(height: 10),
          Text(
            'Todavía no tienes tarjetas guardadas.',
            style: TextStyle(fontSize: 14, color: colors.mutedStrong),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onAgregar,
            child: const Text('Agregar tarjeta'),
          ),
        ],
      ),
    );
  }
}

/// Resultado del pago: aprobado, pendiente o rechazado.
class PaymentResultScreen extends StatelessWidget {
  const PaymentResultScreen({super.key, required this.resultado});

  final CheckoutResult resultado;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (icono, color) = switch (resultado.estado) {
      EstadoPago.aprobado => (Icons.check_circle_outline, colors.success),
      EstadoPago.pendiente => (Icons.schedule, colors.accent),
      EstadoPago.rechazado => (Icons.error_outline, colors.danger),
    };

    final titulo = switch (resultado.estado) {
      EstadoPago.aprobado => 'Pago completado',
      EstadoPago.pendiente => 'Pago en revisión',
      EstadoPago.rechazado => 'Pago rechazado',
    };

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icono, size: 48, color: color),
                ),
                const SizedBox(height: 24),
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  resultado.mensaje,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: colors.muted,
                  ),
                ),
                if (resultado.estado == EstadoPago.aprobado) ...[
                  const SizedBox(height: 16),
                  Text(
                    _formatoPrecio(resultado.amount),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: colors.accent,
                    ),
                  ),
                ],
                const Spacer(),
                if (resultado.estado == EstadoPago.rechazado)
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Intentar con otra tarjeta'),
                    ),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    resultado.estado == EstadoPago.rechazado
                        ? 'Cancelar'
                        : 'Listo',
                    style: TextStyle(color: colors.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
