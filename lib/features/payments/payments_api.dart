import 'dart:convert';

import '../../services/api_error.dart';
import '../../services/api_service.dart';
import 'payment_models.dart';

/// Llamadas al backend relacionadas con pagos.
///
/// Reutiliza el cliente HTTP de [ApiService] (`ApiService.client`) en vez de
/// crear uno propio: así estas llamadas también pasan por la detección de
/// `SESSION_INVALIDATED` y por la traducción de errores de red, y ningún
/// `SocketException` con la IP del servidor puede llegar a la pantalla.
///
/// Los errores salen siempre como [ApiException], igual que en el resto de
/// la app; las pantallas los pintan con `mensajeDeError()`.
class PaymentsApi {
  PaymentsApi._();

  static Future<Map<String, dynamic>> _decodificar(
    dynamic res, {
    required String fallback,
    int esperado = 200,
  }) async {
    if (res.statusCode != esperado) {
      throw excepcionDeRespuesta(res, fallback: fallback);
    }
    return jsonDecodeSeguro(res.body) ?? <String, dynamic>{};
  }

  // ─── Configuración ────────────────────────────────────────

  /// GET /api/payments/config — trae la clave pública de Mercado Pago.
  static Future<PaymentsConfig> getConfig() async {
    final res = await ApiService.client.get(
      ApiService.apiUri('/payments/config'),
      headers: ApiService.authHeaders,
    );
    return PaymentsConfig.fromJson(
      await _decodificar(res, fallback: 'No se pudo cargar la configuración de pagos.'),
    );
  }

  // ─── Vendedor: conectar Mercado Pago ──────────────────────

  /// GET /api/payments/account — si el vendedor ya conectó su cuenta.
  static Future<VendorAccountStatus> getEstadoCuenta() async {
    final res = await ApiService.client.get(
      ApiService.apiUri('/payments/account'),
      headers: ApiService.authHeaders,
    );
    return VendorAccountStatus.fromJson(
      await _decodificar(res, fallback: 'No se pudo consultar tu cuenta de pagos.'),
    );
  }

  /// GET /api/payments/oauth/connect — devuelve la URL de autorización de
  /// Mercado Pago que hay que abrir en el navegador.
  static Future<String> getUrlConexion() async {
    final res = await ApiService.client.get(
      ApiService.apiUri('/payments/oauth/connect'),
      headers: ApiService.authHeaders,
    );
    final datos = await _decodificar(
      res,
      fallback: 'No se pudo iniciar la conexión con Mercado Pago.',
    );
    final url = datos['url'] as String?;
    if (url == null || url.isEmpty) {
      throw const ApiException(
        'No se pudo iniciar la conexión con Mercado Pago.',
        categoria: CategoriaError.servidor,
      );
    }
    return url;
  }

  /// DELETE /api/payments/account — desvincula la cuenta.
  static Future<void> desconectarCuenta() async {
    final res = await ApiService.client.delete(
      ApiService.apiUri('/payments/account'),
      headers: ApiService.authHeaders,
    );
    await _decodificar(res, fallback: 'No se pudo desconectar tu cuenta.');
  }

  // ─── Comprador: tarjetas guardadas ────────────────────────

  /// GET /api/payments/cards
  static Future<List<SavedCard>> getTarjetas() async {
    final res = await ApiService.client.get(
      ApiService.apiUri('/payments/cards'),
      headers: ApiService.authHeaders,
    );
    if (res.statusCode != 200) {
      throw excepcionDeRespuesta(res, fallback: 'No se pudieron cargar tus tarjetas.');
    }
    final datos = jsonDecode(res.body) as List<dynamic>;
    return datos
        .map((e) => SavedCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/payments/cards — guarda una tarjeta ya tokenizada.
  ///
  /// [cardToken] es un token de un solo uso creado por [MpTokenizer] contra
  /// la API pública de Mercado Pago. El número y el CVV NO viajan por aquí:
  /// fueron del dispositivo a MP directamente.
  static Future<SavedCard> guardarTarjeta(String cardToken) async {
    final res = await ApiService.client.post(
      ApiService.apiUri('/payments/cards'),
      headers: ApiService.authHeaders,
      body: jsonEncode({'token': cardToken}),
    );
    return SavedCard.fromJson(
      await _decodificar(
        res,
        esperado: 201,
        fallback: 'No se pudo guardar la tarjeta.',
      ),
    );
  }

  /// DELETE /api/payments/cards/:cardId
  static Future<void> eliminarTarjeta(String cardId) async {
    final res = await ApiService.client.delete(
      ApiService.apiUri('/payments/cards/$cardId'),
      headers: ApiService.authHeaders,
    );
    await _decodificar(res, fallback: 'No se pudo eliminar la tarjeta.');
  }

  // ─── Órdenes ──────────────────────────────────────────────

  /// POST /api/orders — compra directa de un producto.
  ///
  /// Devuelve una lista porque el backend agrupa por vendedor; en compra
  /// directa siempre trae exactamente una orden.
  static Future<List<PaymentOrder>> crearOrdenDirecta(
    String productId, {
    int quantity = 1,
  }) => _crearOrden({'productId': productId, 'quantity': quantity});

  /// POST /api/orders con `fromCart` — una orden POR VENDEDOR.
  static Future<List<PaymentOrder>> crearOrdenesDesdeCarrito() =>
      _crearOrden({'fromCart': true});

  static Future<List<PaymentOrder>> _crearOrden(Map<String, dynamic> body) async {
    final res = await ApiService.client.post(
      ApiService.apiUri('/orders'),
      headers: ApiService.authHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) {
      throw excepcionDeRespuesta(res, fallback: 'No se pudo crear la orden.');
    }
    final datos = jsonDecode(res.body) as List<dynamic>;
    return datos
        .map((e) => PaymentOrder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/orders?role=buyer|vendor
  static Future<List<PaymentOrder>> getOrdenes({bool comoVendedor = false}) async {
    final res = await ApiService.client.get(
      ApiService.apiUri('/orders', {'role': comoVendedor ? 'vendor' : 'buyer'}),
      headers: ApiService.authHeaders,
    );
    if (res.statusCode != 200) {
      throw excepcionDeRespuesta(res, fallback: 'No se pudieron cargar tus compras.');
    }
    final datos = jsonDecode(res.body) as List<dynamic>;
    return datos
        .map((e) => PaymentOrder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Checkout ─────────────────────────────────────────────

  /// POST /api/payments/checkout — cobra la orden.
  ///
  /// [cardToken] se genera SIEMPRE justo antes de llamar aquí, incluso con
  /// una tarjeta guardada: Mercado Pago exige un token nuevo por cobro y
  /// pide el CVV de nuevo. Ese token es de un solo uso y no se guarda.
  ///
  /// Un 409 del backend significa que el vendedor todavía no puede recibir
  /// pagos; su mensaje ya viene redactado para mostrarse tal cual.
  static Future<CheckoutResult> pagar({
    required String orderId,
    required String cardToken,
    String? paymentMethodId,
    String? issuerId,
    int installments = 1,
  }) async {
    final res = await ApiService.client.post(
      ApiService.apiUri('/payments/checkout'),
      headers: ApiService.authHeaders,
      body: jsonEncode({
        'order_id': orderId,
        'card_token': cardToken,
        'installments': installments,
        if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
        if (issuerId != null) 'issuer_id': issuerId,
      }),
    );
    return CheckoutResult.fromJson(
      await _decodificar(res, fallback: 'No se pudo procesar el pago.'),
    );
  }
}
