// TODO: Mercado Pago pendiente para próxima actualización - no eliminar,
// solo descomentar/reactivar cuando esté listo (ver mercado_pago_flag.dart).
// Todo este archivo queda inactivo e inaccesible desde la UI mientras
// kMercadoPagoHabilitado sea false.
import 'package:easy_localization/easy_localization.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/api_error.dart';

/// Tokenización de tarjetas contra la API PÚBLICA de Mercado Pago.
///
/// Esta es la pieza que hace que el número de tarjeta y el CVV NUNCA toquen
/// nuestro servidor: van del dispositivo a `api.mercadopago.com` directamente,
/// autenticados con la MP_PUBLIC_KEY, y lo que vuelve es un token de un solo
/// uso. Ese token es lo único que viaja a nuestro backend.
///
/// Por eso este archivo NO usa el cliente de [ApiService]: nada de lo que
/// pasa por aquí debe poder acabar accidentalmente en una petición a nuestro
/// backend, ni siquiera en un reporte de error.
///
/// Reglas de este archivo:
///  - Nunca se imprime ni se reporta el cuerpo de la petición.
///  - El token devuelto no se guarda en ninguna parte: se usa y se descarta.
///  - Los datos de la tarjeta viven solo en las variables locales de la
///    llamada, el tiempo que tarda en resolverse.
class MpTokenizer {
  MpTokenizer._();

  static const String _base = 'https://api.mercadopago.com';

  /// Cliente propio, deliberadamente separado del de la app.
  static final http.Client _client = http.Client();

  /// Crea un token para una tarjeta NUEVA.
  ///
  /// Endpoint: POST https://api.mercadopago.com/v1/card_tokens
  /// Credencial: MP_PUBLIC_KEY (la sirve GET /api/payments/config).
  ///
  /// [numero] va sin espacios; el formateo del campo es cosa de la UI.
  static Future<String> tokenizarTarjetaNueva({
    required String publicKey,
    required String numero,
    required int mesVencimiento,
    required int anioVencimiento,
    required String cvv,
    required String nombreTitular,
  }) {
    return _pedirToken(publicKey, {
      'card_number': numero.replaceAll(RegExp(r'\s+'), ''),
      'expiration_month': mesVencimiento,
      'expiration_year': anioVencimiento,
      'security_code': cvv,
      'cardholder': {'name': nombreTitular},
    });
  }

  /// Crea un token para una tarjeta YA GUARDADA.
  ///
  /// Endpoint: POST https://api.mercadopago.com/v1/card_tokens
  /// Credencial: MP_PUBLIC_KEY.
  ///
  /// Mercado Pago exige un token nuevo en cada cobro y vuelve a pedir el
  /// CVV aunque la tarjeta esté guardada: es lo que impide que quien
  /// consiga acceso a una sesión pueda gastar con tarjetas ajenas.
  static Future<String> tokenizarTarjetaGuardada({
    required String publicKey,
    required String cardId,
    required String cvv,
  }) {
    return _pedirToken(publicKey, {'card_id': cardId, 'security_code': cvv});
  }

  static Future<String> _pedirToken(
    String publicKey,
    Map<String, dynamic> cuerpo,
  ) async {
    final uri = Uri.parse('$_base/v1/card_tokens?public_key=$publicKey');

    http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(cuerpo),
          )
          .timeout(const Duration(seconds: 20));
    } catch (error) {
      // Se reporta el TIPO de fallo, nunca el cuerpo enviado. Pasar `error`
      // tal cual a registrarErrorTecnico sería seguro hoy (es una excepción
      // de socket), pero este es el único sitio de la app donde una fuga
      // así expondría datos de tarjeta: mejor no depender de eso.
      registrarErrorTecnico(
        'Tokenización de tarjeta: fallo de red (${error.runtimeType})',
        'sin detalle: el cuerpo de esta petición no se registra',
      );
      throw ApiException(
        'card.validate_network_error'.tr(),
        categoria: CategoriaError.sinConexion,
      );
    }

    if (res.statusCode == 200 || res.statusCode == 201) {
      final datos = jsonDecodeSeguro(res.body);
      final token = datos?['id'] as String?;
      if (token != null && token.isNotEmpty) return token;
      throw ApiException(
        'card.validate_error'.tr(),
        categoria: CategoriaError.servidor,
      );
    }

    // Un 4xx aquí son datos de tarjeta mal capturados. El cuerpo del error
    // de MP puede hacer eco de lo enviado, así que NO se registra ni se
    // muestra: se traduce el código a un mensaje propio.
    throw ApiException(
      _mensajeDeErrorDeTokenizacion(res.body),
      categoria: res.statusCode >= 500
          ? CategoriaError.servidor
          : CategoriaError.cliente,
      statusCode: res.statusCode,
    );
  }

  /// Traduce los códigos de validación de MP a algo accionable.
  ///
  /// Solo se lee el campo `code` de la respuesta —un identificador corto y
  /// estable como '324'— y jamás el mensaje libre, que puede contener eco
  /// de los datos enviados.
  static String _mensajeDeErrorDeTokenizacion(String cuerpo) {
    String? codigo;
    try {
      final datos = jsonDecodeSeguro(cuerpo);
      final causas = datos?['cause'];
      if (causas is List && causas.isNotEmpty) {
        codigo = '${(causas.first as Map)['code']}';
      }
    } catch (_) {
      codigo = null;
    }

    switch (codigo) {
      case '205':
        return 'card.number_required'.tr();
      case '208':
      case '209':
        return 'card.expiry_required'.tr();
      case '212':
      case '214':
        return 'card.document_required'.tr();
      case '221':
        return 'card.holder_required'.tr();
      case '224':
        return 'card.cvv_required'.tr();
      case 'E301':
        return 'card.number_invalid_check'.tr();
      case 'E302':
        return 'card.cvv_invalid'.tr();
      case '316':
        return 'card.holder_invalid'.tr();
      case '322':
      case '323':
      case '324':
        return 'card.document_invalid'.tr();
      case '325':
      case '326':
        return 'card.expiry_invalid'.tr();
      default:
        return 'card.review_data'.tr();
    }
  }

  /// Detecta la marca (visa/master/amex…) a partir de los primeros dígitos.
  ///
  /// Endpoint: GET https://api.mercadopago.com/v1/payment_methods/search
  /// Credencial: MP_PUBLIC_KEY.
  ///
  /// Es solo cosmético —sirve para pintar la marca mientras se escribe— así
  /// que cualquier fallo devuelve null en vez de romper el formulario.
  static Future<String?> detectarMetodoDePago({
    required String publicKey,
    required String bin,
  }) async {
    if (bin.length < 6) return null;
    try {
      final res = await _client
          .get(
            Uri.parse(
              '$_base/v1/payment_methods/search'
              '?public_key=$publicKey&bins=${bin.substring(0, 6)}',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final datos = jsonDecodeSeguro(res.body);
      final resultados = datos?['results'];
      if (resultados is List && resultados.isNotEmpty) {
        return (resultados.first as Map)['id'] as String?;
      }
    } catch (_) {
      // Silencio a propósito: es un adorno, no puede bloquear el pago.
    }
    return null;
  }
}
