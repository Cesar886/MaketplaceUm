import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Almacena en SharedPreferences los IDs de productos vistos recientemente.
/// Máximo [maxItems] productos; los más recientes al inicio.
class RecentProductsService {
  RecentProductsService._();

  static const _key = 'recent_products';
  static const int maxItems = 20;

  /// Obtiene la lista de IDs de productos vistos, del más reciente al más viejo.
  static Future<List<String>> getRecentIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<String>();
  }

  /// Agrega (o mueve al inicio) un producto como visto.
  static Future<void> addRecent(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final list = <String>[];
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      list.addAll(decoded.cast<String>());
    }

    // Quitar duplicado si existe
    list.remove(productId);

    // Insertar al inicio
    list.insert(0, productId);

    // Limitar tamaño
    if (list.length > maxItems) {
      list.removeRange(maxItems, list.length);
    }

    await prefs.setString(_key, jsonEncode(list));
  }

  /// Limpia todo el historial de recientes.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
