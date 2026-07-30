const db = require('../database');
const { sendPush } = require('../push');

function register(app) {
  // GET /api/chat/conversations - listar conversaciones de un usuario (anónimo o no)
  app.get('/api/chat/conversations', (req, res) => {
    const userId = req.query.userId;
    if (!userId) return res.status(400).json({ error: 'userId (query param) es requerido' });
    const conversations = db.getConversationsForUser(userId);
    const unreadCount = db.getUnreadMessageCount(userId);

    // Adjuntar datos del producto y del otro usuario
    const enriched = conversations.map(conv => {
      const product = db.getProductById(conv.productId);
      const otherUserId = conv.buyerId === userId ? conv.sellerId : conv.buyerId;
      const otherUser = db.getDb().prepare('SELECT * FROM sellers WHERE id = ?').get(otherUserId);
      const lastMessage = db.getDb().prepare(
        'SELECT * FROM messages WHERE conversation_id = ? ORDER BY created_at DESC LIMIT 1'
      ).get(conv.id);

      return {
        ...conv,
        product: product ? {
          id: product.id,
          title: product.title,
          price: product.price,
          images: product.images,
          imageIcon: product.imageIcon,
          imageColor: product.imageColor,
        } : null,
        otherUser: otherUser ? {
          id: otherUser.id,
          name: otherUser.name,
          avatarInitials: otherUser.avatarInitials || '',
        } : null,
        lastMessage: lastMessage ? {
          id: lastMessage.id,
          senderId: lastMessage.sender_id,
          text: lastMessage.text,
          createdAt: lastMessage.created_at,
          read: !!lastMessage.read,
        } : null,
      };
    });

    res.json({ conversations: enriched, unreadCount });
  });

  // GET /api/chat/conversations/:id/messages - obtener mensajes de una conversación
  app.get('/api/chat/conversations/:id/messages', (req, res) => {
    const conv = db.getDb().prepare('SELECT * FROM conversations WHERE id = ?').get(req.params.id);
    if (!conv) return res.status(404).json({ error: 'Conversación no encontrada' });

    const messages = db.getMessages(req.params.id);
    // Marcar mensajes como leídos si el sender es distinto al que pide
    const userId = req.query.userId;
    if (userId && (conv.buyer_id === userId || conv.seller_id === userId)) {
      db.markConversationMessagesRead(req.params.id, userId);
    }

    res.json({ messages });
  });

  // POST /api/chat/send - enviar un mensaje (anónimo, no requiere auth)
  app.post('/api/chat/send', (req, res) => {
    const { productId, sellerId, text, conversationId } = req.body;
    const userId = req.body.senderId;

    if (!userId) {
      return res.status(400).json({ error: 'senderId es requerido' });
    }
    if (!text || !text.trim()) {
      return res.status(400).json({ error: 'El mensaje no puede estar vacío' });
    }

    let conversation;

    // Si se proporciona conversationId, usarla (útil cuando el vendedor responde)
    if (conversationId) {
      conversation = db.getDb().prepare('SELECT * FROM conversations WHERE id = ?').get(conversationId);
      if (!conversation) {
        return res.status(404).json({ error: 'Conversación no encontrada' });
      }
      // Verificar que el usuario pertenece a la conversación
      if (conversation.buyer_id !== userId && conversation.seller_id !== userId) {
        return res.status(403).json({ error: 'No tienes acceso a esta conversación' });
      }
    } else {
      // Crear nueva conversación (solo el comprador puede iniciar)
      if (!productId || !sellerId) {
        return res.status(400).json({ error: 'productId y sellerId son requeridos para iniciar una conversación' });
      }

      // No puedes enviarte mensaje a ti mismo
      if (userId === sellerId) {
        return res.status(400).json({ error: 'No puedes enviarte un mensaje a ti mismo' });
      }

      // Buscar o crear conversación
      conversation = db.findConversation(productId, userId, sellerId);
      if (!conversation) {
        const convId = `conv_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        db.createConversation(convId, productId, userId, sellerId);
        conversation = db.getDb().prepare('SELECT * FROM conversations WHERE id = ?').get(convId);
      }
    }

    // Crear mensaje
    const msgId = `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    db.createMessage(msgId, conversation.id, userId, text.trim());

    // Notificar al otro usuario (seller si el que envía es buyer, buyer si el que envía es seller)
    const otherUserId = conversation.buyer_id === userId ? conversation.seller_id : conversation.buyer_id;
    const sender = db.getDb().prepare('SELECT name FROM sellers WHERE id = ?').get(userId);
    const notifId = `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
    const isFirst = db.getDb().prepare(
      'SELECT COUNT(*) as c FROM messages WHERE conversation_id = ?'
    ).get(conversation.id);
    const product = db.getProductById(conversation.product_id);
    db.createNotification(
      notifId,
      otherUserId,
      isFirst && isFirst.c <= 1 ? 'new_chat' : 'new_message',
      'Nuevo mensaje',
      `${sender?.name || 'Alguien'} te escribió: \"${text.trim().slice(0, 80)}\"`,
      { conversationId: conversation.id, productId: conversation.product_id, senderId: userId }
    );

    // Enviar push notification via OneSignal
    const senderName = sender?.name || 'Alguien';
    const pushTitle = isFirst && isFirst.c <= 1 ? 'Nuevo chat' : 'Nuevo mensaje';
    const pushBody = `${senderName}: ${text.trim().slice(0, 100)}`;
    sendPush(
      [otherUserId],
      pushTitle,
      pushBody,
      { conversationId: conversation.id, productId: conversation.product_id, type: isFirst && isFirst.c <= 1 ? 'new_chat' : 'new_message' }
    );

    const messages = db.getMessages(conversation.id);

    // ── Emitir evento en tiempo real via Socket.IO ──
    const io = app.get('io');
    if (io) {
      // Notificar a los usuarios en la sala de la conversación
      const newMsg = messages[messages.length - 1];
      io.to(`conv:${conversation.id}`).emit('new:message', {
        message: {
          id: newMsg.id,
          conversationId: newMsg.conversationId,
          senderId: newMsg.senderId,
          text: newMsg.text,
          createdAt: newMsg.createdAt,
          read: false,
        },
        conversationId: conversation.id,
      });

      // Notificar al otro usuario (si no está en la sala) para que refresque su lista
      io.to(`user:${otherUserId}`).emit('conversation:updated', {
        conversationId: conversation.id,
      });
    }

    res.status(201).json({ messages, conversationId: conversation.id });
  });

  // DELETE /api/chat/messages/:id - eliminar un mensaje propio (el senderId debe coincidir)
  app.delete('/api/chat/messages/:id', (req, res) => {
    const senderId = req.query.senderId;
    if (!senderId) return res.status(400).json({ error: 'senderId (query param) requerido' });
    const msg = db.getDb().prepare('SELECT * FROM messages WHERE id = ?').get(req.params.id);
    const deleted = db.deleteMessage(req.params.id, senderId);
    if (!deleted) {
      return res.status(404).json({ error: 'Mensaje no encontrado o no tienes permiso para eliminarlo' });
    }

    // Emitir evento de eliminación via Socket.IO
    const io = app.get('io');
    if (io && msg) {
      io.to(`conv:${msg.conversation_id}`).emit('message:deleted', {
        messageId: req.params.id,
        conversationId: msg.conversation_id,
      });
    }

    res.json({ success: true });
  });
}

module.exports = { register };
