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

class CheckoutResult {
  const CheckoutResult({
    required this.orderId,
    required this.estado,
    required this.amount,
    this.statusDetail,
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

  final String orderId;
  final EstadoPago estado;
  final double amount;

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
            return 'El pago fue rechazado. Intenta con otra tarjeta.';
        }
    }
  }
}

/// Estado de la cuenta de Mercado Pago de un vendedor.
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
