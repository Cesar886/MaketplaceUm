import 'package:flutter/foundation.dart';

import '../utils/estado_conexion.dart';

/// Estado en línea de otras personas, en memoria y compartido por toda la app.
///
/// Es la única fuente de verdad para el puntito: las pantallas leen de aquí
/// y no de su propio `setState`, así que la lista de chats y el perfil del
/// mismo vendedor nunca se contradicen.
///
/// Se alimenta de dos sitios que se complementan: las respuestas REST
/// (semilla, para que la primera pintura ya salga bien) y los eventos de
/// Socket.IO (actualización en vivo).
class PresenceService extends ChangeNotifier {
  final Map<String, EstadoConexion> _estados = {};

  /// Estado conocido de [userId]. Nunca es null: lo que no se sabe se trata
  /// como desconectado, que es también lo que llega de quien oculta su
  /// estado.
  EstadoConexion estadoDe(String userId) =>
      _estados[userId] ?? EstadoConexion.desconocido;

  /// Guarda lo que trajo una respuesta REST.
  void sembrar(String userId, EstadoConexion estado) {
    _guardar(userId, estado);
  }

  /// Aplica un evento `presence:update` del socket.
  void aplicarEvento(Map<String, dynamic> evento) {
    final userId = evento['userId'];
    if (userId is! String || userId.isEmpty) return;

    final crudo = evento['lastActive'];
    _guardar(
      userId,
      EstadoConexion(
        enLinea: evento['online'] == true,
        ultimaActividad: crudo is String
            ? DateTime.tryParse(crudo)
            // Un evento de conexión no trae fecha; se conserva la última
            // conocida para no perder el "activo hace X" cuando se vaya.
            : _estados[userId]?.ultimaActividad,
      ),
    );
  }

  /// Aplica el `presence:snapshot` que responde el backend al suscribirse.
  ///
  /// Necesita [consultados] además de [enLinea] porque el servidor solo
  /// enumera a los conectados: sin saber por quiénes se preguntó no se podría
  /// APAGAR a alguien que se fue mientras la app estaba en segundo plano, y
  /// se quedaría con un punto verde mentiroso hasta el siguiente evento.
  void aplicarSnapshot({
    required List<String> consultados,
    required List<String> enLinea,
  }) {
    final conectados = enLinea.toSet();
    var cambio = false;
    for (final userId in consultados) {
      final anterior = estadoDe(userId);
      final nuevo = EstadoConexion(
        enLinea: conectados.contains(userId),
        ultimaActividad: anterior.ultimaActividad,
      );
      if (nuevo == anterior) continue;
      _estados[userId] = nuevo;
      cambio = true;
    }
    if (cambio) notifyListeners();
  }

  /// Olvida todo. Se llama al cerrar sesión: si no, la siguiente cuenta en el
  /// mismo dispositivo hereda el estado cacheado por la anterior.
  void limpiar() {
    if (_estados.isEmpty) return;
    _estados.clear();
    notifyListeners();
  }

  void _guardar(String userId, EstadoConexion estado) {
    // Comparar antes de notificar evita repintar la lista entera cada vez que
    // llega un evento que dice lo que ya sabíamos (pasa con las reconexiones
    // del socket, que reenvían el estado de todos).
    if (_estados[userId] == estado) return;
    _estados[userId] = estado;
    notifyListeners();
  }
}
