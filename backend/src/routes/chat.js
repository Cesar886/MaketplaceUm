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
    const { productId, sellerId, text } = req.body;
    const buyerId = req.user.id;

    if (!productId || !text) {
      return res.status(400).json({ error: 'productId y text son requeridos' });
    }
    if (!text.trim()) {
      return res.status(400).json({ error: 'El mensaje no puede estar vacío' });
    }

    // No puedes enviarte mensaje a ti mismo
    if (buyerId === sellerId) {
      return res.status(400).json({ error: 'No puedes enviarte un mensaje a ti mismo' });
    }

    // Buscar o crear conversación
    let conversation = db.findConversation(productId, buyerId, sellerId);
    if (!conversation) {
      const convId = `conv_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      db.createConversation(convId, productId, buyerId, sellerId);
      conversation = db.getDb().prepare('SELECT * FROM conversations WHERE id = ?').get(convId);
    }

    // Crear mensaje
    const msgId = `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    db.createMessage(msgId, conversation.id, buyerId, text.trim());

    // Notificar al vendedor
    const product = db.getProductById(productId);
    const buyer = db.getDb().prepare('SELECT name FROM sellers WHERE id = ?').get(buyerId);
    const notifId = `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
    const isFirst = db.getDb().prepare(
      'SELECT COUNT(*) as c FROM messages WHERE conversation_id = ?'
    ).get(conversation.id);
    db.createNotification(
      notifId,
      sellerId,
      isFirst && isFirst.c <= 1 ? 'new_chat' : 'new_message',
      'Nuevo mensaje',
      `${buyer?.name || 'Alguien'} te escribió: "${text.trim().slice(0, 80)}"`,
      { conversationId: conversation.id, productId, senderId: buyerId }
    );

    const messages = db.getMessages(conversation.id);
    res.status(201).json({ messages, conversationId: conversation.id });
  });
}

module.exports = { register };
