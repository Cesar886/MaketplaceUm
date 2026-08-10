import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import '../config/app_config.dart';
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
    if (utf8.decode(bytes, allowMalformed: true).contains('SESSION_INVALIDATED')) {
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

/// Servicio centralizado para consumir la API REST de Mercadito UM.
///
/// Auto-detecta la URL base según plataforma / entorno.
/// Si falla, usa [customBaseUrl] para override manual.
class ApiService {
  ApiService._();

  static final _client = _SessionAwareClient(http.Client());

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
      throw Exception('Error al iniciar sesión. Intenta de nuevo.');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
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
            'No pudimos completar la verificación.',
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
      throw const VerificacionException(
        'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
      );
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
    return _postVerificacion('/estudiante/confirmar', {'codigo_otp': codigoOtp});
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
      throw const VerificacionException(
        'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
      );
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

  // ─── Products ───────────────────────────────────────────
  static Future<List<Product>> getProducts({
    String? category,
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
        body['error'] ?? 'Error al editar la publicación (${res.statusCode})',
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
  static Future<void> registerWantedPostView(String id, {String? userId}) async {
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
      // El seller se obtiene del JWT en el backend (requireAuth)
      if (_token == null) {
        throw Exception(
          'No hay sesión activa en el backend. Vuelve a iniciar sesión.',
        );
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
        throw Exception('Tu sesión expiró, inicia sesión de nuevo.');
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
  }) async {
    if (_token == null) {
      throw Exception(
        'No hay sesión activa en el backend. Vuelve a iniciar sesión.',
      );
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
      throw Exception(body['error'] ?? 'Error al actualizar días disponibles');
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

  // ─── Chat ────────────────────────────────────────────────

  /// Obtiene conversaciones — no requiere auth, usa [userId] (anónimo o real).
  static Future<Map<String, dynamic>> getConversations({String? userId}) async {
    final query = <String, String>{};
    if (userId != null) query['userId'] = userId;
    final res = await _getWithRetry(_uri('/chat/conversations', query));
    if (res.statusCode != 200) throw Exception('Error fetching conversations');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<ChatMessage>> getMessages(
    String conversationId, {
    String? userId,
  }) async {
    final query = <String, String>{};
    if (userId != null) query['userId'] = userId;
    final res = await _getWithRetry(
      _uri('/chat/conversations/$conversationId/messages', query),
    );
    if (res.statusCode != 200) throw Exception('Error fetching messages');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['messages'] as List<dynamic>)
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Envía un mensaje. Si no existe conversación, la crea.
  /// Si se provee [conversationId], lo envía a la conversación existente.
  /// [senderId] es requerido (puede ser anónimo o el backendSellerId).
  /// Devuelve { messages, conversationId }
  static Future<Map<String, dynamic>> sendMessage({
    required String productId,
    required String sellerId,
    required String text,
    required String senderId,
    String? conversationId,
  }) async {
    final body = <String, dynamic>{
      'productId': productId,
      'sellerId': sellerId,
      'text': text,
      'senderId': senderId,
    };
    if (conversationId != null && conversationId.isNotEmpty) {
      body['conversationId'] = conversationId;
    }
    final res = await _client.post(
      _uri('/chat/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) throw Exception('Error sending message');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Elimina un mensaje propio (soft-delete: reemplaza el texto).
  /// [senderId] debe coincidir con el dueño del mensaje.
  static Future<void> deleteMessage(
    String messageId, {
    required String senderId,
  }) async {
    final res = await _client.delete(
      _uri('/chat/messages/$messageId', {'senderId': senderId}),
    );
    if (res.statusCode != 200) throw Exception('Error deleting message');
  }

  /// Envía un mensaje con una imagen. El backend la convierte a WebP antes
  /// de guardarla. Igual que [sendMessage]: si no existe conversación, la
  /// crea (requiere productId/sellerId); si se provee [conversationId], la
  /// usa. Devuelve { messages, conversationId }.
  static Future<Map<String, dynamic>> sendChatImage({
    required String imagePath,
    required String senderId,
    String? productId,
    String? sellerId,
    String? conversationId,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/chat/send-image'));
    request.fields['senderId'] = senderId;
    if (productId != null) request.fields['productId'] = productId;
    if (sellerId != null) request.fields['sellerId'] = sellerId;
    if (conversationId != null && conversationId.isNotEmpty) {
      request.fields['conversationId'] = conversationId;
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
