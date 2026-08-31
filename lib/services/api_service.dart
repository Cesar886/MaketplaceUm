import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../config/app_config.dart';
import 'anonymous_id.dart';
import 'api_error.dart';

/// Cliente HTTP que vigila TODAS las respuestas del backend en busca de un
/// 401 `SESSION_INVALIDATED`, sin que cada endpoint tenga que acordarse de
/// comprobarlo, y que traduce los fallos de red antes de que salgan de aquí.
///
/// Ese 401 significa que el JWT guardado se firmó con un `JWT_SECRET` que ya
/// no es el vigente (ver `backend/src/auth.js`): la firma no valida y el
/// token no es recuperable por ningún reintento. Se dispara una sola vez
/// [ApiService.onSesionInvalidada], que cierra sesión y manda al login.
///
/// La traducción de errores va AQUÍ y no en cada método porque este `send`
/// es el único sitio por el que pasan las 50 y pico llamadas del servicio:
/// puesto aquí, ninguna puede olvidarse. Lo que sale es siempre una
/// [ApiException] con mensaje presentable — nunca el `SocketException` con
/// la IP y el puerto del servidor, que es justo lo que se estaba pintando en
/// la pantalla de chat.
class _SessionAwareClient extends http.BaseClient {
  _SessionAwareClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.StreamedResponse res;
    try {
      res = await _inner.send(request);
    } on ApiException {
      rethrow;
    } catch (error, stack) {
      // Socket cerrado, DNS que no resuelve, TLS roto, timeout del sistema:
      // todo eso muere aquí y se convierte en un mensaje seguro. El detalle
      // real queda en el log de debug.
      throw ApiException.deRed(error, stack: stack);
    }
    if (res.statusCode != 401) return res;

    // El cuerpo de una respuesta en streaming solo puede leerse una vez, así
    // que se materializa y se reconstruye la respuesta para que quien llamó
    // la reciba intacta y pueda seguir generando su propio mensaje de error.
    final bytes = await res.stream.toBytes();
    // Cualquier 401 con Authorization presente significa que el token que
    // mandamos ya no sirve — firma inválida (SESSION_INVALIDATED), expirado
    // (`requireAuth` en el backend), o corrupto. Antes solo se reaccionaba a
    // SESSION_INVALIDATED, así que un JWT de cuenta real que expiraba a las
    // 24h (a diferencia del anónimo, que sí se auto-renueva) se quedaba
    // fallando en silencio hasta que el usuario cerraba sesión a mano.
    if (request.headers.containsKey('Authorization')) {
      ApiService.notificarSesionInvalidada();
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      res.statusCode,
      contentLength: bytes.length,
      request: res.request,
      headers: res.headers,
      isRedirect: res.isRedirect,
      persistentConnection: res.persistentConnection,
      reasonPhrase: res.reasonPhrase,
    );
  }
}

/// Error de un endpoint de verificación, con el mensaje textual del backend.
///
/// Conserva [campo] para que la pantalla pueda resaltar exactamente el dato
/// que falló, y [puedeReintentarEn] (minutos) cuando el rechazo viene del
/// límite de envío de códigos.
class VerificacionException implements Exception {
  const VerificacionException(
    this.mensaje, {
    this.campo,
    this.statusCode,
    this.puedeReintentarEn,
    this.sesionInvalidada = false,
    this.yaVerificado = false,
  });

  final String mensaje;
  final String? campo;
  final int? statusCode;
  final int? puedeReintentarEn;

  /// El JWT guardado se firmó con un `JWT_SECRET` que ya no es el vigente
  /// (ver `backend/src/auth.js`): la firma no valida y el token no es
  /// recuperable. La pantalla debe cerrar sesión y mandar al login — no
  /// tiene sentido mostrarlo como un error del formulario.
  final bool sesionInvalidada;

  /// La cuenta ya estaba verificada: no es un error que deba alarmar, la
  /// pantalla simplemente refresca y cierra.
  ///
  /// Viene del campo `ya_verificado` del cuerpo, NO del status code: el
  /// backend usa 409 también para "ese correo/teléfono ya está registrado en
  /// OTRA cuenta" (`verificacion.js` en `/estudiante/solicitar` y
  /// `/externo/solicitar`), que es un error que el usuario sí debe ver y
  /// corregir, no una señal para cerrar la pantalla en silencio.
  final bool yaVerificado;

  /// Se agotaron los códigos permitidos en la ventana de 15 minutos.
  bool get demasiadosIntentos => statusCode == 429;

  @override
  String toString() => mensaje;
}

/// Servicio centralizado para consumir la API REST de Marketplace UM.
///
/// Auto-detecta la URL base según plataforma / entorno.
/// Si falla, usa [customBaseUrl] para override manual.
class ApiService {
  ApiService._();

  static http.Client _client = _SessionAwareClient(http.Client());

  /// Sustituye el cliente HTTP. Solo para tests de widget: el binding de
  /// `flutter_test` intercepta HttpClient y devuelve 400 a cualquier
  /// petición real, así que una pantalla que consulta la API solo se puede
  /// probar de punta a punta inyectando un cliente falso aquí.
  @visibleForTesting
  static set clienteDePrueba(http.Client cliente) {
    _client = cliente;
  }

  /// Devuelve el cliente real, para deshacer [clienteDePrueba] al terminar.
  @visibleForTesting
  static void restaurarCliente() {
    _client = _SessionAwareClient(http.Client());
  }

  /// El mismo cliente HTTP, para módulos que viven fuera de esta clase
  /// (`lib/features/payments/`). Se expone en vez de dejar que creen su
  /// propio `http.Client` para que TODAS las llamadas al backend sigan
  /// pasando por la detección de `SESSION_INVALIDATED` y por la traducción
  /// de errores de red — un cliente aparte se saltaría las dos cosas.
  static http.Client get client => _client;

  /// Cabeceras con el JWT del usuario. Misma razón que [client]: que nadie
  /// tenga que reconstruir el header de autorización por su cuenta.
  static Map<String, String> get authHeaders => _authHeaders;

  /// Construye una URL de la API (`$baseUrl/api$path`).
  static Uri apiUri(String path, [Map<String, String>? query]) =>
      _uri(path, query);

  /// Se invoca cuando el backend responde `SESSION_INVALIDATED` en cualquier
  /// endpoint. La app lo engancha en `main.dart` para cerrar sesión y llevar
  /// al login. Se deja como callback y no como navegación directa para que
  /// esta capa siga sin depender de Flutter.
  static void Function()? onSesionInvalidada;

  /// Evita que varias peticiones en paralelo que fallan con el mismo token
  /// muerto disparen varios logout y varios push al login encimados.
  static bool _sesionYaInvalidada = false;

  static void notificarSesionInvalidada() {
    if (_sesionYaInvalidada) return;
    _sesionYaInvalidada = true;
    clearToken();
    onSesionInvalidada?.call();
  }

  /// Override programático (alternativa a la constante _backendHost).
  static String? _customBaseUrl;

  // ─── Token JWT para rutas protegidas ─────────────────────────
  // El token se asigna desde AuthProvider cuando el usuario inicia sesión.
  // Ya NO se hardcodea 's1' — cada usuario tiene su propio token.
  static String? _token;

  /// Asigna el token JWT del usuario autenticado para usarlo en requests.
  static void setToken(String token) {
    _token = token;
    // Token nuevo (login o registro): vuelve a armarse el disparo, si no un
    // SESSION_INVALIDATED de la sesión anterior dejaría mudo al siguiente.
    _sesionYaInvalidada = false;
  }

  /// Limpia el token (logout).
  static void clearToken() {
    _token = null;
  }

  /// Token de la sesión actual, para quien no pasa por [_authHeaders]: el
  /// handshake de Socket.IO, que autentica por payload y no por cabecera.
  static String? get token => _token;

  static Map<String, String> get _authHeaders {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  /// ─── CONFIGURACIÓN DEL BACKEND ─────────────────────────────
  /// URL base del backend. Usa AppConfig siempre, a menos que haya override.
  static String get baseUrl {
    if (_customBaseUrl != null) return _customBaseUrl!;
    return AppConfig.apiBaseUrl;
  }

  /// Override programático de la URL (alternativa a _backendHost).
  static set customBaseUrl(String url) {
    _customBaseUrl = url;
  }

  static Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl/api$path').replace(queryParameters: query);
  }

  /// GET con reintentos automáticos ante errores de conexión transitorios
  /// (ej. "Connection closed before full header was received", que ocurre
  /// de forma intermitente cuando el cliente reutiliza una conexión
  /// keep-alive que el servidor ya cerró por inactividad). Solo se reintenta
  /// en fallos de conexión/socket, nunca en respuestas HTTP con error (esas
  /// las maneja cada método según su propio código de estado). Es seguro
  /// reintentar GET porque son idempotentes.
  static Future<http.Response> _getWithRetry(
    Uri uri, {
    Map<String, String>? headers,
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _client.get(uri, headers: headers);
      } on ApiException catch (e) {
        // El cliente ya tradujo el fallo de red. Se reintenta solo lo que
        // puede arreglarse solo (conexión cortada, timeout, 5xx pasajero);
        // un error definitivo se propaga sin gastar tres intentos.
        if (!e.valeLaPenaReintentar || attempt >= maxAttempts) rethrow;
      }
      await Future.delayed(Duration(milliseconds: 300 * attempt));
    }
  }

  // ─── Auth / Registro ──────────────────────────────────────

  /// Llama a POST /api/auth/register. El backend es la autoridad real de
  /// credenciales: guarda el password (hasheado) y devuelve un JWT. Crea el
  /// perfil de vendedor si no existe; si el email ya existe, se comporta
  /// como un login (verifica el password) y solo entonces re-sincroniza.
  static Future<Map<String, dynamic>> registerBackendUser({
    required String name,
    required String email,
    required String userType,
    required String password,
    String? phone,
    String? deviceId,
    Map<int, BusinessHoursRange>? businessHours,
    required List<String> paymentMethods,
  }) async {
    final res = await _client.post(
      _uri('/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'userType': userType,
        'password': password,
        if (phone != null) 'phone': phone,
        if (deviceId != null) 'deviceId': deviceId,
        if (businessHours != null)
          'businessHours': businessHoursToJson(businessHours),
        'paymentMethods': paymentMethods,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(
        body['error'] ?? 'Error al sincronizar usuario con el backend',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Llama a POST /api/auth/login: valida email+password contra el backend
  /// (única autoridad real de credenciales) y devuelve token + seller.
  /// Devuelve `null` si las credenciales son incorrectas (401); lanza
  /// excepción ante cualquier otro error (red, 5xx, etc.).
  static Future<Map<String, dynamic>?> loginBackend({
    required String email,
    required String password,
    String? deviceId,
  }) async {
    final res = await _client.post(
      _uri('/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        if (deviceId != null) 'deviceId': deviceId,
      }),
    );
    if (res.statusCode == 401) return null;
    if (res.statusCode != 200) {
      throw Exception('errors.login_failed'.tr());
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Llama a POST /api/auth/google con el idToken que emitió Google en el
  /// dispositivo. El backend lo verifica contra las claves públicas de
  /// Google y devuelve **la misma** respuesta que /auth/login (`token` +
  /// `seller`), para que la app no tenga dos caminos distintos de "qué pasa
  /// después de iniciar sesión".
  ///
  /// Tres desenlaces:
  ///  - La cuenta existe (o [registro] venía puesto): devuelve token+seller.
  ///  - No existe y no se mandó [registro]: lanza
  ///    [GoogleRegistroRequeridoException] con el perfil de Google, para
  ///    llevar al formulario de registro ya prellenado.
  ///  - Cualquier otro rechazo del servidor: lanza [GoogleAuthException] con
  ///    el código del backend (GOOGLE_NO_CONFIGURADO, GOOGLE_TOKEN_INVALIDO,
  ///    GOOGLE_DOMINIO_NO_PERMITIDO…).
  ///
  /// [registro] son los datos que el idToken no puede traer y el registro de
  /// este marketplace sí exige: tipo de cuenta, teléfono y métodos de pago.
  static Future<Map<String, dynamic>> authGoogle({
    required String idToken,
    String? deviceId,
    Map<String, dynamic>? registro,
  }) async {
    final res = await _client.post(
      _uri('/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        if (deviceId != null) 'deviceId': deviceId,
        if (registro != null) 'registro': registro,
      }),
    );

    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      // Un 502 del proxy no trae JSON; sin esto el usuario vería una
      // excepción de parseo en vez de un mensaje.
      throw GoogleAuthException(
        'HTTP_${res.statusCode}',
        'errors.login_failed'.tr(),
      );
    }

    if (res.statusCode == 200 || res.statusCode == 201) return body;

    final codigo = body['error'] as String? ?? 'HTTP_${res.statusCode}';
    if (codigo == 'GOOGLE_ACCOUNT_NOT_FOUND') {
      final google = (body['google'] as Map?)?.cast<String, dynamic>() ?? {};
      throw GoogleRegistroRequeridoException(
        email: google['email'] as String? ?? '',
        nombre: google['name'] as String? ?? '',
        foto: google['picture'] as String?,
      );
    }
    // `error` trae un código-máquina en las rutas de Google y la frase para
    // el usuario va en `message` (mismo criterio que los 401 de auth.js);
    // pero el resto de validaciones del registro mandan la frase en `error`.
    throw GoogleAuthException(
      codigo,
      body['message'] as String? ?? codigo,
    );
  }

  // ─── Verificación de cuenta ─────────────────────────────
  //
  // El backend resuelve la verificación automáticamente (sin revisión
  // humana) y es la única autoridad sobre `verified`. Todos estos endpoints
  // toman el usuario del JWT, así que nunca se manda un id de usuario.

  /// Decodifica la respuesta de un endpoint de verificación, propagando el
  /// mensaje real del servidor en el error para poder mostrarlo tal cual al
  /// usuario (ej. "La matrícula no coincide con tu correo institucional").
  static Map<String, dynamic> _decodeVerificacion(http.Response res) {
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      // `error` es ambiguo en el backend: en la mayoría de rutas trae una
      // frase ya redactada para el usuario, pero en los 401 de auth.js trae
      // un código-máquina (SESSION_INVALIDATED) y la frase va en `message`.
      // Se prefiere `message` cuando existe, para no pintar el código crudo
      // en la caja de error de la pantalla.
      final codigo = body['error'] as String?;
      throw VerificacionException(
        body['message'] as String? ??
            codigo ??
            'errors.verification_failed'.tr(),
        campo: body['campo'] as String?,
        statusCode: res.statusCode,
        puedeReintentarEn: (body['puede_reintentar_en'] as num?)?.toInt(),
        sesionInvalidada: codigo == 'SESSION_INVALIDATED',
        yaVerificado: body['ya_verificado'] == true,
      );
    }
    return body;
  }

  /// Tope de espera de los endpoints de verificación. El envío del OTP sale a
  /// un SMTP externo: si ese proveedor se cuelga, sin este límite el botón se
  /// queda cargando para siempre. Es holgado respecto al timeout SMTP del
  /// backend (10 s por fase) para que gane el error del servidor, que es más
  /// específico, y este solo actúe si el backend ni siquiera contesta.
  static const _timeoutVerificacion = Duration(seconds: 15);

  static Future<Map<String, dynamic>> _postVerificacion(
    String path,
    Map<String, dynamic> body,
  ) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            _uri('/verificacion$path'),
            headers: _authHeaders,
            body: jsonEncode(body),
          )
          .timeout(_timeoutVerificacion);
    } on TimeoutException {
      throw VerificacionException('errors.server_timeout'.tr());
    }
    return _decodeVerificacion(res);
  }

  /// Envía el código OTP al correo institucional. La matrícula no viaja
  /// aparte: el backend la extrae de los 7 dígitos del correo.
  ///
  /// [tipo] es 'estudiante' o 'empleado' y va EXPLÍCITO: el servidor no lo
  /// deduce del dominio, lo contrasta contra el correo y rechaza con 400 si
  /// no corresponden. [carrera] solo aplica al alumno; para el personal se
  /// omite del cuerpo.
  static Future<Map<String, dynamic>> solicitarVerificacionEstudiante({
    required String correoInstitucional,
    required String tipo,
    String? carrera,
  }) {
    return _postVerificacion('/estudiante/solicitar', {
      'correo_institucional': correoInstitucional,
      'tipo': tipo,
      if (carrera != null) 'carrera': carrera,
    });
  }

  static Future<Map<String, dynamic>> confirmarVerificacionEstudiante(
    String codigoOtp,
  ) {
    return _postVerificacion('/estudiante/confirmar', {
      'codigo_otp': codigoOtp,
    });
  }

  /// Verifica un negocio. A diferencia de los flujos con OTP, resuelve en una
  /// sola llamada: la respuesta trae `estado` 'verificado' o 'rechazado'.
  static Future<Map<String, dynamic>> verificarNegocio({
    required String nombreNegocio,
    required double lat,
    required double lng,
    required String linkRedSocial,
  }) {
    return _postVerificacion('/negocio/solicitar', {
      'nombre_negocio': nombreNegocio,
      'ubicacion_lat': lat,
      'ubicacion_lng': lng,
      'link_red_social': linkRedSocial,
    });
  }

  static Future<Map<String, dynamic>> solicitarVerificacionExterno(
    String telefono,
  ) {
    return _postVerificacion('/externo/solicitar', {'telefono': telefono});
  }

  static Future<Map<String, dynamic>> confirmarVerificacionExterno(
    String codigoOtp,
  ) {
    return _postVerificacion('/externo/confirmar', {'codigo_otp': codigoOtp});
  }

  /// Estado de verificación del usuario autenticado. Lo consultan tanto el
  /// registro como el perfil.
  static Future<Map<String, dynamic>> getEstadoVerificacion() async {
    final http.Response res;
    try {
      res = await _client
          .get(_uri('/verificacion/estado'), headers: _authHeaders)
          .timeout(_timeoutVerificacion);
    } on TimeoutException {
      throw VerificacionException('errors.server_timeout'.tr());
    }
    return _decodeVerificacion(res);
  }

  // ─── Health ─────────────────────────────────────────────
  static Future<bool> healthCheck() async {
    try {
      final res = await _client
          .get(_uri('/health'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─── Categories ─────────────────────────────────────────
  static Future<List<MarketplaceCategory>> getCategories() async {
    final res = await _getWithRetry(_uri('/categories'));
    if (res.statusCode != 200) throw Exception('Error fetching categories');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => MarketplaceCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Todas las categorías ordenadas por actividad reciente de la comunidad
  /// (publicaciones, vistas de producto, toques de ícono). Fuente única de
  /// orden para los íconos de categoría en home y búsqueda.
  static Future<List<MarketplaceCategory>> getCategoriesRanked() async {
    final res = await _getWithRetry(_uri('/categories/ranked'));
    if (res.statusCode != 200)
      throw Exception('Error fetching ranked categories');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => MarketplaceCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Registra que se tocó el ícono de una categoría (señal de interés,
  /// peso bajo en el score de orden). Fire-and-forget: nunca debe bloquear
  /// ni fallar de forma visible la navegación que disparó el toque.
  static Future<void> registerCategoryTap(String categoryId) async {
    try {
      await _client.post(_uri('/categories/$categoryId/tap'));
    } catch (_) {
      // Best-effort: si falla, simplemente no se contó este toque.
    }
  }

  // ─── Search ─────────────────────────────────────────────

  /// Términos más buscados por la comunidad en los últimos días (backend
  /// decide la ventana y el límite). Puede devolver [] si no hay data
  /// suficiente todavía — el llamador debe caer a un placeholder estático.
  static Future<List<String>> getTrendingSearches() async {
    final res = await _getWithRetry(_uri('/search/trending'));
    if (res.statusCode != 200) {
      throw Exception('Error fetching trending searches');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['terms'] as List<dynamic>).cast<String>();
  }

  /// Registra una búsqueda ejecutada por el usuario (al presionar
  /// buscar/enter, nunca por cada tecla).
  ///
  /// Manda el ID anónimo del dispositivo porque el backend rankea por
  /// personas distintas, no por tecleos: sin él, quien busque lo mismo veinte
  /// veces se adueña del placeholder de toda la comunidad.
  ///
  /// El Future se devuelve para poder recargar las tendencias justo después
  /// (así el usuario ve el efecto de su propia búsqueda), pero nunca falla ni
  /// se propaga hacia arriba: una búsqueda del usuario no puede romperse
  /// porque el tracking no llegó al servidor.
  static Future<void> recordSearchQuery(String text) async {
    final trimmed = text.trim();
    if (trimmed.length < 2 || trimmed.length > 60) return;
    try {
      final deviceId = await AnonymousId.get();
      await _client.post(
        _uri('/search/track'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': trimmed, 'deviceId': deviceId}),
      );
    } catch (_) {
      // Best-effort: si no se pudo contar, la búsqueda del usuario ya se hizo.
    }
  }

  // ─── Interacciones (señal conductual) ───────────────────
  //
  // Alimentan dos cosas a la vez: el ranking de afinidad del feed y el score
  // de interés por categoría que decide los avisos de publicaciones nuevas.
  // Sin estas llamadas el backend no tiene ninguna señal de qué le interesa
  // a cada persona, así que el feed sale plano y no se envía retargeting.
  //
  // Todas son best-effort y silenciosas por diseño: el tracking nunca puede
  // romper ni frenar la acción que el usuario acaba de hacer. Por eso no se
  // esperan (`unawaited`) desde las pantallas ni devuelven error.
  //
  // El `userId` NO se manda: el backend lo saca del JWT. Lo que se manda es
  // el id anónimo del dispositivo, que es también el id con el que ese
  // dispositivo registra su token FCM, para que un usuario sin cuenta pueda
  // recibir el aviso igual.
  static Future<void> _registrarInteraccion(Map<String, dynamic> cuerpo) async {
    try {
      final deviceId = await AnonymousId.get();
      await _client.post(
        _uri('/interacciones'),
        headers: _authHeaders,
        body: jsonEncode({'deviceId': deviceId, ...cuerpo}),
      );
    } catch (_) {
      // Best-effort: ver comentario del bloque.
    }
  }

  /// El usuario abrió la ficha de un producto.
  static Future<void> registrarVistaProducto(String productId) =>
      _registrarInteraccion({'tipo': 'vista', 'productId': productId});

  /// El usuario guardó un producto en favoritos.
  static Future<void> registrarFavorito(String productId) =>
      _registrarInteraccion({'tipo': 'favorito', 'productId': productId});

  /// El usuario contactó al vendedor (chat o WhatsApp). Es la señal más
  /// fuerte de intención de compra que produce la app.
  static Future<void> registrarContacto(String productId) =>
      _registrarInteraccion({'tipo': 'contacto', 'productId': productId});

  /// El usuario entró a navegar una categoría, sin abrir nada todavía.
  ///
  /// Va por `/categories/:id/tap` en vez de por `/interacciones` porque ese
  /// endpoint registra el gesto en los dos sitios que lo necesitan de una
  /// sola llamada: el agregado global que ordena los íconos de categoría, y
  /// la señal personal que puntúa el interés de quien tocó.
  static Future<void> registrarVistaCategoria(String categoryId) async {
    try {
      final deviceId = await AnonymousId.get();
      await _client.post(
        _uri('/categories/$categoryId/tap'),
        headers: _authHeaders,
        body: jsonEncode({'deviceId': deviceId}),
      );
    } catch (_) {
      // Best-effort: ver comentario del bloque.
    }
  }

  // ─── Preferencias de notificación ───────────────────────

  /// Tipo de notificación de retargeting; debe coincidir con
  /// `TIPO_RETARGETING` en backend/src/notifications/frecuencia.js.
  static const notifInteresNuevosProductos = 'interest_new_product';

  /// Sin sesión, el sujeto de las preferencias es el id anónimo del
  /// dispositivo: recibe pushes, así que también tiene que poder apagarlos.
  static Future<String?> _subjectIdAnonimo() async =>
      _token == null ? await AnonymousId.get() : null;

  /// Preferencias del usuario. Ausencia de dato = habilitado (opt-out), así
  /// que ante un fallo de red se asume habilitado y no se apaga nada solo.
  static Future<Map<String, bool>> getNotificationPreferences() async {
    final subjectId = await _subjectIdAnonimo();
    final res = await _client.get(
      _uri('/notifications/preferences', {
        if (subjectId != null) 'subjectId': subjectId,
      }),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) {
      throw Exception('No se pudieron cargar las preferencias');
    }
    final prefs = (jsonDecode(res.body) as Map<String, dynamic>)['preferences']
        as Map<String, dynamic>;
    return prefs.map((k, v) => MapEntry(k, v == true));
  }

  static Future<void> setNotificationPreference({
    required String type,
    required bool enabled,
  }) async {
    final subjectId = await _subjectIdAnonimo();
    final res = await _client.put(
      _uri('/notifications/preferences'),
      headers: _authHeaders,
      body: jsonEncode({
        'type': type,
        'enabled': enabled,
        if (subjectId != null) 'subjectId': subjectId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('No se pudo guardar la preferencia');
    }
  }

  /// Avisa de que el usuario abrió un push de publicaciones nuevas.
  ///
  /// No es solo telemetría: la reducción adaptativa del backend pausa una
  /// categoría tras tres avisos seguidos sin abrir. Si la app deja de llamar
  /// aquí, el sistema concluye que a nadie le interesa nada y se apaga solo.
  static Future<void> registrarAperturaInteres({
    String? notificationId,
    String? categoryId,
  }) async {
    if (notificationId == null && categoryId == null) return;
    try {
      final subjectId = await _subjectIdAnonimo();
      await _client.post(
        _uri('/notifications/interest-opened'),
        headers: _authHeaders,
        body: jsonEncode({
          if (notificationId != null) 'notificationId': notificationId,
          if (categoryId != null) 'categoryId': categoryId,
          if (subjectId != null) 'subjectId': subjectId,
        }),
      );
    } catch (_) {
      // Best-effort: perder una apertura sesga la métrica, no rompe la app.
    }
  }

  // ─── Products ───────────────────────────────────────────
  static Future<List<Product>> getProducts({
    String? category,
    // TODO: Destacar publicaciones pendiente para próxima actualización -
    // no eliminar. Ninguna pantalla pasa `featured: true` mientras la feature
    // esté apagada (ver features/highlight/destacar_flag.dart).
    bool? featured,
    bool? offer,
    String? search,
    String? seller,
    String? userId,
  }) async {
    final query = <String, String>{};
    if (category != null) query['category'] = category;
    if (featured == true) query['featured'] = 'true';
    if (offer == true) query['offer'] = 'true';
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (seller != null) query['seller'] = seller;
    if (userId != null) query['userId'] = userId;

    final res = await _getWithRetry(
      _uri('/products', query.isNotEmpty ? query : null),
    );
    if (res.statusCode != 200) throw Exception('Error fetching products');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Feed de productos rankeado por score (recencia + popularidad +
  /// afinidad por categoría del device/usuario), con diversidad por
  /// vendedor ya aplicada en el backend. A diferencia de [getProducts],
  /// que solo filtra, este es el orden "para ti" real.
  static Future<List<Product>> getFeed({
    required String deviceId,
    String? userId,
    int limit = 200,
  }) async {
    final query = <String, String>{'device_id': deviceId, 'limit': '$limit'};
    if (userId != null) query['user_id'] = userId;

    final res = await _getWithRetry(_uri('/feed', query));
    if (res.statusCode != 200) throw Exception('Error fetching feed');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final List<dynamic> data = body['products'] as List<dynamic>;
    return data
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Product> getProduct(String id, {String? userId}) async {
    final query = userId != null ? {'userId': userId} : null;
    final res = await _getWithRetry(_uri('/products/$id', query));
    if (res.statusCode != 200) throw Exception('Product not found');
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// El mismo endpoint que [getProduct], pero conservando los carruseles que
  /// vienen en la respuesta (relacionados y otros del vendedor). Lo usa la
  /// pantalla de detalle; el resto de la app, que solo quiere el producto,
  /// se queda con [getProduct] y los ignora.
  static Future<ProductDetail> getProductDetail(
    String id, {
    String? userId,
  }) async {
    final query = userId != null ? {'userId': userId} : null;
    final res = await _getWithRetry(_uri('/products/$id', query));
    if (res.statusCode != 200) throw Exception('Product not found');
    return ProductDetail.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Registra una vista de detalle de producto. Conteo simple: el backend
  /// no incrementa si [userId] es el dueño de la publicación. Pensado para
  /// llamarse fire-and-forget (sin await bloqueante en la UI) desde la
  /// pantalla de detalle, una vez por apertura y ya filtrado por el
  /// cooldown del cliente ([ViewCooldown]).
  static Future<void> registerProductView(String id, {String? userId}) async {
    try {
      await _client.post(
        _uri('/products/$id/view'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({if (userId != null) 'userId': userId}),
      );
    } catch (_) {
      // Best-effort: si falla, simplemente no se contó esta vista.
    }
  }

  /// Crea una publicación "se busca". Requiere sesión: el autor sale del
  /// JWT (requireAuth en backend), no de un userId de body.
  static Future<WantedPost> createWantedPost({
    required String title,
    String? description,
    required String categoryId,
    required String type,
    double? priceMin,
    double? priceMax,
    double? locationLat,
    double? locationLng,
    List<String>? paymentMethods,
  }) async {
    final res = await _client.post(
      _uri('/wanted'),
      headers: _authHeaders,
      body: jsonEncode({
        'title': title,
        'description': description,
        'categoryId': categoryId,
        'type': type,
        if (priceMin != null) 'priceMin': priceMin,
        if (priceMax != null) 'priceMax': priceMax,
        if (locationLat != null && locationLng != null) ...{
          'locationLat': locationLat,
          'locationLng': locationLng,
        },
        if (paymentMethods != null) 'paymentMethods': paymentMethods,
      }),
    );
    if (res.statusCode != 201)
      throw Exception('${res.statusCode}: ${res.body}');
    return WantedPost.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<List<WantedPost>> getWantedPosts({
    String? category,
    String? status,
    String? type,
  }) async {
    final query = <String, String>{
      if (category != null) 'category': category,
      if (status != null) 'status': status,
      if (type != null) 'type': type,
    };
    final res = await _getWithRetry(
      _uri('/wanted', query.isNotEmpty ? query : null),
    );
    if (res.statusCode != 200) throw Exception('Error fetching wanted posts');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => WantedPost.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Edita una publicación "se busca" existente (solo el dueño). A diferencia
  /// de [createWantedPost], usa el JWT del usuario (requireAuth en backend)
  /// en vez de mandar el userId en el body, para que un no-dueño reciba un
  /// 403 real y no pueda spoofear la autoría.
  static Future<WantedPost> editWantedPost({
    required String id,
    required String title,
    String? description,
    required String categoryId,
    required String type,
    double? priceMin,
    double? priceMax,
    List<String>? paymentMethods,
  }) async {
    final res = await _client.put(
      _uri('/wanted/$id'),
      headers: _authHeaders,
      body: jsonEncode({
        'title': title,
        'description': description,
        'categoryId': categoryId,
        'type': type,
        if (priceMin != null) 'priceMin': priceMin,
        if (priceMax != null) 'priceMax': priceMax,
        'paymentMethods': paymentMethods ?? const [],
      }),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(
        body['error'] ??
            'errors.edit_listing_failed'.tr(
              namedArgs: {'code': '${res.statusCode}'},
            ),
      );
    }
    return WantedPost.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<WantedPost> getWantedPost(String id) async {
    final res = await _getWithRetry(_uri('/wanted/$id'));
    if (res.statusCode != 200) throw Exception('Wanted post not found');
    return WantedPost.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Análogo a [registerProductView] pero para publicaciones "se busca".
  static Future<void> registerWantedPostView(
    String id, {
    String? userId,
  }) async {
    try {
      await _client.post(
        _uri('/wanted/$id/view'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({if (userId != null) 'userId': userId}),
      );
    } catch (_) {
      // Best-effort: si falla, simplemente no se contó esta vista.
    }
  }

  static Future<WantedPost> resolveWantedPost(
    String id, {
    required String userId,
    String? resolvedWithUserId,
  }) async {
    final res = await _client.patch(
      _uri('/wanted/$id/resolve'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        if (resolvedWithUserId != null)
          'resolvedWithUserId': resolvedWithUserId,
      }),
    );
    if (res.statusCode != 200)
      throw Exception('${res.statusCode}: ${res.body}');
    return WantedPost.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<String> respondToWantedPost(
    String id, {
    required String userId,
  }) async {
    final res = await _client.post(
      _uri('/wanted/$id/respond'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId}),
    );
    if (res.statusCode != 200)
      throw Exception('${res.statusCode}: ${res.body}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['conversationId'] as String;
  }

  static Future<Map<String, dynamic>> getPriceHistory(String id) async {
    final res = await _getWithRetry(_uri('/products/$id/price-history'));
    if (res.statusCode != 200) throw Exception('Error fetching price history');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Product> createProduct({
    required String title,
    required String price,
    required String category,
    required String description,
    List<int> availableDays = const [],
    List<Map<String, dynamic>> extras = const [],
    List<String>? imagePaths,
    int? stockQuantity,
    bool stockResetDaily = false,
    int? stockInitial,
    double? locationLat,
    double? locationLng,
    List<String>? paymentMethods,
    Map<String, dynamic> atributos = const {},
  }) async {
    // Si hay imágenes, usar multipart
    if (imagePaths != null && imagePaths.isNotEmpty) {
      final request = http.MultipartRequest('POST', _uri('/products'));
      request.fields['title'] = title;
      request.fields['price'] = price;
      request.fields['category'] = category;
      request.fields['description'] = description;
      request.fields['extras'] = jsonEncode(extras);
      if (stockQuantity != null) {
        request.fields['stock_quantity'] = stockQuantity.toString();
      }
      request.fields['stock_reset_daily'] = stockResetDaily.toString();
      if (stockInitial != null) {
        request.fields['stock_initial'] = stockInitial.toString();
      }
      if (availableDays.isNotEmpty) {
        request.fields['availableDays'] = jsonEncode(availableDays);
      }
      if (locationLat != null && locationLng != null) {
        request.fields['locationLat'] = locationLat.toString();
        request.fields['locationLng'] = locationLng.toString();
      }
      if (paymentMethods != null) {
        request.fields['paymentMethods'] = jsonEncode(paymentMethods);
      }
      // Respuestas a las preguntas dinámicas de la categoría. Van
      // stringificadas porque multipart no transporta objetos; el backend
      // acepta ambas formas. Se omite el campo si no se respondió nada, para
      // no mandar un "{}" que no significa nada.
      if (atributos.isNotEmpty) {
        request.fields['atributos'] = jsonEncode(atributos);
      }
      // El seller se obtiene del JWT en el backend (requireAuth)
      if (_token == null) {
        throw Exception('errors.no_active_session'.tr());
      }
      request.headers['Authorization'] = 'Bearer $_token';

      for (final path in imagePaths) {
        final file = await http.MultipartFile.fromPath('images', path);
        request.files.add(file);
      }

      final streamed = await _client.send(request);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != 201) _throwProductAuthAwareError(res);
      return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }

    // Sin imágenes: JSON plano
    final body = <String, dynamic>{
      'title': title,
      'price': price,
      'category': category,
      'description': description,
      'extras': extras,
      if (stockQuantity != null) 'stock_quantity': stockQuantity,
      'stock_reset_daily': stockResetDaily,
      if (stockInitial != null) 'stock_initial': stockInitial,
      if (availableDays.isNotEmpty) 'availableDays': availableDays,
      if (locationLat != null && locationLng != null) ...{
        'locationLat': locationLat,
        'locationLng': locationLng,
      },
      if (paymentMethods != null) 'paymentMethods': paymentMethods,
      if (atributos.isNotEmpty) 'atributos': atributos,
    };
    final res = await _client.post(
      _uri('/products'),
      headers: _authHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) _throwProductAuthAwareError(res);
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Traduce un 401 de `/api/products` a un mensaje accionable. El backend
  /// distingue `error: 'SESSION_INVALIDATED'` (el JWT_SECRET con el que se
  /// firmó el token ya no es válido, p. ej. tras un restart que no cargó el
  /// .env correctamente) del resto de fallos de token: en ese caso no hay
  /// forma de recuperar la sesión, hay que volver a loguearse.
  static Never _throwProductAuthAwareError(http.Response res) {
    if (res.statusCode == 401) {
      Map<String, dynamic>? decoded;
      try {
        decoded = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      if (decoded?['error'] == 'SESSION_INVALIDATED') {
        throw Exception('errors.session_expired'.tr());
      }
    }
    throw Exception('${res.statusCode}: ${res.body}');
  }

  /// Edita los campos generales de un producto ya existente (solo el dueño):
  /// título, descripción, categoría, imágenes, extras y días disponibles.
  /// El precio NO se edita aquí — usa [updateProduct] para eso, que tiene
  /// su propia lógica de historial/anti-fraude en el backend.
  ///
  /// [existingImageUrls] son las URLs (ya subidas antes) que se conservan;
  /// cualquier URL vieja que no esté en esta lista se borra del storage en
  /// el backend. [newImagePaths] son archivos locales nuevos a subir.
  static Future<Product> editProduct({
    required String productId,
    required String title,
    required String category,
    required String description,
    List<Map<String, dynamic>> extras = const [],
    List<int> availableDays = const [],
    List<String> existingImageUrls = const [],
    List<String>? newImagePaths,
    List<String>? paymentMethods,
    Map<String, dynamic> atributos = const {},
  }) async {
    if (_token == null) {
      throw Exception('errors.no_active_session'.tr());
    }

    final request = http.MultipartRequest('PUT', _uri('/products/$productId'));
    request.fields['title'] = title;
    request.fields['category'] = category;
    request.fields['description'] = description;
    request.fields['extras'] = jsonEncode(extras);
    request.fields['availableDays'] = jsonEncode(availableDays);
    request.fields['existingImages'] = jsonEncode(existingImageUrls);
    // Siempre se manda (aunque vacío): el backend interpreta [] como "sin
    // override, hereda del perfil" — un arreglo vacío es una respuesta
    // válida, no "no tocar este campo".
    request.fields['paymentMethods'] = jsonEncode(paymentMethods ?? const []);
    // Igual que paymentMethods: siempre se manda, aunque vaya vacío. El
    // backend reemplaza el objeto completo con lo que llegue, así que omitir
    // el campo significaría "no tocar" y sería imposible borrar una
    // respuesta que el vendedor acaba de quitar.
    request.fields['atributos'] = jsonEncode(atributos);
    request.headers['Authorization'] = 'Bearer $_token';

    for (final path in newImagePaths ?? const <String>[]) {
      request.files.add(await http.MultipartFile.fromPath('images', path));
    }

    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(
        body['error'] ?? 'Error al editar producto (${res.statusCode})',
      );
    }
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<Product> toggleFavorite(String productId) async {
    final res = await _client.patch(
      _uri('/products/$productId/favorite'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('Error toggling favorite');
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Actualiza el precio de un producto (solo el dueño).
  /// Envía PATCH /api/products/:id con el nuevo precio numérico.
  /// El backend calcula ofertas automáticas, historial, etc.
  static Future<Product> updateProduct(String productId, num newPrice) async {
    final res = await _client.patch(
      _uri('/products/$productId'),
      headers: _authHeaders,
      body: jsonEncode({'price': newPrice}),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Error al actualizar precio');
    }
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Elimina un producto (solo el dueño puede hacerlo).
  static Future<void> deleteProduct(String productId) async {
    final res = await _client.delete(
      _uri('/products/$productId'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Error al eliminar producto');
    }
  }

  /// Califica un producto con 1-5 estrellas (requiere userId, anónimo o real).
  static Future<Product> rateProduct(
    String productId,
    int stars, {
    required String userId,
  }) async {
    final res = await _client.post(
      _uri('/products/$productId/rate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'stars': stars, 'userId': userId}),
    );
    if (res.statusCode == 403) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(
        body['error'] ?? 'No puedes calificar tu propio producto',
      );
    }
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Error al calificar producto');
    }
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Activa (o quita, si [status] es `null`) un estado manual pegajoso del
  /// producto — vendido/apartado/en negociación/pausado. `null` "reactiva"
  /// el producto y lo vuelve al cálculo automático del badge.
  static Future<Product> updateProductStatus(
    String productId,
    String? status,
  ) async {
    final res = await _client.patch(
      _uri('/products/$productId/status'),
      headers: _authHeaders,
      body: jsonEncode({'status': status}),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Error al cambiar estado');
    }
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ─── Privacidad ──────────────────────────────────────────────

  /// ¿Está compartiendo el usuario su estado en línea?
  static Future<bool> getShowOnlineStatus() async {
    final res = await _client.get(_uri('/me/privacy'), headers: _authHeaders);
    if (res.statusCode != 200) {
      throw Exception('errors.privacy_read_failed'.tr());
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['showOnlineStatus']
        as bool;
  }

  /// Enciende o apaga "mostrar mi estado en línea".
  ///
  /// Apagarlo es recíproco por diseño del backend: quien lo apaga tampoco ve
  /// el estado de los demás.
  static Future<bool> setShowOnlineStatus(bool mostrar) async {
    final res = await _client.patch(
      _uri('/me/privacy'),
      headers: _authHeaders,
      body: jsonEncode({'showOnlineStatus': mostrar}),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Error al guardar la privacidad');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['showOnlineStatus']
        as bool;
  }

  /// Fija el stock de un producto a una cantidad exacta (solo el dueño).
  /// Usa `set` en vez de `decrement`, útil para la pantalla de edición.
  static Future<Product> setProductStock(
    String productId, {
    required int quantity,
    required bool resetDaily,
  }) async {
    final res = await _client.patch(
      _uri('/products/$productId/stock'),
      headers: _authHeaders,
      body: jsonEncode({'set': quantity, 'stock_reset_daily': resetDaily}),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Error al actualizar el stock');
    }
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Actualiza los días disponibles de un producto (solo el dueño).
  static Future<Product> updateProductDays(
    String productId,
    List<int> availableDays,
  ) async {
    final res = await _client.patch(
      _uri('/products/$productId/days'),
      headers: _authHeaders,
      body: jsonEncode({'availableDays': availableDays}),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'errors.update_days_failed'.tr());
    }
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ─── Sellers ────────────────────────────────────────────
  static Future<List<Seller>> getSellers() async {
    final res = await _getWithRetry(_uri('/sellers'));
    if (res.statusCode != 200) throw Exception('Error fetching sellers');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => Seller.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Seller> getSeller(String id) async {
    final res = await _getWithRetry(_uri('/sellers/$id'));
    if (res.statusCode != 200) throw Exception('Seller not found');
    return Seller.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Centinela para distinguir "no toques este campo" de "ponlo en null".
  /// El resto de campos del PATCH usan `!= null` para decidir si viajan, pero
  /// para el color de acento y el producto fijado null es un valor con
  /// significado propio ("vuelve al color de marca", "desfija"), así que ahí
  /// hace falta poder mandarlo explícitamente.
  static const _sinCambio = Object();

  static Future<Seller> updateSellerProfile({
    required String sellerId,
    String? name,
    String? phone,
    String? businessDescription,
    String? businessCategory,
    Map<int, BusinessHoursRange>? businessHours,
    double? locationLat,
    double? locationLng,
    List<String>? paymentMethods,
    Object? colorAcento = _sinCambio,
    Object? productoFijadoId = _sinCambio,
    String? facebookUrl,
    String? instagramUrl,
    String? whatsappNumber,
    String? tiktokUrl,
    String? twitterUrl,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (phone != null) body['phone'] = phone;
    if (businessDescription != null)
      body['businessDescription'] = businessDescription;
    if (businessCategory != null) body['businessCategory'] = businessCategory;
    if (businessHours != null) {
      body['businessHours'] = businessHoursToJson(businessHours);
    }
    if (locationLat != null && locationLng != null) {
      body['locationLat'] = locationLat;
      body['locationLng'] = locationLng;
    }
    if (paymentMethods != null) body['paymentMethods'] = paymentMethods;
    if (!identical(colorAcento, _sinCambio)) {
      body['colorAcento'] = colorAcento;
    }
    if (!identical(productoFijadoId, _sinCambio)) {
      body['productoFijadoId'] = productoFijadoId;
    }
    if (facebookUrl != null) body['facebookUrl'] = facebookUrl;
    if (instagramUrl != null) body['instagramUrl'] = instagramUrl;
    if (whatsappNumber != null) body['whatsappNumber'] = whatsappNumber;
    if (tiktokUrl != null) body['tiktokUrl'] = tiktokUrl;
    if (twitterUrl != null) body['twitterUrl'] = twitterUrl;
    final res = await _client.patch(
      _uri('/sellers/$sellerId'),
      headers: _authHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(decoded['error'] ?? 'Error al actualizar perfil');
    }
    return Seller.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Sube el logo de un negocio al servidor.
  /// [sellerId] es el ID del vendedor en el backend.
  /// [imagePath] es la ruta local del archivo.
  /// Devuelve el Seller actualizado.
  static Future<Seller> uploadBusinessLogo({
    required String sellerId,
    required String imagePath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/sellers/$sellerId/logo'),
    );
    request.files.add(await http.MultipartFile.fromPath('logo', imagePath));
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200)
      throw Exception('Error al subir logo: ${res.statusCode}');
    return Seller.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ─── Cart ───────────────────────────────────────────────
  static Future<List<CartItem>> getCart() async {
    final res = await _getWithRetry(_uri('/cart'));
    if (res.statusCode != 200) throw Exception('Error fetching cart');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> addToCart(
    String productId, {
    int quantity = 1,
    String meetingPoint = 'Por definir',
  }) async {
    final res = await _client.post(
      _uri('/cart'),
      headers: _authHeaders,
      body: jsonEncode({
        'productId': productId,
        'quantity': quantity,
        'meetingPoint': meetingPoint,
      }),
    );
    if (res.statusCode != 201) throw Exception('Error adding to cart');
  }

  static Future<void> updateCartQuantity(
    String cartItemId,
    int quantity,
  ) async {
    final res = await _client.put(
      _uri('/cart/$cartItemId'),
      headers: _authHeaders,
      body: jsonEncode({'quantity': quantity}),
    );
    if (res.statusCode != 200) throw Exception('Error updating cart');
  }

  static Future<void> removeFromCart(String cartItemId) async {
    final res = await _client.delete(
      _uri('/cart/$cartItemId'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('Error removing from cart');
  }

  // ─── Listings ───────────────────────────────────────────
  static Future<List<Product>> getListings() async {
    final res = await _getWithRetry(_uri('/listings'));
    if (res.statusCode != 200) throw Exception('Error fetching listings');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Highlight Plans ────────────────────────────────────
  //
  // TODO: Destacar publicaciones pendiente para próxima actualización - no
  // eliminar. Con kDestacarHabilitado en false nadie llama a este endpoint:
  // el home y el formulario de publicar dejaron de pedirlo y la pantalla de
  // planes (único consumidor que queda) es inaccesible desde la UI. El
  // backend sigue sirviendo /api/highlight-plans para clientes viejos.
  // Ver features/highlight/destacar_flag.dart.
  static Future<List<HighlightPlan>> getHighlightPlans() async {
    final res = await _getWithRetry(_uri('/highlight-plans'));
    if (res.statusCode != 200) throw Exception('Error fetching plans');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => HighlightPlan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Notifications ──────────────────────────────────────

  static Future<Map<String, dynamic>> getNotifications() async {
    final res = await _getWithRetry(
      _uri('/notifications'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('Error fetching notifications');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> markNotificationRead(String id) async {
    await _client.patch(_uri('/notifications/$id/read'), headers: _authHeaders);
  }

  static Future<void> markAllNotificationsRead() async {
    await _client.patch(_uri('/notifications/read-all'), headers: _authHeaders);
  }

  /// Marca como leídas las notificaciones in-app de una conversación.
  ///
  /// Se llama al abrir el chat. Los usuarios anónimos no tienen bandeja de
  /// notificaciones (el endpoint pide sesión), así que un 401 aquí es un caso
  /// normal y no un error: por eso no se lanza nada.
  static Future<void> markNotificationsReadForConversation(
    String conversationId,
  ) async {
    try {
      await _client.patch(
        _uri('/notifications/read-by-conversation'),
        headers: _authHeaders,
        body: jsonEncode({'conversationId': conversationId}),
      );
    } catch (_) {
      // Limpiar el badge es mejor-esfuerzo: no debe romper la apertura del chat.
    }
  }

  // ─── Push Tokens (FCM) ─────────────────────────────────────────

  static Future<void> registerPushToken(String fcmToken) async {
    final res = await _client.post(
      _uri('/notifications/register-push'),
      headers: _authHeaders,
      body: jsonEncode({'playerId': fcmToken}),
    );
    if (res.statusCode != 200) throw Exception('Error registering push token');
  }

  static Future<void> registerPushTokenAnonymous(
    String fcmToken,
    String anonymousId, {
    String platform = 'android',
  }) async {
    final res = await _client.post(
      _uri('/notifications/register-push-anon'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'playerId': fcmToken,
        'userId': anonymousId,
        'platform': platform,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Error registering anonymous push token');
    }
  }

  static Future<void> unregisterPushToken(String playerId) async {
    final res = await _client.delete(
      _uri('/notifications/register-push'),
      headers: _authHeaders,
      body: jsonEncode({'playerId': playerId}),
    );
    if (res.statusCode != 200)
      throw Exception('Error unregistering push token');
  }

  static Future<void> unregisterAllPushTokens() async {
    final res = await _client.delete(
      _uri('/notifications/register-push/all'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200)
      throw Exception('Error unregistering all push tokens');
  }

  static Future<int> getUnreadNotificationCount() async {
    final res = await _getWithRetry(
      _uri('/notifications/unread-count'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) return 0;
    return (jsonDecode(res.body) as Map<String, dynamic>)['count'] as int? ?? 0;
  }

  // ─── Category Interests ──────────────────────────────────

  static Future<List<String>> getCategoryInterests() async {
    final res = await _getWithRetry(
      _uri('/notifications/interests'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['interests'] as List<dynamic>?)?.cast<String>() ?? [];
  }

  static Future<List<String>> addCategoryInterest(String categoryId) async {
    final res = await _client.post(
      _uri('/notifications/interests'),
      headers: _authHeaders,
      body: jsonEncode({'categoryId': categoryId}),
    );
    if (res.statusCode != 200) throw Exception('Error adding interest');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['interests'] as List<dynamic>?)?.cast<String>() ?? [];
  }

  static Future<List<String>> removeCategoryInterest(String categoryId) async {
    final res = await _client.delete(
      _uri('/notifications/interests/$categoryId'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('Error removing interest');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['interests'] as List<dynamic>?)?.cast<String>() ?? [];
  }

  /// Pide una sesión de invitado al backend. Ver [AnonSession], que es quien
  /// la persiste y decide cuándo hace falta.
  static Future<Map<String, dynamic>> crearSesionInvitado() async {
    final res = await _client.post(
      _uri('/auth/anon'),
      headers: {'Content-Type': 'application/json'},
    );
    if (res.statusCode != 201) {
      throw Exception('No se pudo iniciar la sesión de invitado');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ─── Chat ────────────────────────────────────────────────
  //
  // Ninguna de estas llamadas manda ya `senderId`/`userId`: la identidad va
  // en el Bearer y la resuelve el servidor. Mandarla en el cuerpo era lo que
  // permitía leer la bandeja de cualquiera y escribir en su nombre.

  /// Obtiene las conversaciones del usuario del token (cuenta o invitado).
  static Future<Map<String, dynamic>> getConversations() async {
    final res = await _getWithRetry(_uri('/chat/conversations'), headers: _authHeaders);
    if (res.statusCode != 200) throw Exception('Error fetching conversations');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<ChatMessage>> getMessages(String conversationId) async {
    final res = await _getWithRetry(
      _uri('/chat/conversations/$conversationId/messages'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('Error fetching messages');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['messages'] as List<dynamic>)
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Envía un mensaje. Si no existe conversación, la crea.
  /// Si se provee [conversationId], lo envía a la conversación existente.
  /// El autor lo determina el token. Devuelve { messages, conversationId }.
  static Future<Map<String, dynamic>> sendMessage({
    required String productId,
    required String sellerId,
    required String text,
    String? conversationId,
    String? replyToMessageId,
  }) async {
    final body = <String, dynamic>{
      'productId': productId,
      'sellerId': sellerId,
      'text': text,
    };
    if (conversationId != null && conversationId.isNotEmpty) {
      body['conversationId'] = conversationId;
    }
    if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
      body['replyToMessageId'] = replyToMessageId;
    }
    final res = await _client.post(
      _uri('/chat/send'),
      headers: _authHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) throw Exception('Error sending message');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Elimina un mensaje propio (soft-delete: reemplaza el texto).
  /// El servidor solo lo permite si el autor es el dueño del token.
  static Future<void> deleteMessage(String messageId) async {
    final res = await _client.delete(
      _uri('/chat/messages/$messageId'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('Error deleting message');
  }

  /// Envía un mensaje con una imagen. El backend la convierte a WebP antes
  /// de guardarla. Igual que [sendMessage]: si no existe conversación, la
  /// crea (requiere productId/sellerId); si se provee [conversationId], la
  /// usa. Devuelve { messages, conversationId }.
  static Future<Map<String, dynamic>> sendChatImage({
    required String imagePath,
    String? productId,
    String? sellerId,
    String? conversationId,
    String? replyToMessageId,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/chat/send-image'));
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    if (productId != null) request.fields['productId'] = productId;
    if (sellerId != null) request.fields['sellerId'] = sellerId;
    if (conversationId != null && conversationId.isNotEmpty) {
      request.fields['conversationId'] = conversationId;
    }
    if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
      request.fields['replyToMessageId'] = replyToMessageId;
    }
    request.files.add(await http.MultipartFile.fromPath('image', imagePath));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 201) {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(decoded['error'] ?? 'Error al enviar la imagen');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ─── Comentarios ──────────────────────────────────────────

  /// Hilo de comentarios de una publicación. Lectura abierta: no manda token
  /// y funciona igual sin sesión, que es justo el punto — los comentarios
  /// son el respaldo social del vendedor ante quien todavía no se registra.
  ///
  /// [cursor] viene del `nextCursor` de la página anterior; null pide la
  /// primera.
  static Future<ProductCommentPage> getProductComments(
    String productId, {
    String? cursor,
    int? limit,
  }) async {
    final res = await _getWithRetry(
      _uri('/products/$productId/comments', {
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': '$limit',
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('No se pudieron cargar los comentarios');
    }
    return ProductCommentPage.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  /// Publica un comentario. Requiere sesión CON verificación institucional.
  ///
  /// El 403 se traduce a [ComentarioNoVerificadoException] en vez de a un
  /// `Exception` genérico porque la UI reacciona distinto: no es un error
  /// que mostrar en un snackbar, es la señal de cambiar el input por la
  /// tarjeta que lleva a verificarse.
  static Future<ProductComment> postProductComment(
    String productId,
    String texto,
  ) async {
    final res = await _client.post(
      _uri('/products/$productId/comments'),
      headers: _authHeaders,
      body: jsonEncode({'texto': texto}),
    );

    if (res.statusCode == 403) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ComentarioNoVerificadoException(
        body['error'] as String? ?? 'Verifica tu cuenta para comentar',
      );
    }
    if (res.statusCode != 201) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'No se pudo publicar el comentario');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return ProductComment.fromJson(body['comment'] as Map<String, dynamic>);
  }

  /// Borra un comentario. El backend solo lo permite al autor o al dueño de
  /// la publicación, y el borrado es lógico (la fila se marca, no se va).
  static Future<void> deleteProductComment(
    String productId,
    String commentId,
  ) async {
    final res = await _client.delete(
      _uri('/products/$productId/comments/$commentId'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'No se pudo eliminar el comentario');
    }
  }

  // ─── Preguntas y respuestas ───────────────────────────────────

  /// Las 2-3 preguntas que se asoman en el detalle del producto. Público:
  /// no manda sesión y el backend no la pide.
  static Future<ProductQuestionPage> getProductQuestionsPreview(
    String productId, {
    int limit = 3,
  }) async {
    final res = await _getWithRetry(
      _uri('/products/$productId/questions', {
        'preview': 'true',
        'limit': '$limit',
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('No se pudieron cargar las preguntas');
    }
    return ProductQuestionPage.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  /// Página del listado completo. [soloPendientes] es el chip que usa el
  /// dueño para ir directo a lo que le falta por responder.
  static Future<ProductQuestionPage> getProductQuestions(
    String productId, {
    String? cursor,
    int? limit,
    bool soloPendientes = false,
  }) async {
    final res = await _getWithRetry(
      _uri('/products/$productId/questions', {
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': '$limit',
        if (soloPendientes) 'filter': 'pending',
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('No se pudieron cargar las preguntas');
    }
    return ProductQuestionPage.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  /// Publica una pregunta. Requiere sesión, pero NO verificación: preguntar
  /// es pedir un dato, no opinar sobre alguien.
  ///
  /// El 403 llega cuando el backend detecta que quien pregunta es el dueño
  /// de la publicación — caso que la UI ya evita, y que se traduce igual
  /// por si el estado del cliente estuviera desfasado.
  static Future<ProductQuestion> askProductQuestion(
    String productId,
    String texto,
  ) async {
    final res = await _client.post(
      _uri('/products/$productId/questions'),
      headers: _authHeaders,
      body: jsonEncode({'texto': texto}),
    );

    if (res.statusCode != 201) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'No se pudo publicar la pregunta');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return ProductQuestion.fromJson(body['question'] as Map<String, dynamic>);
  }

  /// Responde (o corrige la respuesta de) una pregunta. El backend solo lo
  /// permite al dueño de la publicación: el cliente esconde el input, esto
  /// es lo que lo hace cumplir.
  static Future<ProductQuestion> answerProductQuestion(
    String questionId,
    String texto,
  ) async {
    final res = await _client.post(
      _uri('/questions/$questionId/answer'),
      headers: _authHeaders,
      body: jsonEncode({'texto': texto}),
    );

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'No se pudo guardar la respuesta');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return ProductQuestion.fromJson(body['question'] as Map<String, dynamic>);
  }

  /// Comentarios que OTROS dejaron en las publicaciones de [userId] — la
  /// pestaña "Comentarios" del perfil. Ojo: recibidos, no escritos; es
  /// prueba social del vendedor, no su historial de actividad.
  static Future<ProductCommentPage> getCommentsForUser(
    String userId, {
    String? cursor,
    int? limit,
  }) async {
    final res = await _getWithRetry(
      _uri('/users/$userId/comments', {
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': '$limit',
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('No se pudieron cargar los comentarios');
    }
    return ProductCommentPage.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }
}

/// El backend rechazó el comentario porque la cuenta no está verificada.
/// Tipo propio para que la UI la distinga de un fallo cualquiera de red.
class ComentarioNoVerificadoException implements Exception {
  const ComentarioNoVerificadoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// El backend rechazó el inicio de sesión con Google.
///
/// [codigo] es el valor de `error` que manda el servidor
/// (GOOGLE_NO_CONFIGURADO, GOOGLE_TOKEN_INVALIDO, GOOGLE_EMAIL_NO_VERIFICADO,
/// GOOGLE_DOMINIO_NO_PERMITIDO…), para que la UI pueda distinguir casos sin
/// leer el texto.
class GoogleAuthException implements Exception {
  GoogleAuthException(this.codigo, this.mensaje);

  final String codigo;
  final String mensaje;

  /// El servidor todavía no tiene pegados los Client ID de Google.
  bool get faltaConfigurar => codigo == 'GOOGLE_NO_CONFIGURADO';

  /// El idToken caducó o no era válido: hay que repetir el flujo de Google.
  bool get tokenInvalido => codigo == 'GOOGLE_TOKEN_INVALIDO';

  @override
  String toString() => mensaje;
}

/// La cuenta de Google es válida pero todavía no existe en el marketplace.
///
/// No es un fallo: es el camino normal de "registrarse con Google". Trae lo
/// que Google sí sabe del usuario para prellenar el formulario; el resto
/// (tipo de cuenta, teléfono, métodos de pago) lo tiene que capturar él.
class GoogleRegistroRequeridoException implements Exception {
  GoogleRegistroRequeridoException({
    required this.email,
    required this.nombre,
    this.foto,
  });

  final String email;
  final String nombre;
  final String? foto;

  @override
  String toString() => 'GoogleRegistroRequerido($email)';
}
