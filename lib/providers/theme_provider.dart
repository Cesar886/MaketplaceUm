import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider que gestiona el modo oscuro de la app.
class ThemeProvider extends ChangeNotifier {
  static const _key = 'dark_mode';

  bool _darkMode = false;

  bool get darkMode => _darkMode;
  ThemeMode get themeMode => _darkMode ? ThemeMode.dark : ThemeMode.light;

  ThemeProvider() {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    _darkMode = prefs.getBool(_key) ?? false;
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    _darkMode = !_darkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _darkMode);
    notifyListeners();
  }
}
