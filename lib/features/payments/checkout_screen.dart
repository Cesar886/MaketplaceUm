// TODO: Mercado Pago pendiente para próxima actualización - no eliminar,
// solo descomentar/reactivar cuando esté listo (ver mercado_pago_flag.dart).
// Todo este archivo queda inactivo e inaccesible desde la UI mientras
// kMercadoPagoHabilitado sea false.
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../services/api_error.dart';
import 'add_card_screen.dart';
import 'checkout_methods.dart';
import 'mp_tokenizer.dart';
import 'payment_models.dart';
import 'payments_api.dart';

/// En qué punto va el pago con la cuenta de Mercado Pago.
///
/// Ese pago ocurre FUERA de la app, así que no basta con un bool de
/// "cargando": entre tocar el botón y saber el resultado hay tres esperas
/// distintas —preparar la preferencia, la persona pagando en el navegador, y
/// nosotros preguntando si ya llegó— y cada una necesita decir algo
/// diferente. Un solo bool las colapsaría en un spinner eterno.
enum _FaseCuentaMp {
  inicial,

  /// Pidiendo la preferencia al backend. Dura poco.
  preparando,

  /// La persona está en Mercado Pago. La app no puede hacer nada más que
  /// esperar a que vuelva.
  enMercadoPago,

  /// Volvió: se pregunta por la orden hasta que el webhook la mueva.
  verificando,
}

/// Pantalla de pago de UNA orden.
///
/// Una orden es siempre de un vendedor. Si la compra salió de un carrito con
/// varios vendedores, quien navega hasta aquí lo hace una vez por orden (ver
/// [PaymentsApi.crearOrdenesDesdeCarrito]).
///
/// Hay DOS carriles para cobrar la misma orden y conviven en esta pantalla:
///
///  - **Tarjeta**: el formulario propio de la app. El número y el CVV van
///    del dispositivo a Mercado Pago sin pasar por nuestro servidor.
///  - **Cuenta de Mercado Pago**: se manda a la persona a Mercado Pago, que
///    cobra con lo que tenga allí. Nosotros no vemos nada de eso.
///
/// Los dos cobran EL MISMO importe: ninguno manda el monto: los dos llaman a
/// un endpoint que lo recalcula desde `order_items` en el servidor.
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

class _CheckoutScreenState extends State<CheckoutScreen>
    with WidgetsBindingObserver {
  final _cvv = TextEditingController();

  /// Métodos y clave pública DEL VENDEDOR de esta orden. Sustituye a la
  /// configuración global de la plataforma: la tokenización tiene que
  /// hacerse con la clave del vendedor que va a cobrar.
  VendorPaymentMethods? _metodos;
  List<SavedCard>? _tarjetas;
  SavedCard? _seleccionada;
  String? _error;
  bool _pagando = false;

  /// Carril elegido. Se fija al cargar según lo que el vendedor pueda
  /// cobrar, no con un valor por defecto fijo: preseleccionar tarjeta a un
  /// vendedor que solo puede cobrar por Mercado Pago arranca la pantalla en
  /// la única opción que no funciona.
  MetodoDePagoId _metodoActivo = MetodoDePagoId.tarjeta;

  _FaseCuentaMp _faseMp = _FaseCuentaMp.inicial;

  /// Se salió al navegador y falta volver. Lo lee el ciclo de vida para
  /// distinguir "la app se reanudó porque volvimos de Mercado Pago" de "se
  /// reanudó porque alguien atendió una llamada".
  bool _volviendoDeMercadoPago = false;

  /// Corta un sondeo en curso. Se incrementa al salir de la pantalla o al
  /// cambiar de método: sin esto, un sondeo lanzado hace un minuto sigue
  /// vivo y puede empujar una pantalla de resultado encima de lo que la
  /// persona esté haciendo ahora.
  int _generacionDeSondeo = 0;

  /// Hay algo en vuelo: ningún método puede empezar otra operación.
  bool get _ocupado => _pagando || _faseMp != _FaseCuentaMp.inicial;

  @override
  void initState() {
    super.initState();
    // Volver del navegador reanuda la app: es la señal para preguntar si el
    // pago llegó, sin obligar a nadie a pulsar nada.
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  @override
  void dispose() {
    _generacionDeSondeo++;
    WidgetsBinding.instance.removeObserver(this);
    _cvv.clear();
    _cvv.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _volviendoDeMercadoPago) {
      _volviendoDeMercadoPago = false;
      _verificarPagoConCuentaMp();
    }
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
        _metodoActivo = metodos.aceptaTarjeta
            ? MetodoDePagoId.tarjeta
            : MetodoDePagoId.cuentaMp;
        // El error de "no se puede pagar" solo se levanta cuando NINGÚN
        // carril sirve. Con uno de los dos vivo no hay nada que anunciar
        // arriba: el que no sirve ya lo explica en su propia tarjeta.
        _error = metodos.puedeCobrarEnLaApp
            ? null
            : (metodos.porId('tarjeta')?.unavailableReason ??
                  metodos.walletUnavailableReason ??
                  'checkout.seller_no_payments'.tr(
                    namedArgs: {
                      'seller':
                          widget.nombreVendedor ?? 'checkout.this_seller'.tr(),
                    },
                  ));
      });
    } catch (e, s) {
      if (!mounted) return;
      setState(
        () => _error = mensajeDeError(
          e,
          fallback: 'checkout.prepare_error'.tr(),
          stack: s,
        ),
      );
    }
  }

  /// Los métodos tal como se le ofrecen a esta persona para esta orden.
  ///
  /// Los que no se pueden usar se listan igual, apagados y con el motivo:
  /// esconderlos deja a alguien buscando una opción que le dijeron que
  /// existía. Es el mismo criterio que ya sigue `unavailableReason`.
  List<MetodoDePago> _metodosOfrecidos() {
    final metodos = _metodos;
    if (metodos == null) return const [];

    return [
      MetodoDePago(
        id: MetodoDePagoId.tarjeta,
        titulo: 'card.generic'.tr(),
        subtitulo: 'checkout.card_subtitle'.tr(),
        icono: (context, color) =>
            Icon(Icons.credit_card_rounded, size: 26, color: color),
        motivoNoDisponible: metodos.aceptaTarjeta
            ? null
            : (metodos.porId('tarjeta')?.unavailableReason ??
                  'checkout.card_unavailable'.tr()),
      ),
      MetodoDePago(
        id: MetodoDePagoId.cuentaMp,
        titulo: 'checkout.mp_account'.tr(),
        subtitulo: 'checkout.mp_account_subtitle'.tr(),
        icono: (context, color) =>
            MarcaMercadoPago(apagado: !metodos.puedeCobrarConCuentaMp),
        motivoNoDisponible: metodos.puedeCobrarConCuentaMp
            ? null
            : (metodos.walletUnavailableReason ??
                  'checkout.mp_unavailable'.tr()),
      ),
    ];
  }

  void _cambiarMetodo(MetodoDePagoId id) {
    if (id == _metodoActivo) return;
    setState(() {
      _metodoActivo = id;
      // El error de un método no puede seguir en pantalla cuando ya se está
      // mirando otro: "el CVV no es correcto" sobre el botón de Mercado
      // Pago es desconcertante.
      _error = null;
      _cvv.clear();
    });
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
      setState(() => _error = 'card.cvv_required'.tr());
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

      await _mostrarResultado(resultado);
    } catch (e, s) {
      _cvv.clear();
      if (!mounted) return;
      setState(() {
        _pagando = false;
        _error = mensajeDeError(
          e,
          fallback: 'payments_api.process_error'.tr(),
          stack: s,
        );
      });
    }
  }

  // ─── Pago con la cuenta de Mercado Pago del comprador ─────

  /// Prepara la preferencia y saca a la persona al navegador.
  ///
  /// Al NAVEGADOR del sistema y no a un WebView, por lo mismo que el OAuth
  /// del vendedor (ver [ConnectMpScreen]): ahí se escriben las credenciales
  /// de una cuenta de Mercado Pago, y en un WebView propio no hay barra de
  /// direcciones que permita comprobar que la página es la real. Mercado
  /// Pago además bloquea los WebView embebidos en su login.
  Future<void> _pagarConCuentaMp() async {
    if (_metodos?.puedeCobrarConCuentaMp != true) return;

    setState(() {
      _faseMp = _FaseCuentaMp.preparando;
      _error = null;
    });

    try {
      final checkout = await PaymentsApi.iniciarPagoConCuentaMp(
        widget.orden.id,
      );

      // El importe que va a cobrar Mercado Pago es el que el servidor
      // recalculó. Si no coincide con el que esta pantalla lleva enseñando,
      // se para: cobrar algo distinto de lo que la persona vio en pantalla
      // es lo único que no se puede dejar pasar aquí.
      if ((checkout.amount - widget.orden.amount).abs() > 0.009) {
        if (!mounted) return;
        setState(() {
          _faseMp = _FaseCuentaMp.inicial;
          _error = 'checkout.total_changed'.tr();
        });
        return;
      }

      _volviendoDeMercadoPago = true;
      final abierto = await launchUrl(
        Uri.parse(checkout.initPoint),
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;
      if (!abierto) {
        _volviendoDeMercadoPago = false;
        setState(() {
          _faseMp = _FaseCuentaMp.inicial;
          _error = 'mp.browser_error'.tr();
        });
        return;
      }
      setState(() => _faseMp = _FaseCuentaMp.enMercadoPago);
    } catch (e, s) {
      _volviendoDeMercadoPago = false;
      if (!mounted) return;
      setState(() {
        _faseMp = _FaseCuentaMp.inicial;
        _error = mensajeDeError(
          e,
          fallback: 'checkout.mp_start_error'.tr(),
          stack: s,
        );
      });
    }
  }

  /// Pregunta por la orden hasta que tenga veredicto.
  ///
  /// Hay que sondear porque quien decide si esta orden se pagó es el webhook
  /// de Mercado Pago contra nuestro backend, y eso llega cuando llega: la
  /// vuelta del navegador NO prueba nada — se llega a ella igual cancelando
  /// el pago, y se puede escribir a mano.
  ///
  /// Si se agotan los intentos no se declara nada. Un pago aprobado que
  /// tardó de más se pintaría como rechazado, y esa es la peor mentira
  /// posible en esta pantalla: la persona pagaría dos veces.
  Future<void> _verificarPagoConCuentaMp() async {
    final generacion = ++_generacionDeSondeo;
    if (!mounted) return;
    setState(() {
      _faseMp = _FaseCuentaMp.verificando;
      _error = null;
    });

    // Un minuto largo, denso al principio: el webhook normalmente llega en
    // segundos, y espaciar desde el arranque haría esperar de más al caso
    // común por culpa del raro.
    const esperas = [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 3),
      Duration(seconds: 5),
      Duration(seconds: 5),
      Duration(seconds: 8),
      Duration(seconds: 8),
      Duration(seconds: 10),
      Duration(seconds: 15),
    ];

    for (final espera in esperas) {
      await Future<void>.delayed(espera);
      if (!mounted || generacion != _generacionDeSondeo) return;

      try {
        final orden = await PaymentsApi.getOrden(widget.orden.id);
        if (!mounted || generacion != _generacionDeSondeo) return;

        final resultado = CheckoutResult.deOrden(orden);
        if (resultado != null) {
          await _mostrarResultado(resultado);
          return;
        }
      } catch (_) {
        // Un fallo de red en mitad del sondeo no significa que el pago
        // fallara: se sigue preguntando. Solo si se agotan los intentos se
        // dice algo, y lo que se dice es "no lo sabemos todavía".
      }
    }

    if (!mounted || generacion != _generacionDeSondeo) return;
    setState(() {
      _faseMp = _FaseCuentaMp.inicial;
      _error = 'checkout.mp_no_confirmation'.tr();
    });
  }

  /// Lleva a la pantalla de resultado y decide qué hacer al volver de ella.
  ///
  /// La comparten los dos métodos: el final de un pago se ve igual da lo
  /// mismo por dónde entró el dinero, y duplicarlo es cómo uno de los dos se
  /// queda sin vaciar el carrito o sin devolver el resultado a quien abrió
  /// el checkout.
  Future<void> _mostrarResultado(CheckoutResult resultado) async {
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
      setState(() {
        _pagando = false;
        _faseMp = _FaseCuentaMp.inicial;
      });
      if (reintentar != true) Navigator.pop(context, resultado);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('checkout.title'.tr())),
      body: SafeArea(child: _cuerpo()),
    );
  }

  Widget _cuerpo() {
    final colors = context.colors;
    final metodos = _metodos;

    // Se espera a `_metodos` y no a `_tarjetas`: con un vendedor que solo
    // cobra por Mercado Pago no hay tarjetas que cargar, y esperar por ellas
    // dejaría la pantalla en un spinner que no termina nunca.
    if (metodos == null) {
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
          'checkout.how_to_pay'.tr(),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 12),
        SelectorDeMetodoDePago(
          metodos: _metodosOfrecidos(),
          seleccionado: _metodoActivo,
          onSeleccionar: _ocupado ? (_) {} : _cambiarMetodo,
        ),
        const SizedBox(height: 6),
        ...switch (_metodoActivo) {
          MetodoDePagoId.tarjeta => _cuerpoTarjeta(),
          MetodoDePagoId.cuentaMp => _cuerpoCuentaMp(),
        },
        if (_error != null) ...[
          const SizedBox(height: 16),
          CajaDeError(mensaje: _error!),
        ],
        const SizedBox(height: 24),
        _accion(),
      ],
    );
  }

  /// Lo propio del pago con tarjeta: elegir cuál y escribir el CVV.
  List<Widget> _cuerpoTarjeta() {
    final colors = context.colors;
    final tarjetas = _tarjetas;

    if (_metodos?.aceptaTarjeta != true) return const [];
    if (tarjetas == null) {
      return const [
        SizedBox(height: 24),
        Center(child: CircularProgressIndicator()),
      ];
    }

    return [
      if (tarjetas.isEmpty)
        _SinTarjetas(onAgregar: _agregarTarjeta)
      else ...[
        for (final tarjeta in tarjetas)
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
          onPressed: _ocupado ? null : _agregarTarjeta,
          icon: const Icon(Icons.add, size: 18),
          label: Text('checkout.add_another_card'.tr()),
        ),
      ],
      if (_seleccionada != null) ...[
        const SizedBox(height: 16),
        TextFormField(
          controller: _cvv,
          keyboardType: TextInputType.number,
          obscureText: true,
          enabled: !_ocupado,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          style: TextStyle(color: colors.ink),
          decoration: InputDecoration(
            labelText: 'checkout.cvv_for_card'.tr(
              namedArgs: {'last4': _seleccionada!.lastFourDigits},
            ),
            helperText: 'checkout.cvv_helper'.tr(),
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
    ];
  }

  /// Lo propio del pago con cuenta de Mercado Pago: contar qué va a pasar.
  ///
  /// No hay formulario que rellenar, así que todo lo que este bloque puede
  /// aportar es que nadie se sorprenda al salir de la app — que es
  /// exactamente el momento en que la gente abandona un pago.
  List<Widget> _cuerpoCuentaMp() {
    final colors = context.colors;

    if (_metodos?.puedeCobrarConCuentaMp != true) return const [];

    if (_faseMp == _FaseCuentaMp.enMercadoPago ||
        _faseMp == _FaseCuentaMp.verificando) {
      final verificando = _faseMp == _FaseCuentaMp.verificando;
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.accentTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.accentTintBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  verificando
                      ? 'checkout.mp_confirming'.tr()
                      : 'checkout.mp_finish_outside'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Punto(
              icono: Icons.open_in_new_rounded,
              texto: 'checkout.mp_point_open'.tr(),
            ),
            const SizedBox(height: 10),
            _Punto(
              icono: Icons.account_balance_wallet_outlined,
              texto: 'checkout.mp_point_balance'.tr(),
            ),
            const SizedBox(height: 10),
            _Punto(
              icono: Icons.lock_outline_rounded,
              texto: 'checkout.mp_point_data'.tr(),
            ),
          ],
        ),
      ),
    ];
  }

  /// El botón principal, distinto por método pero con el mismo componente.
  Widget _accion() {
    final metodos = _metodos;
    if (metodos == null || !metodos.puedeCobrarEnLaApp) {
      return const SizedBox.shrink();
    }

    final total = _formatoPrecio(widget.orden.amount);

    switch (_metodoActivo) {
      case MetodoDePagoId.tarjeta:
        return BotonDePago(
          etiqueta: 'checkout.pay_total'.tr(namedArgs: {'total': total}),
          cargando: _pagando,
          onPressed: (_seleccionada == null || _ocupado) ? null : _pagar,
        );

      case MetodoDePagoId.cuentaMp:
        // Ya salió al navegador: el botón deja de ser "pagar" —volver a
        // pulsarlo abriría un segundo pago de la misma orden— y pasa a ser
        // la salida manual para quien volvió sin que la app se enterara.
        if (_faseMp == _FaseCuentaMp.enMercadoPago) {
          return OutlinedButton.icon(
            onPressed: _verificarPagoConCuentaMp,
            icon: const Icon(Icons.refresh_rounded, size: 19),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'checkout.already_paid'.tr(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        return BotonDePago(
          etiqueta: 'checkout.pay_total_mp'.tr(namedArgs: {'total': total}),
          icono: Icons.open_in_new_rounded,
          cargando: _faseMp != _FaseCuentaMp.inicial,
          onPressed: _ocupado ? null : _pagarConCuentaMp,
        );
    }
  }
}

/// Una línea de "esto es lo que va a pasar" en el panel de Mercado Pago.
class _Punto extends StatelessWidget {
  const _Punto({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 16, color: colors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: colors.muted),
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
              'checkout.buying_from'.tr(namedArgs: {'seller': nombreVendedor!}),
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
                          ? '${item.quantity}× ${item.title ?? 'chat.product_fallback'.tr()}'
                          : (item.title ?? 'chat.product_fallback'.tr()),
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
                            ? 'checkout.card_expired'.tr(
                                namedArgs: {'date': tarjeta.vencimiento},
                              )
                            : 'checkout.card_expires'.tr(
                                namedArgs: {'date': tarjeta.vencimiento},
                              ),
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
            'checkout.no_saved_cards'.tr(),
            style: TextStyle(fontSize: 14, color: colors.mutedStrong),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onAgregar, child: Text('card.add'.tr())),
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
      EstadoPago.aprobado => 'checkout.result_approved'.tr(),
      EstadoPago.pendiente => 'checkout.result_pending'.tr(),
      EstadoPago.rechazado => 'checkout.result_rejected'.tr(),
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      // Volver al checkout deja elegir CUALQUIER método, no
                      // solo otra tarjeta. Prometer "otra tarjeta" a quien
                      // acaba de fallar pagando con su cuenta de Mercado
                      // Pago le esconde justo la salida que sí tiene.
                      child: Text(switch (resultado.metodo) {
                        MetodoDePagoId.tarjeta =>
                          'checkout.try_another_card'.tr(),
                        MetodoDePagoId.cuentaMp =>
                          'checkout.try_another_way'.tr(),
                      }),
                    ),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    resultado.estado == EstadoPago.rechazado
                        ? 'common.cancel'.tr()
                        : 'common.done'.tr(),
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
