/// Modelos del módulo de pagos.
///
/// Nota importante sobre qué NO existe aquí: no hay ningún campo para el
/// número de tarjeta, el CVV ni el token de pago. Esos datos viven en
/// memoria el tiempo que tarda el formulario en enviarlos a Mercado Pago y
/// nunca se guardan, ni en un modelo, ni en disco, ni en el backend.
library;

/// Tarjeta guardada, tal como la devuelve el backend: solo lo necesario
/// para que la persona reconozca cuál es.
class SavedCard {
  const SavedCard({
    required this.id,
    required this.lastFourDigits,
    required this.paymentMethod,
    this.expirationMonth,
    this.expirationYear,
  });

  factory SavedCard.fromJson(Map<String, dynamic> json) => SavedCard(
    id: json['id'] as String,
    lastFourDigits: (json['lastFourDigits'] ?? '····') as String,
    paymentMethod: (json['paymentMethod'] ?? '') as String,
    expirationMonth: json['expirationMonth'] as int?,
    expirationYear: json['expirationYear'] as int?,
  );

  /// Id de la tarjeta EN Mercado Pago. Es una referencia opaca: no permite
  /// reconstruir el número.
  final String id;
  final String lastFourDigits;

  /// 'visa', 'master', 'amex'… tal como lo llama Mercado Pago.
  final String paymentMethod;
  final int? expirationMonth;
  final int? expirationYear;

  String get marcaLegible {
    switch (paymentMethod.toLowerCase()) {
      case 'visa':
        return 'Visa';
      case 'master':
      case 'mastercard':
        return 'Mastercard';
      case 'amex':
        return 'American Express';
      case 'debvisa':
        return 'Visa Débito';
      case 'debmaster':
        return 'Mastercard Débito';
      default:
        return paymentMethod.isEmpty ? 'Tarjeta' : paymentMethod;
    }
  }

  String get vencimiento {
    if (expirationMonth == null || expirationYear == null) return '';
    final mes = expirationMonth.toString().padLeft(2, '0');
    final anio = expirationYear.toString().padLeft(4, '0').substring(2);
    return '$mes/$anio';
  }

  bool get estaVencida {
    if (expirationMonth == null || expirationYear == null) return false;
    final ahora = DateTime.now();
    final ultimoDia = DateTime(expirationYear!, expirationMonth! + 1, 0);
    return ultimoDia.isBefore(DateTime(ahora.year, ahora.month, ahora.day));
  }
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.title,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    productId: json['productId'] as String,
    quantity: (json['quantity'] as num).toInt(),
    unitPrice: (json['unitPrice'] as num).toDouble(),
    title: json['title'] as String?,
  );

  final String productId;
  final int quantity;

  /// Precio CONGELADO al crear la orden. Si el vendedor cambia el precio
  /// después, esta orden conserva el que se acordó.
  final double unitPrice;
  final String? title;

  double get subtotal => unitPrice * quantity;
}

/// Una orden es siempre de UN vendedor: el cobro con split va contra su
/// cuenta de Mercado Pago. Un carrito con dos vendedores genera dos órdenes.
class PaymentOrder {
  const PaymentOrder({
    required this.id,
    required this.vendorId,
    required this.amount,
    required this.applicationFee,
    required this.currency,
    required this.status,
    required this.items,
    this.paymentStatus,
    this.createdAt,
  });

  factory PaymentOrder.fromJson(Map<String, dynamic> json) => PaymentOrder(
    id: json['id'] as String,
    vendorId: json['vendorId'] as String,
    amount: (json['amount'] as num).toDouble(),
    applicationFee: (json['applicationFee'] as num?)?.toDouble() ?? 0,
    currency: (json['currency'] ?? 'MXN') as String,
    status: (json['status'] ?? 'pending') as String,
    paymentStatus: json['paymentStatus'] as String?,
    createdAt: json['createdAt'] as String?,
    items: ((json['items'] ?? const []) as List<dynamic>)
        .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String vendorId;
  final double amount;

  /// Comisión de la plataforma. Se muestra a modo informativo: NO se suma
  /// al total — sale de lo que recibe el vendedor, no de lo que paga quien
  /// compra.
  final double applicationFee;
  final String currency;
  final String status;
  final String? paymentStatus;
  final String? createdAt;
  final List<OrderItem> items;

  bool get estaPagada => status == 'paid';
}

/// En qué acabó un intento de cobro.
enum EstadoPago { aprobado, pendiente, rechazado }

/// Por qué carril se cobra una orden.
///
/// Vive aquí, en los modelos, y no en la pantalla, porque no es solo una
/// opción de la interfaz: cambia a qué endpoint se llama y cómo se redactan
/// los mensajes de resultado ("intenta con otra tarjeta" no significa nada
/// para quien pagó con su cuenta de Mercado Pago).
///
/// Añadir un método nuevo —efectivo en tienda, otra billetera— es añadir un
/// valor aquí y su descriptor en `checkout_methods.dart`. Nada más de la
/// pantalla de pago tiene que saber cuántos hay.
enum MetodoDePagoId {
  tarjeta,
  cuentaMp;

  /// Lo que se manda al backend en `POST /api/orders` como `paymentMethod`.
  ///
  /// Los dos carriles son 'tarjeta' para el vendedor: son las dos formas de
  /// cobrar por su cuenta de Mercado Pago conectada, y es el único método
  /// que su perfil declara. Un id distinto haría que `/api/orders` rechazara
  /// la orden por un método que ningún vendedor tiene declarado.
  String get metodoDeclarado => 'tarjeta';
}

class CheckoutResult {
  const CheckoutResult({
    required this.orderId,
    required this.estado,
    required this.amount,
    this.statusDetail,
    this.metodo = MetodoDePagoId.tarjeta,
  });

  factory CheckoutResult.fromJson(Map<String, dynamic> json) {
    final crudo = (json['status'] ?? '') as String;
    return CheckoutResult(
      orderId: (json['orderId'] ?? '') as String,
      estado: switch (crudo) {
        'approved' => EstadoPago.aprobado,
        'in_process' || 'pending' || 'authorized' => EstadoPago.pendiente,
        _ => EstadoPago.rechazado,
      },
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      statusDetail: json['statusDetail'] as String?,
    );
  }

  /// Resultado deducido del ESTADO DE LA ORDEN, no de una respuesta de cobro.
  ///
  /// Lo usa el pago con cuenta de Mercado Pago: ahí nadie nos devuelve el
  /// resultado del cobro —el comprador paga en Mercado Pago, fuera de la
  /// app— y lo único que se puede hacer es preguntar por la orden hasta que
  /// el webhook la mueva. Traducir esa orden a un [CheckoutResult] es lo que
  /// permite que los dos métodos terminen en la misma pantalla de resultado.
  ///
  /// Devuelve null mientras la orden siga sin veredicto: no es lo mismo
  /// "todavía no se sabe" que "rechazado", y colapsarlos le diría a alguien
  /// que su pago falló cuando solo estaba tardando.
  static CheckoutResult? deOrden(PaymentOrder orden) {
    final estado = switch (orden.paymentStatus) {
      'approved' => EstadoPago.aprobado,
      'in_process' || 'pending' || 'authorized' => EstadoPago.pendiente,
      'rejected' || 'cancelled' => EstadoPago.rechazado,
      // Sin `paymentStatus` todavía puede haber veredicto igual: el estado
      // de la ORDEN es el que se mueve cuando el vendedor deja de poder
      // cobrar, sin que llegue a existir ningún pago.
      _ => switch (orden.status) {
        'paid' => EstadoPago.aprobado,
        'cancelled' || 'requires_other_method' => EstadoPago.rechazado,
        _ => null,
      },
    };
    if (estado == null) return null;
    return CheckoutResult(
      orderId: orden.id,
      estado: estado,
      amount: orden.amount,
      metodo: MetodoDePagoId.cuentaMp,
    );
  }

  final String orderId;
  final EstadoPago estado;
  final double amount;

  /// Con qué se intentó pagar. Solo afecta a la redacción de [mensaje].
  final MetodoDePagoId metodo;

  /// Código estable de Mercado Pago ('cc_rejected_bad_filled_security_code').
  /// Se traduce en el cliente: el backend nunca reenvía texto de MP.
  final String? statusDetail;

  /// Mensaje accionable a partir del código de rechazo.
  ///
  /// La lista sale de la documentación de MP y cubre los rechazos que de
  /// verdad ocurren. El genérico existe porque MP añade códigos nuevos: un
  /// código desconocido tiene que dar un mensaje útil, no una cadena vacía.
  String get mensaje {
    switch (estado) {
      case EstadoPago.aprobado:
        return '¡Pago aprobado! Ya puedes coordinar la entrega por chat.';
      case EstadoPago.pendiente:
        return 'Tu pago está en revisión. Te avisamos en cuanto se confirme.';
      case EstadoPago.rechazado:
        switch (statusDetail) {
          case 'cc_rejected_bad_filled_security_code':
            return 'El código de seguridad (CVV) no es correcto.';
          case 'cc_rejected_bad_filled_date':
            return 'La fecha de vencimiento no es correcta.';
          case 'cc_rejected_bad_filled_card_number':
            return 'Revisa el número de la tarjeta.';
          case 'cc_rejected_insufficient_amount':
            return 'Tu tarjeta no tiene fondos suficientes.';
          case 'cc_rejected_high_risk':
            return 'Tu banco rechazó el pago. Intenta con otra tarjeta.';
          case 'cc_rejected_max_attempts':
            return 'Demasiados intentos con esta tarjeta. Prueba con otra.';
          case 'cc_rejected_call_for_authorize':
            return 'Tu banco necesita autorizar este pago. Llámalos e intenta de nuevo.';
          case 'cc_rejected_card_disabled':
            return 'La tarjeta está inactiva. Llama a tu banco para activarla.';
          case 'cc_rejected_duplicated_payment':
            return 'Ya hiciste un pago igual hace un momento. Revisa tus compras.';
          default:
            // Los códigos de arriba son todos de tarjeta ('cc_'), así que
            // llegan solo por ese carril. El genérico no: es lo único que
            // se puede decir cuando el pago se hizo con la cuenta de
            // Mercado Pago y lo que sabemos es que la orden no prosperó.
            return switch (metodo) {
              MetodoDePagoId.tarjeta =>
                'El pago fue rechazado. Intenta con otra tarjeta.',
              MetodoDePagoId.cuentaMp =>
                'El pago no se completó. Puedes intentarlo de nuevo o pagar '
                    'con tarjeta.',
            };
        }
    }
  }
}

/// Estado de la cuenta de Mercado Pago de un vendedor.
/// Estado de la cuenta de cobros tal como puede pintarlo la app.
///
/// [desconocido] existe porque "no pude comprobarlo" y "no está conectada"
/// son cosas distintas y llevan a acciones distintas: la primera se
/// reintenta, la segunda se resuelve conectando. Colapsarlas en un bool deja
/// al vendedor mirando "Sin conectar" mientras su cuenta funciona.
enum EstadoCobros {
  conectado,
  sinConectar,
  desconocido;

  bool get estaConectado => this == EstadoCobros.conectado;
}

class VendorAccountStatus {
  const VendorAccountStatus({
    required this.connected,
    required this.canConnect,
    this.connectedAt,
  });

  factory VendorAccountStatus.fromJson(Map<String, dynamic> json) =>
      VendorAccountStatus(
        connected: json['connected'] == true,
        canConnect: json['canConnect'] == true,
        connectedAt: json['connectedAt'] as String?,
      );

  final bool connected;

  /// Falso si la cuenta no está verificada o es de tipo particular: no puede
  /// recibir pagos todavía.
  final bool canConnect;
  final String? connectedAt;
}

/// Configuración pública que el backend sirve a la app.
class PaymentsConfig {
  const PaymentsConfig({
    required this.publicKey,
    required this.currency,
    required this.feePercent,
  });

  factory PaymentsConfig.fromJson(Map<String, dynamic> json) => PaymentsConfig(
    publicKey: json['publicKey'] as String,
    currency: (json['currency'] ?? 'MXN') as String,
    feePercent: (json['feePercent'] as num?)?.toDouble() ?? 0,
  );

  /// Clave PÚBLICA de Mercado Pago. Es la única credencial que puede estar
  /// en el dispositivo: solo sirve para tokenizar tarjetas. Se pide al
  /// backend en vez de compilarla en la app para poder rotarla sin
  /// publicar una versión nueva.
  final String publicKey;
  final String currency;
  final double feePercent;
}

/// Métodos de pago que un vendedor concreto acepta, y cuáles de ellos
/// funcionan ahora mismo.
///
/// La distinción importa: un vendedor puede tener 'tarjeta' entre sus
/// métodos y aun así no poder cobrarla porque su cuenta de Mercado Pago se
/// desconectó. En ese caso llega `available: false` con un motivo legible,
/// para que el checkout pueda explicarlo en vez de esconder la opción.
class VendorPaymentMethod {
  const VendorPaymentMethod({
    required this.id,
    required this.available,
    this.unavailableReason,
  });

  final String id;
  final bool available;
  final String? unavailableReason;

  factory VendorPaymentMethod.fromJson(Map<String, dynamic> json) {
    return VendorPaymentMethod(
      id: json['id'] as String? ?? '',
      available: json['available'] == true,
      unavailableReason: json['unavailableReason'] as String?,
    );
  }
}

class VendorPaymentMethods {
  const VendorPaymentMethods({
    required this.vendorId,
    required this.methods,
    this.cardEnabled = false,
    this.cardPublicKey,
    this.walletEnabled = false,
    this.walletUnavailableReason,
  });

  final String vendorId;

  /// Lo que el vendedor ANUNCIA que acepta. No es lo mismo que lo que su
  /// cuenta puede cobrar — ver [cardEnabled].
  final List<VendorPaymentMethod> methods;

  /// Su cuenta de Mercado Pago está conectada y viva AHORA: el cobro con
  /// tarjeta funcionaría hoy mismo, haya marcado o no 'tarjeta' en su perfil.
  ///
  /// Es lo que decide si se le ofrece pagar con tarjeta al comprador, porque
  /// es exactamente lo que `/payments/checkout` exige. Marcar el checkbox del
  /// perfil es una declaración de intenciones; esto es la capacidad real.
  final bool cardEnabled;

  /// Clave pública DEL VENDEDOR con la que hay que tokenizar. Llega null si
  /// no puede cobrar con tarjeta; nunca es la clave de la plataforma.
  final String? cardPublicKey;

  /// Su cuenta de Mercado Pago está conectada y viva: se le puede mandar al
  /// comprador a pagar allí con su propia cuenta.
  ///
  /// Es una condición MÁS FLOJA que [puedeCobrarConTarjeta] y no un
  /// duplicado suyo: por este camino no se tokeniza nada en el dispositivo,
  /// así que no hace falta la public key del vendedor. Un vendedor cuyo
  /// OAuth no devolvió public key puede cobrar por aquí y no por tarjeta.
  final bool walletEnabled;

  /// Por qué no se puede pagar con cuenta de Mercado Pago, ya redactado por
  /// el backend. Null cuando sí se puede.
  final String? walletUnavailableReason;

  /// Se le puede ofrecer pagar con tarjeta: su cuenta cobra y hay con qué
  /// tokenizar. Sin la key el comprador queda en un callejón.
  bool get puedeCobrarConTarjeta => cardEnabled && cardPublicKey != null;

  /// Se le puede ofrecer pagar con su cuenta de Mercado Pago.
  bool get puedeCobrarConCuentaMp => walletEnabled;

  /// ¿Hay ALGÚN carril de cobro en la app para este vendedor?
  ///
  /// La pantalla de pago solo tiene sentido si esto es cierto; con los dos
  /// apagados lo que toca es explicar por qué, no pintar un selector vacío.
  bool get puedeCobrarEnLaApp => puedeCobrarConTarjeta || puedeCobrarConCuentaMp;

  /// El vendedor ANUNCIA tarjeta y además funciona. Más estricto que
  /// [puedeCobrarConTarjeta]: úsalo solo donde importe lo declarado.
  bool get aceptaTarjeta =>
      methods.any((m) => m.id == 'tarjeta' && m.available) &&
      cardPublicKey != null;

  VendorPaymentMethod? porId(String id) {
    for (final m in methods) {
      if (m.id == id) return m;
    }
    return null;
  }

  factory VendorPaymentMethods.fromJson(Map<String, dynamic> json) {
    final lista = (json['methods'] as List<dynamic>? ?? const [])
        .map((e) => VendorPaymentMethod.fromJson(e as Map<String, dynamic>))
        .toList();
    return VendorPaymentMethods(
      vendorId: json['vendorId'] as String? ?? '',
      methods: lista,
      cardEnabled: json['cardEnabled'] == true,
      cardPublicKey: json['cardPublicKey'] as String?,
      walletEnabled: json['walletEnabled'] == true,
      walletUnavailableReason: json['walletUnavailableReason'] as String?,
    );
  }
}

/// Lo que hace falta para mandar a alguien a pagar a Mercado Pago.
///
/// No representa un pago: representa el permiso para intentarlo. Cuando esto
/// llega no se ha cobrado nada todavía, y quien decide si se cobró es el
/// webhook — por eso no hay aquí ningún campo de estado.
class WalletCheckout {
  const WalletCheckout({
    required this.orderId,
    required this.initPoint,
    required this.amount,
    this.preferenceId,
  });

  factory WalletCheckout.fromJson(Map<String, dynamic> json) => WalletCheckout(
    orderId: (json['orderId'] ?? '') as String,
    initPoint: (json['initPoint'] ?? '') as String,
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    preferenceId: json['preferenceId'] as String?,
  );

  final String orderId;

  /// URL de Mercado Pago que hay que abrir en el NAVEGADOR del sistema.
  final String initPoint;

  /// El total que se va a cobrar, tal como lo recalculó el servidor. Se usa
  /// para comprobar que coincide con lo que la pantalla venía mostrando.
  final double amount;

  final String? preferenceId;
}
