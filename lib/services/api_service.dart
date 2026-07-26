import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

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
  ///
  /// En EMULADOR Android: 10.0.2.2:3000  (default automático)
  /// En DISPOSITIVO FÍSICO: pon la IP de tu compu aquí 👇
  ///
  /// Para saber tu IP, corre en la terminal:
  ///   hostname -I | awk '{print $1}'
  ///
  ///                  👇 CÁMBIAME si usas dispositivo físico
  // static const String _backendHost = '192.168.27.77';
  // static const int _backendPort = 3000;

      static const String _backendHost = 'localhost';
      static const int _backendPort = 3000;


  /// URL base del backend. Usa [_backendHost] siempre.
  static String get baseUrl {
    if (_customBaseUrl != null) return _customBaseUrl!;
    return 'http://$_backendHost:$_backendPort';
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
  }) async {
    final query = <String, String>{};
    if (category != null) query['category'] = category;
    if (featured == true) query['featured'] = 'true';
    if (offer == true) query['offer'] = 'true';
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (seller != null) query['seller'] = seller;

    final res = await _client.get(_uri('/products', query.isNotEmpty ? query : null));
    if (res.statusCode != 200) throw Exception('Error fetching products');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Product> getProduct(String id) async {
    final res = await _client.get(_uri('/products/$id'));
    if (res.statusCode != 200) throw Exception('Product not found');
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
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

  /// Califica un producto con 1-5 estrellas (requiere auth).
  /// Crea o actualiza la calificación del usuario actual.
  static Future<Product> rateProduct(String productId, int stars) async {
    final res = await _client.post(
      _uri('/products/$productId/rate'),
      headers: _authHeaders,
      body: jsonEncode({'stars': stars}),
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

  static Future<Map<String, dynamic>> getConversations() async {
    final res = await _client.get(
      _uri('/chat/conversations'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('Error fetching conversations');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<ChatMessage>> getMessages(String conversationId) async {
    final res = await _client.get(
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
  /// Devuelve { messages, conversationId }
  static Future<Map<String, dynamic>> sendMessage({
    required String productId,
    required String sellerId,
    required String text,
  }) async {
    final res = await _client.post(
      _uri('/chat/send'),
      headers: _authHeaders,
      body: jsonEncode({
        'productId': productId,
        'sellerId': sellerId,
        'text': text,
      }),
    );
    if (res.statusCode != 201) throw Exception('Error sending message');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
