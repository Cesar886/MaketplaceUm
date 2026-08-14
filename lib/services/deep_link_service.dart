import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../main.dart' show navigatorKey, scaffoldMessengerKey;
import '../screens/product_detail_screen.dart';
import 'deep_link_parser.dart';
import 'publicacion_lookup.dart';

/// Abre la app en el detalle de una publicación cuando el sistema le entrega
/// un link de mercaditoum.site.
///
/// Android decide si el link llega aquí o al navegador según la verificación
/// de `/.well-known/assetlinks.json` (ver AndroidManifest.xml). Cuando llega
/// aquí, la app se comporta como si el usuario hubiera tocado la publicación
/// dentro de la app: mismo `ProductDetailScreen`, misma pila de navegación.
///
/// Hay dos momentos en que puede llegar un link, y son distintos:
///   - App abierta: se navega de inmediato.
///   - Arranque en frío: el link llega ANTES de que exista la pantalla a la
///     que navegar (SplashScreen todavía está restaurando la sesión, y al
///     terminar hace pushReplacement a MainShell, que borraría cualquier cosa
///     apilada antes). Por eso el link se guarda y se procesa cuando
///     [marcarAppLista] avisa que ya hay dónde navegar.
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  StreamSubscription<Uri>? _suscripcion;
  Uri? _pendiente;
  bool _appLista = false;

  /// Empieza a escuchar links entrantes. Se llama una sola vez, al arrancar.
  ///
  /// `uriLinkStream` emite también el link con el que se abrió la app en frío,
  /// así que NO se consulta además `getInitialLink()`: eso entregaría el mismo
  /// link dos veces y abriría la publicación por duplicado.
  void iniciar() {
    _suscripcion ??= AppLinks().uriLinkStream.listen(
      _alRecibirLink,
      // Un link malformado no debe tumbar la app: el stream se mantiene vivo
      // para los siguientes.
      onError: (Object _) {},
    );
  }

  /// Avisa que ya existe una pantalla sobre la cual navegar. La llama
  /// SplashScreen justo después de entrar a MainShell.
  void marcarAppLista() {
    _appLista = true;

    final pendiente = _pendiente;
    _pendiente = null;
    if (pendiente != null) _alRecibirLink(pendiente);
  }

  void _alRecibirLink(Uri uri) {
    if (!_appLista) {
      // Solo se guarda el último: si llegaran dos links antes de arrancar, el
      // que el usuario espera ver es el más reciente.
      _pendiente = uri;
      return;
    }

    final id = idDePublicacionEnLink(uri);
    // Un link que no reconocemos se ignora en silencio. No hay error que
    // mostrarle al usuario: él tocó un link, no pidió nada dentro de la app.
    if (id == null) return;

    unawaited(_abrirPublicacion(id));
  }

  Future<void> _abrirPublicacion(String id) async {
    // El link no dice si el id es de un producto o de una búsqueda; lo
    // resuelve buscarPublicacion, igual que para un QR escaneado.
    final publicacion = await buscarPublicacion(id);

    final navegador = navigatorKey.currentState;
    if (navegador == null) return;

    if (publicacion == null) {
      // Aquí sí se avisa: el usuario tocó un link esperando ver algo, y la
      // app se abrió sin llevarlo a ningún lado. El silencio se leería como
      // que la app está rota.
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Esta publicación ya no está disponible'),
        ),
      );
      return;
    }

    // push y no pushReplacement: al volver, el usuario se queda dentro de la
    // app en el feed, en vez de salir a la pantalla anterior del sistema.
    await navegador.push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(product: publicacion),
      ),
    );
  }
}
