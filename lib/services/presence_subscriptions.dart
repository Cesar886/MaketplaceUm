/// Contador de referencias de las suscripciones de presencia.
///
/// Existe porque varias pantallas siguen a la MISMA persona a la vez —la
/// lista de chats y, encima, su perfil— y comparten una sola conexión
/// Socket.IO. Sin contar referencias, el `dispose` del perfil abandonaría la
/// sala `presence:<id>` y la lista de chats dejaría de recibir los cambios de
/// esa persona sin que nada lo delatara: el punto simplemente se quedaría
/// congelado en el último valor conocido.
///
/// Separado del servicio de socket para poder probar esta parte, que es la
/// que tiene lógica, sin red de por medio.
class PresenceSubscriptions {
  final Map<String, int> _referencias = {};

  /// Todos los seguidos ahora mismo. Se usa al reconectar: el servidor pierde
  /// las salas al caerse el transporte, así que hay que volver a pedirlas o
  /// el punto se queda congelado hasta que se navegue a otra pantalla.
  List<String> get activos => _referencias.keys.toList();

  /// Registra interés en [userIds] y devuelve solo aquellos por los que hay
  /// que emitir `presence:subscribe` (los que pasan de 0 a 1).
  List<String> agregar(List<String> userIds) {
    final nuevos = <String>[];
    for (final userId in userIds) {
      final previo = _referencias[userId] ?? 0;
      _referencias[userId] = previo + 1;
      if (previo == 0) nuevos.add(userId);
    }
    return nuevos;
  }

  /// Suelta el interés en [userIds] y devuelve aquellos que ya no sigue
  /// nadie, que son los únicos que hay que desuscribir.
  List<String> quitar(List<String> userIds) {
    final sobrantes = <String>[];
    for (final userId in userIds) {
      final previo = _referencias[userId];
      if (previo == null) continue;
      if (previo > 1) {
        _referencias[userId] = previo - 1;
        continue;
      }
      _referencias.remove(userId);
      sobrantes.add(userId);
    }
    return sobrantes;
  }

  /// Olvida todo (cierre de sesión / desconexión) y devuelve lo que seguía
  /// vivo, por si hay que soltarlo explícitamente.
  List<String> limpiar() {
    final vivos = _referencias.keys.toList();
    _referencias.clear();
    return vivos;
  }
}
