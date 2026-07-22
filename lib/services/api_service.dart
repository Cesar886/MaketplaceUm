import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Servicio centralizado para consumir la API REST de Mercadito UM.
///
/// Configura automáticamente la URL base según la plataforma:
/// - Android emulator → `http://10.0.2.2:3000`
/// - Otros            → `http://localhost:3000`
class ApiService {
  ApiService._();

  static final _client = http.Client();

  static String get baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  static Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl/api$path').replace(queryParameters: query);
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
    String? seller,
    List<String>? imagePaths, // rutas de archivos locales
  }) async {
    // Si hay imágenes, usar multipart
    if (imagePaths != null && imagePaths.isNotEmpty) {
      final request = http.MultipartRequest('POST', _uri('/products'));
      request.fields['title'] = title;
      request.fields['price'] = price;
      request.fields['category'] = category;
      request.fields['description'] = description;
      if (seller != null) request.fields['seller'] = seller;

      for (final path in imagePaths) {
        final file = await http.MultipartFile.fromPath('images', path);
        request.files.add(file);
      }

      final streamed = await _client.send(request);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != 201) throw Exception('Error creating product');
      return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }

    // Sin imágenes: JSON plano
    final body = <String, dynamic>{
      'title': title,
      'price': price,
      'category': category,
      'description': description,
    };
    if (seller != null) body['seller'] = seller;
    final res = await _client.post(
      _uri('/products'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) throw Exception('Error creating product');
    return Product.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<Product> toggleFavorite(String productId) async {
    final res = await _client.patch(_uri('/products/$productId/favorite'));
    if (res.statusCode != 200) throw Exception('Error toggling favorite');
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
      headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'quantity': quantity}),
    );
    if (res.statusCode != 200) throw Exception('Error updating cart');
  }

  static Future<void> removeFromCart(String cartItemId) async {
    final res = await _client.delete(_uri('/cart/$cartItemId'));
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
}
