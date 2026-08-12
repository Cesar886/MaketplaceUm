import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/models.dart';

void main() {
  group('ChatMessage.fromJson con respuesta', () {
    test('un mensaje sin cita deja replyTo en null', () {
      final msg = ChatMessage.fromJson({
        'id': 'm1',
        'conversationId': 'c1',
        'senderId': 'u1',
        'text': 'hola',
        'createdAt': '2026-08-03 05:48:33',
        'read': false,
      });
      expect(msg.replyTo, isNull);
    });

    test('parsea la cita que manda el backend', () {
      final msg = ChatMessage.fromJson({
        'id': 'm2',
        'conversationId': 'c1',
        'senderId': 'u2',
        'text': 'Sí, disponible',
        'createdAt': '2026-08-03 05:49:00',
        'read': false,
        'replyTo': {
          'id': 'm1',
          'senderId': 'u1',
          'text': '¿Sigue disponible?',
          'imageUrl': null,
        },
      });
      expect(msg.replyTo, isNotNull);
      expect(msg.replyTo!.id, 'm1');
      expect(msg.replyTo!.senderId, 'u1');
      expect(msg.replyTo!.resumen, '¿Sigue disponible?');
    });

    test('la cita de una foto sin texto se resume como foto', () {
      const cita = RepliedMessage(
        id: 'm1',
        senderId: 'u1',
        text: '',
        imageUrl: '/uploads/x.webp',
      );
      expect(cita.resumen, '📷 Foto');
    });
  });

  group('comoEliminado', () {
    test('reemplaza el texto y quita la imagen sin perder la cita', () {
      // El punto del test: la versión anterior reconstruía el mensaje campo a
      // campo, así que cualquier campo nuevo (como replyTo) se perdía en
      // silencio al borrar.
      const original = ChatMessage(
        id: 'm2',
        conversationId: 'c1',
        senderId: 'u2',
        text: 'Sí, disponible',
        createdAt: '2026-08-03 05:49:00',
        read: true,
        imageUrl: '/uploads/x.webp',
        replyTo: RepliedMessage(id: 'm1', senderId: 'u1', text: '¿Hay?'),
      );

      final borrado = original.comoEliminado();

      expect(borrado.text, '[Mensaje eliminado]');
      expect(borrado.imageUrl, isNull);
      expect(borrado.id, 'm2');
      expect(borrado.createdAt, '2026-08-03 05:49:00');
      expect(borrado.read, isTrue);
      expect(borrado.replyTo?.id, 'm1');
    });
  });
}
