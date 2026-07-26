const db = require('../database');
const { requireAuth } = require('../auth');

function register(app) {
  // GET /api/chat/conversations - listar conversaciones del usuario autenticado
  app.get('/api/chat/conversations', requireAuth, (req, res) => {
    const conversations = db.getConversationsForUser(req.user.id);
    const unreadCount = db.getUnreadMessageCount(req.user.id);

    // Adjuntar datos del producto y del otro usuario
    const enriched = conversations.map(conv => {
      const product = db.getProductById(conv.productId);
      const otherUserId = conv.buyerId === req.user.id ? conv.sellerId : conv.buyerId;
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
  app.get('/api/chat/conversations/:id/messages', requireAuth, (req, res) => {
    const conv = db.getDb().prepare('SELECT * FROM conversations WHERE id = ?').get(req.params.id);
    if (!conv) return res.status(404).json({ error: 'Conversación no encontrada' });

    // Verificar que el usuario pertenece a la conversación
    if (conv.buyer_id !== req.user.id && conv.seller_id !== req.user.id) {
      return res.status(403).json({ error: 'No tienes acceso a esta conversación' });
    }

    const messages = db.getMessages(req.params.id);
    // Marcar mensajes como leídos
    db.markConversationMessagesRead(req.params.id, req.user.id);

    res.json({ messages });
  });

  // POST /api/chat/send - enviar un mensaje (crea conversación si no existe)
  app.post('/api/chat/send', requireAuth, (req, res) => {
    const { productId, sellerId, text, conversationId } = req.body;
    const userId = req.user.id;

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

    const messages = db.getMessages(conversation.id);
    res.status(201).json({ messages, conversationId: conversation.id });
  });

  // DELETE /api/chat/messages/:id - eliminar un mensaje propio
  app.delete('/api/chat/messages/:id', requireAuth, (req, res) => {
    const deleted = db.deleteMessage(req.params.id, req.user.id);
    if (!deleted) {
      return res.status(404).json({ error: 'Mensaje no encontrado o no tienes permiso para eliminarlo' });
    }
    res.json({ success: true });
  });
}

module.exports = { register };
