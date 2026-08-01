import 'package:shared_preferences/shared_preferences.dart';

/// Genera y persiste un ID único anónimo para el chat sin login.
///
/// Se guarda en SharedPreferences y se reutiliza entre sesiones.
/// Así el usuario conserva sus conversaciones aunque no tenga cuenta.
class AnonymousId {
  static const _key = 'anonymous_chat_id';
  static String? _cached;

  /// Retorna el ID anónimo actual, generándolo si no existe.
  static Future<String> get() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_key);

    if (id == null || id.isEmpty) {
      // Generar UUID v4 simple sin dependencias externas
      id = _generateUuid();
      await prefs.setString(_key, id);
    }

    _cached = id;
    return id;
  }

  /// Resuelve el ID a usar para identificar al usuario actual ante el backend:
  /// su ID de vendedor si tiene sesión, o su ID anónimo persistido si no.
  static Future<String> resolve({required bool isLoggedIn, String? backendSellerId}) async {
    if (isLoggedIn && backendSellerId != null) return backendSellerId;
    return get();
  }

  /// Limpia el ID anónimo (útil si el usuario se registra después).
  static Future<void> reset() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Genera un UUID v4 compatible con RFC 4122.
  static String _generateUuid() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = (now * 9301 + 49297) % 233280;
    final chars = '0123456789abcdef';
    final segments = [8, 4, 4, 4, 12];
    final buffer = StringBuffer();
    for (final len in segments) {
      if (buffer.isNotEmpty) buffer.write('-');
      for (var i = 0; i < len; i++) {
        final val = ((random * (i + 1) + now) % 16).toInt();
        buffer.write(chars[val]);
      }
    }
    return 'anon_${buffer.toString()}';
  }
}
