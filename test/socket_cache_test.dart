// Documenta la suposición sobre la que descansa el guardia de
// `ChatSocketService.connect()`.
//
// `connect()` sale temprano si `_socket != null` en vez de si ya está
// conectado, porque `io.io()` NO crea un socket nuevo por llamada: devuelve
// el que ya tiene cacheado para esa URI. Registrar los handlers otra vez
// sobre esa misma instancia los SUMA a los anteriores, y cada mensaje de
// chat y cada comentario llega duplicado.
//
// El bug se volvió alcanzable al llamar `connect()` también desde el detalle
// de producto (comentarios): esa pantalla se abre muy seguido justo mientras
// el socket sigue en handshake, con `_socket` ya creado y `_connected` aún
// en false.
//
// Si una actualización del paquete cambiara este comportamiento, este test
// falla y avisa de que el comentario del guardia dejó de ser cierto.

import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

void main() {
  test('io.io() devuelve la MISMA instancia para la misma URI', () {
    // autoConnect en false: esto no abre ninguna conexión de red.
    final opciones = <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    };

    final a = io.io('http://127.0.0.1:65001', opciones);
    final b = io.io('http://127.0.0.1:65001', opciones);

    expect(
      identical(a, b),
      isTrue,
      reason: 'si dejaran de compartirse, el guardia de connect() sobra',
    );

    a.dispose();
  });

  test('dispose() sí quita los handlers; disconnect() no', () {
    // Por esto `ChatSocketService.disconnect()` usa dispose(): dejar los
    // listeners puestos y luego reconectar sobre la instancia cacheada es la
    // otra forma de acabar con handlers duplicados.
    final socket = io.io('http://127.0.0.1:65002', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.on('new:comment', (_) {});
    expect(socket.hasListeners('new:comment'), isTrue);

    socket.disconnect();
    expect(
      socket.hasListeners('new:comment'),
      isTrue,
      reason: 'disconnect() no limpia listeners — de ahí el uso de dispose()',
    );

    socket.dispose();
    expect(socket.hasListeners('new:comment'), isFalse);
  });
}
