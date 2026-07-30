import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_service.dart';

/// Servicio para manejar la conexión Socket.IO en tiempo real para el chat.
///
/// Se conecta al mismo backend que la API REST y maneja eventos de:
/// - Mensajes nuevos (new:message)
/// - Mensajes eliminados (message:deleted)
/// - Indicador de escritura (typing:start / typing:stop)
/// - Actualización de conversaciones (conversation:updated)
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

  /// Stream de mensajes nuevos: emite { message, conversationId }
  Stream<Map<String, dynamic>> get onNewMessage => _messageController.stream;

  /// Stream de IDs de mensajes eliminados
  Stream<String> get onMessageDeleted => _deletedController.stream;

  /// Stream de eventos de escritura: emite { userId, conversationId }
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;

  /// Stream de conversaciones actualizadas: emite conversationId
  Stream<String> get onConversationUpdated => _convUpdateController.stream;

  bool get isConnected => _connected;

  /// Inicia la conexión Socket.IO
  void connect() {
    if (_socket != null && _connected) return;

    final uri = Uri.parse(ApiService.baseUrl);
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

  /// Desconectar y limpiar recursos
  void disconnect() {
    _socket?.disconnect();
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
  }
}
