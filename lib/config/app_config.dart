class AppConfig {
  // Cambia esto a 'true' para usar el servidor local en desarrollo
  static const bool isDevelopment = false;

  // URL del servidor en producción
  static const String _prodApiBaseUrl = 'http://157.245.247.45:3000';

  // URL del servidor local
  // Nota: Si usas el emulador de Android, cambia esto a 'http://10.0.2.2:3000'
  static const String _devApiBaseUrl = 'http://127.0.0.1:3000';

  // URL Base para las peticiones HTTP a la API REST
  static String get apiBaseUrl =>
      isDevelopment ? _devApiBaseUrl : _prodApiBaseUrl;

  // URL para la conexión de Chat en tiempo real (Socket.IO)
  static String get socketUrl => apiBaseUrl;

  // ─── Sitio web público ──────────────────────────────────────────────
  //
  // Dominio del sitio (carpeta /website) que muestra una publicación a quien
  // abre un link compartido SIN tener la app instalada.
  //
  // Es una sola constante porque tiene que coincidir en tres lugares que
  // fallan de formas distintas si se desincronizan: el texto que genera
  // "Compartir", el parseo del link entrante, y el android:host del
  // intent-filter en AndroidManifest.xml (ese sí hay que cambiarlo a mano).
  static const String webDomain = 'mercaditoum.site';

  static String get webBaseUrl => 'https://$webDomain';

  /// URL pública de una publicación — producto o "se busca", que comparten
  /// ruta porque comparten el botón de compartir.
  static String urlPublicacion(String id) => '$webBaseUrl/producto/$id';
}
