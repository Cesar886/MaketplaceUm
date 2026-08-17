import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda si este dispositivo ya vio el onboarding.
///
/// Va en SharedPreferences y no en el perfil del backend a propósito: el
/// onboarding se muestra ANTES de cualquier login (la app se navega entera
/// sin cuenta, ver `splash_screen.dart`), así que en el momento en que hay
/// que decidir si mostrarlo todavía no existe un usuario al que colgarle la
/// preferencia.
class OnboardingService {
  OnboardingService._();

  static const _key = 'onboarding_seen';

  /// `false` en instalación nueva — que es justo cuando hay que mostrarlo.
  static Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  /// Marca el onboarding como visto. Lo llaman tanto "Empezar" como
  /// "Saltar": saltarlo también cuenta, o el botón no estaría saltando nada.
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  /// Vuelve a mostrarlo en el próximo arranque. Sirve para probarlo sin
  /// reinstalar la app.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
