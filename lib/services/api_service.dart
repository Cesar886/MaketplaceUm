import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import '../config/app_config.dart';

/// Servicio centralizado para consumir la API REST de Mercadito UM.
///
/// Auto-detecta la URL base según plataforma / entorno.
/// Si falla, usa [customBaseUrl] para override manual.
class ApiService {
  ApiService._();

  static final _client = http.Client();

  /// Override programático (alternativa a la constante _backendHost).
  static String? _customBaseUrl;

  // ─── Token JWT para rutas protegidas ─────────────────────────
  // El token se asigna desde AuthProvider cuando el usuario inicia sesión.
  // Ya NO se hardcodea 's1' — cada usuario tiene su propio token.
  static String? _token;

  /// Asigna el token JWT del usuario autenticado para usarlo en requests.
  static void setToken(String token) {
    _token = token;
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

  // ─── Auth / Registro ──────────────────────────────────────

  /// Llama a POST /api/auth/register para sincronizar el usuario local
  /// con el backend. Crea un perfil de vendedor si no existe y devuelve
  /// un JWT para requests autenticados.
  static Future<Map<String, dynamic>> registerBackendUser({
    required String name,
    required String email,
    required String userType,
    String? phone,
  }) async {
    final res = await _client.post(
      _uri('/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'userType': userType,
        if (phone != null) 'phone': phone,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Error al sincronizar usuario con el backend');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ─── Health ─────────────────────────────────────────────
  static Future<bool> healthCheck() async {
    try {
      final res = await _client.get(_uri('/health'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─── Categories ─────────────────────────────────────────
  static Future<List<MarketplaceCategory>> getCategories() async {
    final res = await _client.get(_uri('/categories'));
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

    final res = await _client.get(_uri('/products', query.isNotEmpty ? query : null));
    if (res.statusCode != 200) throw Exception('Error fetching products');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Product> getProduct(String id, {String? userId}) async {
    final query = userId != null ? {'userId': userId} : null;
    final res = await _client.get(_uri('/products/$id', query));
    if (res.statusCode != 200) throw Exception('Product not found');
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<WantedPost> createWantedPost({
    required String userId,
    required String title,
    String? description,
    required String categoryId,
    required String type,
    double? priceMin,
    double? priceMax,
  }) async {
    final res = await _client.post(
      _uri('/wanted'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'title': title,
        'description': description,
        'categoryId': categoryId,
        'type': type,
        if (priceMin != null) 'priceMin': priceMin,
        if (priceMax != null) 'priceMax': priceMax,
      }),
    );
    if (res.statusCode != 201) throw Exception('${res.statusCode}: ${res.body}');
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
    final res = await _client.get(_uri('/wanted', query.isNotEmpty ? query : null));
    if (res.statusCode != 200) throw Exception('Error fetching wanted posts');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => WantedPost.fromJson(e as Map<String, dynamic>)).toList();
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
      }),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Error al editar la publicación (${res.statusCode})');
    }
    return WantedPost.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<WantedPost> getWantedPost(String id) async {
    final res = await _client.get(_uri('/wanted/$id'));
    if (res.statusCode != 200) throw Exception('Wanted post not found');
    return WantedPost.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
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
        if (resolvedWithUserId != null) 'resolvedWithUserId': resolvedWithUserId,
      }),
    );
    if (res.statusCode != 200) throw Exception('${res.statusCode}: ${res.body}');
    return WantedPost.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<String> respondToWantedPost(String id, {required String userId}) async {
    final res = await _client.post(
      _uri('/wanted/$id/respond'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId}),
    );
    if (res.statusCode != 200) throw Exception('${res.statusCode}: ${res.body}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['conversationId'] as String;
  }

  static Future<Map<String, dynamic>> getPriceHistory(String id) async {
    final res = await _client.get(_uri('/products/$id/price-history'));
    if (res.statusCode != 200) throw Exception('Error fetching price history');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Product> createProduct({
    required String title,
    required String price,
    required String category,
    required String description,
    String status = 'available',
    List<int> availableDays = const [],
    List<Map<String, dynamic>> extras = const [],
    List<String>? imagePaths,
    int? stockQuantity,
    bool stockResetDaily = false,
    int? stockInitial,
  }) async {
    // Si hay imágenes, usar multipart
    if (imagePaths != null && imagePaths.isNotEmpty) {
      final request = http.MultipartRequest('POST', _uri('/products'));
      request.fields['title'] = title;
      request.fields['price'] = price;
      request.fields['category'] = category;
      request.fields['description'] = description;
      request.fields['status'] = status;
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
      // El seller se obtiene del JWT en el backend (requireAuth)
      if (_token == null) {
        throw Exception('No hay sesión activa en el backend. Vuelve a iniciar sesión.');
      }
      request.headers['Authorization'] = 'Bearer $_token';

      for (final path in imagePaths) {
        final file = await http.MultipartFile.fromPath('images', path);
        request.files.add(file);
      }

      final streamed = await _client.send(request);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != 201) throw Exception('${res.statusCode}: ${res.body}');
      return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }

    // Sin imágenes: JSON plano
    final body = <String, dynamic>{
      'title': title,
      'price': price,
      'category': category,
      'description': description,
      'status': status,
      'extras': extras,
      if (stockQuantity != null) 'stock_quantity': stockQuantity,
      'stock_reset_daily': stockResetDaily,
      if (stockInitial != null) 'stock_initial': stockInitial,
      if (availableDays.isNotEmpty) 'availableDays': availableDays,
    };
    final res = await _client.post(
      _uri('/products'),
      headers: _authHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) throw Exception('${res.statusCode}: ${res.body}');
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
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
  }) async {
    if (_token == null) {
      throw Exception('No hay sesión activa en el backend. Vuelve a iniciar sesión.');
    }

    final request = http.MultipartRequest('PUT', _uri('/products/$productId'));
    request.fields['title'] = title;
    request.fields['category'] = category;
    request.fields['description'] = description;
    request.fields['extras'] = jsonEncode(extras);
    request.fields['availableDays'] = jsonEncode(availableDays);
    request.fields['existingImages'] = jsonEncode(existingImageUrls);
    request.headers['Authorization'] = 'Bearer $_token';

    for (final path in newImagePaths ?? const <String>[]) {
      request.files.add(await http.MultipartFile.fromPath('images', path));
    }

    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Error al editar producto (${res.statusCode})');
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
  static Future<Product> rateProduct(String productId, int stars, {required String userId}) async {
    final res = await _client.post(
      _uri('/products/$productId/rate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'stars': stars, 'userId': userId}),
    );
    if (res.statusCode == 403) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'No puedes calificar tu propio producto');
    }
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Error al calificar producto');
    }
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Cambia el estado de disponibilidad de un producto (solo el dueño).
  static Future<Product> updateProductStatus(
      String productId, String status) async {
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
      String productId, List<int> availableDays) async {
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
    final res = await _client.get(_uri('/sellers'));
    if (res.statusCode != 200) throw Exception('Error fetching sellers');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => Seller.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Seller> getSeller(String id) async {
    final res = await _client.get(_uri('/sellers/$id'));
    if (res.statusCode != 200) throw Exception('Seller not found');
    return Seller.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<Seller> updateSellerProfile({
    required String sellerId,
    String? name,
    String? phone,
    String? businessDescription,
    String? businessCategory,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (phone != null) body['phone'] = phone;
    if (businessDescription != null) body['businessDescription'] = businessDescription;
    if (businessCategory != null) body['businessCategory'] = businessCategory;
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
    if (res.statusCode != 200) throw Exception('Error al subir logo: ${res.statusCode}');
    return Seller.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ─── Cart ───────────────────────────────────────────────
  static Future<List<CartItem>> getCart() async {
    final res = await _client.get(_uri('/cart'));
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

  static Future<void> updateCartQuantity(String cartItemId, int quantity) async {
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
    final res = await _client.get(_uri('/listings'));
    if (res.statusCode != 200) throw Exception('Error fetching listings');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Highlight Plans ────────────────────────────────────
  static Future<List<HighlightPlan>> getHighlightPlans() async {
    final res = await _client.get(_uri('/highlight-plans'));
    if (res.statusCode != 200) throw Exception('Error fetching plans');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => HighlightPlan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Notifications ──────────────────────────────────────

  static Future<Map<String, dynamic>> getNotifications() async {
    final res = await _client.get(_uri('/notifications'), headers: _authHeaders);
    if (res.statusCode != 200) throw Exception('Error fetching notifications');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> markNotificationRead(String id) async {
    await _client.patch(
      _uri('/notifications/$id/read'),
      headers: _authHeaders,
    );
  }

  static Future<void> markAllNotificationsRead() async {
    await _client.patch(
      _uri('/notifications/read-all'),
      headers: _authHeaders,
    );
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
    if (res.statusCode != 200) throw Exception('Error unregistering push token');
  }

  static Future<void> unregisterAllPushTokens() async {
    final res = await _client.delete(
      _uri('/notifications/register-push/all'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('Error unregistering all push tokens');
  }

  static Future<int> getUnreadNotificationCount() async {
    final res = await _client.get(
      _uri('/notifications/unread-count'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) return 0;
    return (jsonDecode(res.body) as Map<String, dynamic>)['count'] as int? ?? 0;
  }

  // ─── Category Interests ──────────────────────────────────

  static Future<List<String>> getCategoryInterests() async {
    final res = await _client.get(
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
    final res = await _client.get(_uri('/chat/conversations', query));
    if (res.statusCode != 200) throw Exception('Error fetching conversations');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<ChatMessage>> getMessages(String conversationId, {String? userId}) async {
    final query = <String, String>{};
    if (userId != null) query['userId'] = userId;
    final res = await _client.get(_uri('/chat/conversations/$conversationId/messages', query));
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
  static Future<void> deleteMessage(String messageId, {required String senderId}) async {
    final res = await _client.delete(
      _uri('/chat/messages/$messageId', {'senderId': senderId}),
    );
    if (res.statusCode != 200) throw Exception('Error deleting message');
  }
}
