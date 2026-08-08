import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';

/// Servicio para manejar la conexión Socket.IO en tiempo real.
///
/// Se conecta al mismo backend que la API REST y maneja eventos de:
/// - Mensajes nuevos (new:message)
/// - Mensajes eliminados (message:deleted)
/// - Indicador de escritura (typing:start / typing:stop)
/// - Actualización de conversaciones (conversation:updated)
/// - Comentarios de producto (new:comment / comment:deleted)
///
/// Conserva el nombre `ChatSocketService` aunque ya sirva también a los
/// comentarios: es UNA sola conexión Socket.IO para toda la app (el backend
/// distingue por prefijo de sala, `conv:` vs `product:`), y abrir un segundo
/// socket solo para el detalle de producto sería una conexión de más por
/// dispositivo a cambio de nada.
class ChatSocketService {
  ChatSocketService._();
  static final ChatSocketService instance = ChatSocketService._();

  io.Socket? _socket;
  bool _connected = false;

  // StreamControllers para exponer los eventos como streams
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _deletedController =
      StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _convUpdateController =
      StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _commentController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _commentDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream de mensajes nuevos: emite { message, conversationId }
  Stream<Map<String, dynamic>> get onNewMessage => _messageController.stream;

  /// Stream de comentarios nuevos: emite { productId, comment }
  Stream<Map<String, dynamic>> get onNewComment => _commentController.stream;

  /// Stream de comentarios eliminados: emite { productId, commentId }
  Stream<Map<String, dynamic>> get onCommentDeleted =>
      _commentDeletedController.stream;

  /// Stream de IDs de mensajes eliminados
  Stream<String> get onMessageDeleted => _deletedController.stream;

  /// Stream de eventos de escritura: emite { userId, conversationId }
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;

  /// Stream de conversaciones actualizadas: emite conversationId
  Stream<String> get onConversationUpdated => _convUpdateController.stream;

  bool get isConnected => _connected;

  /// Inicia la conexión Socket.IO. Idempotente: se puede llamar desde
  /// cualquier pantalla que necesite tiempo real, tantas veces como haga
  /// falta.
  void connect() {
    // El guardia mira `_socket`, NO `_connected`. Con `_connected` bastaba
    // mientras solo el chat llamaba aquí, pero un segundo llamador (el
    // detalle de producto, para los comentarios) entra fácilmente mientras
    // el socket todavía está haciendo el handshake: `_socket` ya existe y
    // `_connected` sigue en false. En ese caso se volvía a ejecutar todo lo
    // de abajo, y `io.io()` devuelve el socket YA CACHEADO para esta URI, así
    // que cada `.on(...)` se sumaba al anterior en vez de reemplazarlo. El
    // síntoma es cada mensaje y cada comentario apareciendo dos veces.
    if (_socket != null) {
      // Existe pero se cayó (p. ej. la app volvió de segundo plano): se
      // reabre el transporte sin volver a registrar los handlers.
      if (!_connected) _socket!.connect();
      return;
    }

    final uri = Uri.parse(AppConfig.socketUrl);
    _socket = io.io(
      '${uri.scheme}://${uri.host}:${uri.port}',
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      },
    );

    _socket!.onConnect((_) {
      _connected = true;
      debugPrint('🟢 ChatSocket conectado');
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      debugPrint('🔴 ChatSocket desconectado');
    });

    _socket!.on('new:message', (data) {
      if (data is Map<String, dynamic>) {
        _messageController.add(data);
      }
    });

    _socket!.on('message:deleted', (data) {
      if (data is Map<String, dynamic> && data['messageId'] is String) {
        _deletedController.add(data['messageId'] as String);
      }
    });

    _socket!.on('typing:start', (data) {
      if (data is Map<String, dynamic>) {
        _typingController.add({...data, 'typing': true});
      }
    });

    _socket!.on('typing:stop', (data) {
      if (data is Map<String, dynamic>) {
        _typingController.add({...data, 'typing': false});
      }
    });

    _socket!.on('conversation:updated', (data) {
      if (data is Map<String, dynamic> && data['conversationId'] is String) {
        _convUpdateController.add(data['conversationId'] as String);
      }
    });

    _socket!.on('new:comment', (data) {
      if (data is Map<String, dynamic>) {
        _commentController.add(data);
      }
    });

    _socket!.on('comment:deleted', (data) {
      if (data is Map<String, dynamic>) {
        _commentDeletedController.add(data);
      }
    });

    _socket!.onConnectError((_) {
      debugPrint('⚠️ ChatSocket error de conexión');
    });

    _socket!.connect();
  }

  /// Unirse a la sala de una conversación para recibir sus eventos
  void joinConversation(String conversationId) {
    _socket?.emit('join:conversation', [conversationId]);
  }

  /// Salir de la sala de una conversación
  void leaveConversation(String conversationId) {
    _socket?.emit('leave:conversation', [conversationId]);
  }

  /// Unirse a la sala de un producto para recibir sus comentarios en vivo.
  ///
  /// Se llama al entrar al detalle y hay que salir en el `dispose` de la
  /// pantalla: la conexión es única y compartida, así que una sala que no se
  /// abandona sigue recibiendo eventos de un producto que ya nadie mira.
  void joinProduct(String productId) {
    _socket?.emit('join:product', [productId]);
  }

  /// Salir de la sala de un producto.
  void leaveProduct(String productId) {
    _socket?.emit('leave:product', [productId]);
  }

  /// Registrar el userId para recibir notificaciones de nuevas conversaciones
  void registerUser(String userId) {
    _socket?.emit('register:user', [userId]);
  }

  /// Notificar que el usuario está escribiendo
  void emitTypingStart(String conversationId, String userId) {
    _socket?.emit('typing:start', {
      'conversationId': conversationId,
      'userId': userId,
    });
  }

  /// Notificar que el usuario dejó de escribir
  void emitTypingStop(String conversationId, String userId) {
    _socket?.emit('typing:stop', {
      'conversationId': conversationId,
      'userId': userId,
    });
  }

  /// Desconectar y limpiar recursos.
  ///
  /// Usa `dispose()` y no `disconnect()`: este último cierra el transporte
  /// pero DEJA los listeners puestos, y como `io.io()` devuelve el socket
  /// cacheado para la misma URI, el siguiente [connect] volvería a
  /// registrarlos encima de los viejos y cada evento llegaría duplicado.
  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }

  /// Liberar los StreamControllers
  void dispose() {
    disconnect();
    _messageController.close();
    _deletedController.close();
    _typingController.close();
    _convUpdateController.close();
    _commentController.close();
    _commentDeletedController.close();
  }
}
