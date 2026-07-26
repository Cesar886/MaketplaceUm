import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Almacena en SharedPreferences los IDs de productos favoritos del usuario.
/// Es exclusivo por usuario — cada quien tiene su propia lista privada.
class FavoriteProductsService {
  FavoriteProductsService._();

  static const _key = 'favorite_products';

  /// Obtiene la lista de IDs de productos favoritos.
  static Future<List<String>> getFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<String>();
  }

  /// Verifica si un producto está en favoritos.
  static Future<bool> isFavorite(String productId) async {
    final ids = await getFavoriteIds();
    return ids.contains(productId);
  }

  /// Agrega un producto a favoritos (no duplica).
  static Future<void> addFavorite(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final list = <String>[];
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      list.addAll(decoded.cast<String>());
    }
    if (!list.contains(productId)) {
      list.add(productId);
    }
    await prefs.setString(_key, jsonEncode(list));
  }

  /// Elimina un producto de favoritos.
  static Future<void> removeFavorite(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    final list = decoded.cast<String>();
    list.remove(productId);
    await prefs.setString(_key, jsonEncode(list));
  }

  /// Alterna el estado de favorito de un producto.
  /// Devuelve `true` si ahora es favorito, `false` si ya no.
  static Future<bool> toggleFavorite(String productId) async {
    final isFav = await isFavorite(productId);
    if (isFav) {
      await removeFavorite(productId);
      return false;
    } else {
      await addFavorite(productId);
      return true;
    }
  }

  /// Limpia todos los favoritos.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
