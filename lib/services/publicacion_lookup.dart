import '../models.dart';
import 'api_service.dart';

/// Resuelve un id de publicación a un [Product], venga de donde venga.
///
/// Un link compartido y un código QR traen un id pelón: no dicen si es un
/// producto en venta o una publicación "se busca". Adentro son cosas distintas
/// (tablas y endpoints distintos), pero la pantalla de detalle es la misma, así
/// que aquí se prueba una y luego la otra.
///
/// Vive aparte para que el escáner de QR y el manejador de deep links usen
/// exactamente la misma resolución: antes el escáner solo sabía de productos y
/// un QR de búsqueda —que la propia app genera— fallaba con "producto no
/// encontrado".
///
/// Devuelve null si el id no corresponde a ninguna de las dos, o si la red
/// falló. Quien llama decide qué decirle al usuario.
Future<Product?> buscarPublicacion(String id) async {
  try {
    return await ApiService.getProduct(id);
  } catch (_) {
    // No era un producto (404) o falló la red. Se intenta como búsqueda antes
    // de darlo por perdido.
  }

  try {
    return Product.fromWantedPost(await ApiService.getWantedPost(id));
  } catch (_) {
    return null;
  }
}
