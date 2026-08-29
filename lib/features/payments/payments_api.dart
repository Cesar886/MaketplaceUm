// TODO: Mercado Pago pendiente para próxima actualización - no eliminar,
// solo descomentar/reactivar cuando esté listo (ver mercado_pago_flag.dart).
// Todo este archivo queda inactivo e inaccesible desde la UI mientras
// kMercadoPagoHabilitado sea false.
import 'package:easy_localization/easy_localization.dart';
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
      await _decodificar(res, fallback: 'payments_api.config_error'.tr()),
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
      await _decodificar(res, fallback: 'payments_api.account_error'.tr()),
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
      fallback: 'payments_api.connect_error'.tr(),
    );
    final url = datos['url'] as String?;
    if (url == null || url.isEmpty) {
      throw ApiException(
        'payments_api.connect_error'.tr(),
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
    await _decodificar(res, fallback: 'payments_api.disconnect_error'.tr());
  }

  // ─── Comprador: tarjetas guardadas ────────────────────────

  /// POST /api/payments/account/validate — comprueba contra Mercado Pago que
  /// la autorización sigue viva.
  ///
  /// Hace falta porque el vendedor puede revocarla desde el panel de Mercado
  /// Pago, fuera de la app. El webhook de revocación suele avisar, pero si se
  /// pierde, sin esto el vendedor seguiría viendo "conectado" durante semanas
  /// mientras sus cobros fallan.
  static Future<bool> validarCuenta() async {
    final res = await ApiService.client.post(
      ApiService.apiUri('/payments/account/validate'),
      headers: ApiService.authHeaders,
    );
    final datos = await _decodificar(
      res,
      fallback: 'payments_api.check_error'.tr(),
    );
    return datos['connected'] == true;
  }

  /// Estado de la cuenta de cobros del vendedor, resuelto de la forma más
  /// fiable posible.
  ///
  /// Se intenta primero [validarCuenta], que es la respuesta REAL (pregunta a
  /// Mercado Pago si la autorización sigue viva). Pero ese endpoint responde
  /// 503 si a la plataforma le falta cualquier variable de entorno de MP, y
  /// además toca la red: tratar cualquiera de esos fallos como "sin conectar"
  /// es cómo un vendedor con su cuenta perfectamente conectada ve
  /// "Sin conectar" para siempre y no tiene forma de saber por qué.
  ///
  /// Por eso el fallback es [getEstadoCuenta] (`GET /payments/account`), que
  /// ni exige la configuración completa ni sale a la red: lee el flag que ya
  /// está guardado. Y si tampoco se puede, se devuelve [EstadoCobros.desconocido]
  /// en vez de mentir en la dirección cómoda.
  static Future<EstadoCobros> estadoDeCobros() async {
    try {
      return await validarCuenta()
          ? EstadoCobros.conectado
          : EstadoCobros.sinConectar;
    } catch (_) {
      try {
        final estado = await getEstadoCuenta();
        return estado.connected
            ? EstadoCobros.conectado
            : EstadoCobros.sinConectar;
      } catch (_) {
        return EstadoCobros.desconocido;
      }
    }
  }

  // ─── Métodos de pago de un vendedor ───────────────────────

  /// GET /api/payments/vendors/:vendorId/methods
  ///
  /// Se consulta EN VIVO al abrir el checkout y no se cachea: entre que el
  /// comprador vio el producto y paga, el vendedor pudo desconectar su
  /// cuenta.
  static Future<VendorPaymentMethods> getMetodosDeVendedor(
    String vendorId,
  ) async {
    final res = await ApiService.client.get(
      ApiService.apiUri('/payments/vendors/$vendorId/methods'),
      headers: ApiService.authHeaders,
    );
    return VendorPaymentMethods.fromJson(
      await _decodificar(res, fallback: 'payments_api.methods_error'.tr()),
    );
  }

  // ─── Comprador: tarjetas guardadas ────────────────────────
  //
  // Todas van con el vendedor en la ruta. Una tarjeta guardada NO es del
  // comprador a secas: vive dentro de la cuenta de Mercado Pago del vendedor
  // con el que se registró, y el token de otro vendedor no puede cobrarla.
  // Por eso el comprador registra su tarjeta una vez por cada vendedor.

  /// GET /api/payments/vendors/:vendorId/cards
  static Future<List<SavedCard>> getTarjetas(String vendorId) async {
    final res = await ApiService.client.get(
      ApiService.apiUri('/payments/vendors/$vendorId/cards'),
      headers: ApiService.authHeaders,
    );
    if (res.statusCode != 200) {
      throw excepcionDeRespuesta(
        res,
        fallback: 'payments_api.cards_error'.tr(),
      );
    }
    final datos = jsonDecode(res.body) as List<dynamic>;
    return datos
        .map((e) => SavedCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/payments/vendors/:vendorId/cards — guarda una tarjeta ya
  /// tokenizada.
  ///
  /// [cardToken] es un token de un solo uso creado por [MpTokenizer] contra
  /// la API pública de Mercado Pago, y con la PUBLIC KEY DEL VENDEDOR — un
  /// token hecho con otra clave no pertenece a esa cuenta y MP lo rechaza.
  /// El número y el CVV NO viajan por aquí: fueron del dispositivo a MP
  /// directamente.
  static Future<SavedCard> guardarTarjeta(
    String vendorId,
    String cardToken,
  ) async {
    final res = await ApiService.client.post(
      ApiService.apiUri('/payments/vendors/$vendorId/cards'),
      headers: ApiService.authHeaders,
      body: jsonEncode({'token': cardToken}),
    );
    return SavedCard.fromJson(
      await _decodificar(
        res,
        esperado: 201,
        fallback: 'payments_api.save_card_error'.tr(),
      ),
    );
  }

  /// DELETE /api/payments/vendors/:vendorId/cards/:cardId
  static Future<void> eliminarTarjeta(String vendorId, String cardId) async {
    final res = await ApiService.client.delete(
      ApiService.apiUri('/payments/vendors/$vendorId/cards/$cardId'),
      headers: ApiService.authHeaders,
    );
    await _decodificar(res, fallback: 'payments_api.delete_card_error'.tr());
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

  static Future<List<PaymentOrder>> _crearOrden(
    Map<String, dynamic> body,
  ) async {
    final res = await ApiService.client.post(
      ApiService.apiUri('/orders'),
      headers: ApiService.authHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) {
      throw excepcionDeRespuesta(
        res,
        fallback: 'payments_api.create_order_error'.tr(),
      );
    }
    final datos = jsonDecode(res.body) as List<dynamic>;
    return datos
        .map((e) => PaymentOrder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/orders/:id — el estado ACTUAL de una orden.
  ///
  /// Es la única forma de saber cómo acabó un pago hecho con la cuenta de
  /// Mercado Pago: ese cobro ocurre fuera de la app y a nadie se le devuelve
  /// un resultado. Quien escribe la verdad es el webhook, y esto la lee.
  static Future<PaymentOrder> getOrden(String orderId) async {
    final res = await ApiService.client.get(
      ApiService.apiUri('/orders/$orderId'),
      headers: ApiService.authHeaders,
    );
    return PaymentOrder.fromJson(
      await _decodificar(res, fallback: 'payments_api.order_error'.tr()),
    );
  }

  /// GET /api/orders?role=buyer|vendor
  static Future<List<PaymentOrder>> getOrdenes({
    bool comoVendedor = false,
  }) async {
    final res = await ApiService.client.get(
      ApiService.apiUri('/orders', {'role': comoVendedor ? 'vendor' : 'buyer'}),
      headers: ApiService.authHeaders,
    );
    if (res.statusCode != 200) {
      throw excepcionDeRespuesta(
        res,
        fallback: 'payments_api.orders_error'.tr(),
      );
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
      await _decodificar(res, fallback: 'payments_api.process_error'.tr()),
    );
  }

  /// POST /api/payments/checkout/wallet — prepara el pago con la cuenta de
  /// Mercado Pago del comprador.
  ///
  /// Cobra la MISMA orden que [pagar] y pasa por las mismas comprobaciones
  /// del servidor (vendedor abierto, con stock, con la cuenta viva) y por el
  /// mismo total recalculado allí: el monto no viaja desde el dispositivo en
  /// ninguno de los dos caminos.
  ///
  /// Devolver esto NO es haber pagado. Lo único que llega es la URL a la que
  /// mandar a la persona; el resultado se descubre después consultando la
  /// orden con [getOrden].
  static Future<WalletCheckout> iniciarPagoConCuentaMp(String orderId) async {
    final res = await ApiService.client.post(
      ApiService.apiUri('/payments/checkout/wallet'),
      headers: ApiService.authHeaders,
      body: jsonEncode({'order_id': orderId}),
    );
    return WalletCheckout.fromJson(
      await _decodificar(res, fallback: 'payments_api.start_error'.tr()),
    );
  }
}
