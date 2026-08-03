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
}
