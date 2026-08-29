import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Sesión de invitado: permite chatear sin cuenta.
///
/// Sustituye al UUID que la app se generaba sola en [AnonymousId] y mandaba
/// como `senderId` en cada petición de chat. Aquel esquema tenía dos fallos
/// que esta clase cierra:
///
///  1. El identificador lo elegía el cliente, así que el backend no podía
///     distinguir al invitado legítimo de quien copiara su id — y el id viaja
///     en cada mensaje, a la vista de cualquiera en la conversación.
///  2. El UUID no era aleatorio: salía de un generador congruencial sembrado
///     con `DateTime.now()`, así que era reconstruible sabiendo poco más que
///     cuándo se instaló la app.
///
/// Ahora el identificador lo emite y lo firma el servidor
/// (`POST /api/auth/anon`), y lo que se guarda es el token. La credencial es
/// el token, no el id: saber el id de alguien ya no sirve para suplantarlo.
///
/// [AnonymousId] sigue existiendo para lo que siempre fue —el `deviceId` con
/// el que el feed acumula afinidad sin sesión—, que no es una identidad y no
/// autentica nada.
class AnonSession {
  static const _tokenKey = 'anon_session_token';
  static const _idKey = 'anon_session_id';

  static String? _token;
  static String? _anonId;

  /// Id de invitado de esta instalación, o null si aún no se pidió sesión.
  /// Sirve para pintar "este mensaje es mío"; no para autenticar.
  static String? get anonId => _anonId;

  /// Deja a [ApiService] con un token utilizable para el chat.
  ///
  /// Si ya hay sesión de cuenta real no toca nada: el token de la cuenta
  /// manda sobre el de invitado. Si no, reutiliza el token de invitado
  /// guardado y solo pide uno nuevo cuando no hay o caducó.
  static Future<void> ensure() async {
    if (ApiService.token != null) return;

    final prefs = await SharedPreferences.getInstance();
    _token ??= prefs.getString(_tokenKey);
    _anonId ??= prefs.getString(_idKey);

    if (_token != null && !_expirado(_token!)) {
      ApiService.setToken(_token!);
      return;
    }

    final sesion = await ApiService.crearSesionInvitado();
    _token = sesion['token'] as String;
    _anonId = sesion['anonId'] as String;
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_idKey, _anonId!);
    ApiService.setToken(_token!);
  }

  /// Reaplica el token de invitado tras cerrar sesión, para que quien vuelve
  /// a ser invitado conserve sus conversaciones de invitado.
  static Future<void> restaurarTrasLogout() async {
    ApiService.clearToken();
    await ensure();
  }

  /// Olvida la sesión de invitado (p. ej. al registrarse de verdad).
  static Future<void> reset() async {
    _token = null;
    _anonId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_idKey);
  }

  /// ¿Caducó el JWT? Se mira el `exp` del payload sin verificar la firma:
  /// aquí no se está autorizando nada, solo evitando un viaje al servidor
  /// que iba a responder 401 de todos modos. La autoridad sigue siendo el
  /// backend, que sí verifica.
  static bool _expirado(String token) {
    try {
      final partes = token.split('.');
      if (partes.length != 3) return true;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'] as int?;
      if (exp == null) return true;
      // Margen de un día: renovar antes de que expire evita que el token
      // muera justo mientras el usuario escribe.
      final limite = DateTime.now().add(const Duration(days: 1));
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000).isBefore(limite);
    } catch (_) {
      return true;
    }
  }
}
