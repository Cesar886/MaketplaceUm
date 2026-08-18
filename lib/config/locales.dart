import 'package:flutter/widgets.dart';

/// Configuración de idiomas de la app, en un solo lugar.
///
/// `main.dart`, la pantalla de idioma y los tests leen de aquí: agregar un
/// idioma nuevo es soltar su JSON en `assets/translations/` y añadir una
/// entrada a [localesSoportados], sin tocar nada más.
class AppLocales {
  const AppLocales._();

  /// Español. Es el idioma original de la app: todos los textos de
  /// `es.json` son el literal que estaba hardcodeado en el widget.
  static const es = Locale('es');

  /// Inglés.
  static const en = Locale('en');

  static const List<Locale> localesSoportados = [es, en];

  /// Idioma por defecto y fallback. Si el sistema está en un idioma que no
  /// soportamos, o si a una clave le falta traducción, se cae a español.
  static const fallback = es;

  /// Carpeta de los JSON, relativa a la raíz del proyecto. Declarada en
  /// `pubspec.yaml` como asset.
  static const rutaTraducciones = 'assets/translations';

  /// Nombre del idioma escrito en ese mismo idioma ("Español", "English").
  ///
  /// No se traduce: en un selector de idioma cada opción debe leerse en su
  /// propia lengua, porque quien la busca todavía no entiende la actual.
  static String nombreNativo(Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return 'English';
      case 'es':
      default:
        return 'Español';
    }
  }

  /// Clave de traducción del nombre del idioma ("Inglés" / "English"), para
  /// cuando el nombre sí debe salir en el idioma activo — por ejemplo en el
  /// snackbar de confirmación.
  static String claveNombre(Locale locale) => 'language.${locale.languageCode}';
}
