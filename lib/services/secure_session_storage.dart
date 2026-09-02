import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Credenciales cifradas por Android Keystore / iOS Keychain.
/// Migra y elimina silenciosamente los JWT que versiones anteriores dejaron
/// en SharedPreferences.
class SecureSessionStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> read(String key) async {
    final secure = await _storage.read(key: key);
    if (secure != null) return secure;
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(key);
    if (legacy != null) {
      await _storage.write(key: key, value: legacy);
      await prefs.remove(key);
    }
    return legacy;
  }

  static Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<void> delete(String key) => _storage.delete(key: key);
}
