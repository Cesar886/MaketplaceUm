import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Mitigación ligera contra inflar el contador de vistas: si ya se registró
/// una vista para un id en los últimos [cooldown] minutos, no se vuelve a
/// mandar. No es a prueba de balas (el cliente se puede manipular), solo
/// evita el caso común de entrar y salir repetido por accidente o aburrimiento.
///
/// Se guarda en SharedPreferences (no solo en memoria) para que el cooldown
/// sobreviva un reinicio de la app.
class ViewCooldown {
  ViewCooldown._();

  static const _key = 'view_cooldown_timestamps';
  static const cooldown = Duration(minutes: 10);

  /// True si ya pasó el cooldown (o nunca se registró) para [id] y por lo
  /// tanto SÍ corresponde mandar la vista al backend.
  static Future<bool> shouldRegisterView(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final map = _readMap(prefs);
    final lastMillis = map[id];
    if (lastMillis == null) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMillis);
    return DateTime.now().difference(last) >= cooldown;
  }

  /// Marca [id] como visto ahora, para que no se vuelva a registrar hasta
  /// que pase el cooldown.
  static Future<void> markViewed(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final map = _readMap(prefs);
    map[id] = DateTime.now().millisecondsSinceEpoch;

    // Poda oportunista: no dejar crecer el mapa indefinidamente.
    final cutoff = DateTime.now().subtract(cooldown).millisecondsSinceEpoch;
    map.removeWhere((_, millis) => millis < cutoff);

    await prefs.setString(_key, jsonEncode(map));
  }

  static Map<String, int> _readMap(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      return {};
    }
  }
}
