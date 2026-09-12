import '../config/app_config.dart';

/// Decide si un link que llegó de fuera apunta a una publicación de Marketplace
/// UM, y a cuál.
///
/// Vive aparte de `DeepLinkService` porque es la única parte del deep linking
/// que es lógica pura: no toca plataforma, ni red, ni navegación. Separarlo
/// deja probarlo directo (test/deep_link_service_test.dart) y, sobre todo,
/// deja que el chequeo de dominio —que es lo que impide que un link ajeno
/// abra la app— se revise sin leer el resto.

/// Segmento de ruta del sitio bajo el que vive el detalle público. Debe
/// coincidir con `android:pathPrefix` del intent-filter en AndroidManifest.xml
/// y con la ruta `/producto/[id]` del sitio.
const String rutaPublicacion = 'producto';

/// Hosts del sitio que se aceptan.
///
/// `www` se acepta aunque el intent-filter de Android no lo declare (allá
/// declararlo rompería la verificación del dominio desnudo en Android 11 y
/// anteriores): aquí no cuesta nada y cubre un link pegado a mano.
bool _esHostDelSitio(String host) {
  final normalizado = host.toLowerCase();
  return normalizado == AppConfig.webDomain ||
      normalizado == 'www.${AppConfig.webDomain}';
}

/// Descarta ids vacíos o de puro espacio, que producirían una petición al
/// backend garantizada a fallar.
String? _idValido(String crudo) {
  final id = crudo.trim();
  return id.isEmpty ? null : id;
}

/// Id de la publicación que identifica [uri], o null si el link no apunta a
/// una publicación de Marketplace UM.
String? idDePublicacionEnLink(Uri uri) {
  final segmentos = uri.pathSegments;

  // App Link del sitio: https://marketplace-um.me/producto/<id>
  if (uri.scheme == 'https' || uri.scheme == 'http') {
    // Se compara el host COMPLETO, nunca con `contains`: un dominio como
    // 'marketplace-um.me.malo.com' contiene el nuestro y no es nuestro.
    if (!_esHostDelSitio(uri.host)) return null;
    if (segmentos.length != 2 || segmentos.first != rutaPublicacion) {
      return null;
    }
    return _idValido(segmentos[1]);
  }

  // Esquema propio, el que traen los códigos QR que genera la app.
  if (uri.scheme == 'mercaditoum') {
    // 'payments' es del flujo de Mercado Pago y lo maneja otra parte.
    if (uri.host != 'product' && uri.host != 'wanted') return null;
    if (segmentos.length != 1) return null;
    return _idValido(segmentos.first);
  }

  return null;
}
