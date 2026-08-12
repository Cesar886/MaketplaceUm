import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';

/// Provider del color de acento del perfil.
///
/// La fuente de verdad es el backend (`sellers.colorAcento`), porque el color
/// es parte del perfil y tiene que verse igual desde cualquier dispositivo.
/// SharedPreferences se conserva solo como CACHÉ de arranque: sin él, cada
/// apertura de la app pintaría el color de marca durante el tiempo que tarda
/// la primera petición y luego saltaría al color elegido.
class AccentProvider extends ChangeNotifier {
  static const _key = 'accent_swatch';

  AccentSwatch _swatch = AccentSwatch.defecto;
  bool _guardando = false;

  /// El servidor ya dijo cuál es el color real de este perfil.
  ///
  /// Existe por una carrera: la lectura del caché arranca en el constructor
  /// y es asíncrona, así que si el perfil llega del backend PRIMERO, el
  /// caché (que puede estar desactualizado, p. ej. tras cambiar el color en
  /// otro teléfono) terminaría de leerse después y pisaría el valor bueno.
  bool _servidorMando = false;

  AccentSwatch get swatch => _swatch;

  /// Hay un PATCH en vuelo. La UI lo usa para no disparar dos cambios
  /// encimados, que llegarían al backend sin orden garantizado.
  bool get guardando => _guardando;

  AccentProvider() {
    _cargarCache();
  }

  Future<void> _cargarCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (_servidorMando) return;
    _swatch = AccentSwatch.porId(prefs.getString(_key));
    notifyListeners();
  }

  Future<void> _escribirCache(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }

  /// Trae el color desde el perfil del backend.
  ///
  /// Es lo que hace que el tema sobreviva a reinstalar la app: tras una
  /// instalación limpia SharedPreferences está vacío, así que el color solo
  /// puede venir del servidor. Se llama al restaurar sesión y al iniciar
  /// sesión, no al abrir el perfil — si esperara a que la persona entre a su
  /// perfil, la app arrancaría con el color de marca y cambiaría a media
  /// sesión.
  ///
  /// Falla en silencio: quedarse con el color cacheado (o el de marca) es
  /// mejor que bloquear el arranque por una preferencia visual.
  Future<void> sincronizarDesdeBackend(String sellerId) async {
    try {
      adoptarDe(await ApiService.getSeller(sellerId));
    } catch (_) {
      // Sin red al arrancar: el caché local ya pintó algo razonable.
    }
  }

  /// Sincroniza el color con lo que dice un perfil YA cargado. Se llama al
  /// abrir el perfil propio: si la persona cambió el color en otro
  /// teléfono, es aquí donde este se entera (a diferencia de
  /// [sincronizarDesdeBackend], que hace su propio fetch).
  void adoptarDe(Seller propio) {
    _servidorMando = true;
    final delServidor = AccentSwatch.porId(propio.colorAcento);
    if (delServidor.id == _swatch.id) return;
    _swatch = delServidor;
    _escribirCache(delServidor.id);
    notifyListeners();
  }

  /// Cambia el color y lo guarda en el perfil.
  ///
  /// Se pinta primero y se guarda después: elegir un color debe sentirse
  /// instantáneo. Si el PATCH falla se revierte al anterior y se relanza el
  /// error, para que la pantalla pueda avisar en vez de dejar un color que
  /// se perdería en la siguiente apertura.
  Future<void> seleccionar(
    AccentSwatch nuevo, {
    required String sellerId,
  }) async {
    if (nuevo.id == _swatch.id || _guardando) return;
    final anterior = _swatch;
    _swatch = nuevo;
    _guardando = true;
    notifyListeners();

    try {
      await ApiService.updateSellerProfile(
        sellerId: sellerId,
        colorAcento: nuevo.id,
      );
      await _escribirCache(nuevo.id);
    } catch (_) {
      _swatch = anterior;
      rethrow;
    } finally {
      _guardando = false;
      notifyListeners();
    }
  }
}

extension AccentContext on BuildContext {
  /// Swatch activo. Se suscribe a cambios: la pantalla se repinta al elegir
  /// otro color.
  AccentSwatch get accent => watch<AccentProvider>().swatch;

  /// El swatch como LÍNEA (anillo, indicador) ya resuelto contra el tema
  /// activo. Usar esto y no `accent.fill` para cualquier trazo sobre el
  /// fondo de la página: el relleno pastel sobre fondo claro no se ve.
  Color get accentLine => accent.line(Theme.of(this).brightness);
}
