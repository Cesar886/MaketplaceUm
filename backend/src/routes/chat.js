const path = require('path');
const fs = require('fs');
const sharp = require('sharp');
const multer = require('multer');
const db = require('../database');
const { sendPush } = require('../push');
const { presenciaDe } = require('./presenciaHttp');
const { requireAuth } = require('../auth');

const UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads');

const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, UPLOADS_DIR),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname) || '.jpg';
      cb(null, `chatimg_${Date.now()}_${Math.random().toString(36).slice(2, 6)}${ext}`);
    },
  }),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    cb(null, /\.(jpg|jpeg|png|gif|webp)$/i.test(path.extname(file.originalname)));
  },
});

/** Convierte una imagen recién subida a WebP y borra el original. */
async function convertToWebp(filePath) {
  const parsed = path.parse(filePath);
  const webpPath = path.join(parsed.dir, parsed.name + '.webp');
  const publicPath = '/uploads/' + parsed.name + '.webp';

  await sharp(filePath).webp({ quality: 80 }).toFile(webpPath);
  fs.unlinkSync(filePath);

  return publicPath;
}

/**
 * Busca la conversación indicada por conversationId, o la busca/crea a
 * partir de (productId, sellerId, senderId). Usado tanto por el envío de
 * texto como por el envío de imagen para no duplicar esta lógica.
 * Lanza un objeto { status, error } (no una excepción) para que la ruta
 * que llama decida cómo responder sin try/catch.
 */
function resolveConversation({ conversationId, productId, sellerId, userId }) {
  if (conversationId) {
    const conversation = db.getDb().prepare('SELECT * FROM conversations WHERE id = ?').get(conversationId);
    if (!conversation) return { error: { status: 404, error: 'Conversación no encontrada' } };
    if (conversation.buyer_id !== userId && conversation.seller_id !== userId) {
      return { error: { status: 403, error: 'No tienes acceso a esta conversación' } };
    }
    return { conversation };
  }

  if (!productId || !sellerId) {
    return { error: { status: 400, error: 'productId y sellerId son requeridos para iniciar una conversación' } };
  }
  if (userId === sellerId) {
    return { error: { status: 400, error: 'No puedes enviarte un mensaje a ti mismo' } };
  }

  let conversation = db.findConversation(productId, userId, sellerId);
  if (!conversation) {
    const convId = `conv_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    db.createConversation(convId, productId, userId, sellerId);
    conversation = db.getDb().prepare('SELECT * FROM conversations WHERE id = ?').get(convId);
  }
  return { conversation };
}

/** Valida el mensaje citado de una respuesta.
 *
 *  Retorna un string con el error, o null si todo bien (incluido el caso
 *  normal de que no haya cita).
 *
 *  Se exige que el citado sea de la MISMA conversación: sin eso, un cliente
 *  podría citar el id de un mensaje de un chat ajeno y la burbuja mostraría
 *  su texto al otro usuario, filtrando una conversación privada. */
function validarCita(replyToMessageId, conversationId) {
  if (!replyToMessageId) return null;
  if (typeof replyToMessageId !== 'string') {
    return 'replyToMessageId inválido';
  }
  if (!db.messageBelongsToConversation(replyToMessageId, conversationId)) {
    return 'El mensaje citado no existe en esta conversación';
  }
  return null;
}

/** Notifica al otro usuario de la conversación (push + notificación in-app + socket). */
function notifyNewMessage(app, conversation, senderId, previewText) {
  const otherUserId = conversation.buyer_id === senderId ? conversation.seller_id : conversation.buyer_id;
  const sender = db.getDb().prepare('SELECT name FROM sellers WHERE id = ?').get(senderId);
  const notifId = `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
  const isFirst = db.getDb().prepare(
    'SELECT COUNT(*) as c FROM messages WHERE conversation_id = ?'
  ).get(conversation.id);
  const type = isFirst && isFirst.c <= 1 ? 'new_chat' : 'new_message';

  db.createNotification(
    notifId,
    otherUserId,
    type,
    'Nuevo mensaje',
    `${sender?.name || 'Alguien'} te escribió: "${previewText}"`,
    { conversationId: conversation.id, productId: conversation.product_id, senderId }
  );

  const senderName = sender?.name || 'Alguien';
  sendPush(
    [otherUserId],
    type === 'new_chat' ? 'Nuevo chat' : 'Nuevo mensaje',
    `${senderName}: ${previewText}`,
    { conversationId: conversation.id, productId: conversation.product_id, type }
  );

  const messages = db.getMessages(conversation.id);
  const io = app.get('io');
  if (io) {
    const newMsg = messages[messages.length - 1];
    io.to(`conv:${conversation.id}`).emit('new:message', {
      message: {
        id: newMsg.id,
        conversationId: newMsg.conversationId,
        senderId: newMsg.senderId,
        text: newMsg.text,
        imageUrl: newMsg.imageUrl,
        createdAt: newMsg.createdAt,
        read: false,
        // La cita viaja resuelta en el evento y no solo como id: si el otro
        // usuario tuviera que recargar el chat para ver a qué se respondió,
        // la respuesta en tiempo real llegaría coja.
        replyToMessageId: newMsg.replyToMessageId,
        replyTo: newMsg.replyTo,
      },
      conversationId: conversation.id,
    });
    io.to(`user:${otherUserId}`).emit('conversation:updated', {
      conversationId: conversation.id,
    });
  }

  return messages;
}

function register(app) {
  // GET /api/chat/conversations - listar conversaciones de un usuario (anónimo o no)
  app.get('/api/chat/conversations', requireAuth, (req, res) => {
    // La bandeja es la del token, punto. Antes el `userId` venía en la query,
    // así que pedir la de cualquier otra persona era cambiar un parámetro.
    const userId = req.user.id;
    const conversations = db.getConversationsForUser(userId);
    const unreadCount = db.getUnreadMessageCount(userId);

    // Adjuntar datos del producto y del otro usuario
    const enriched = conversations.map(conv => {
      const product = db.getProductById(conv.productId);
      const wantedPost = conv.productId ? null : db.getWantedPostById(conv.wantedPostId);
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
        wantedPost: wantedPost ? { id: wantedPost.id, title: wantedPost.title } : null,
        otherUser: otherUser ? {
          id: otherUser.id,
          name: otherUser.name,
          avatarInitials: otherUser.avatarInitials || '',
          logoUrl: otherUser.logoUrl || null,
          // Mismo par de campos que sirve `rowToSeller`, para que el chat
          // pueda mostrar el subtítulo de rol sin una llamada extra a
          // /api/sellers/:id. Hoy la UI del chat aún no lo pinta.
          carrera: otherUser.carrera || null,
          tipoVerificacion: otherUser.tipo_verificacion || null,
          // Presencia ya filtrada por privacidad: quien no tiene permiso
          // recibe exactamente lo mismo que si el otro estuviera offline.
          // El "visor" es el dueño del inbox que se está leyendo, así que
          // esto no concede nada que el endpoint no diera ya.
          ...presenciaDe(req, userId, otherUser.id),
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
    const userId = req.user.id;
    const conv = db.getDb().prepare('SELECT * FROM conversations WHERE id = ?').get(req.params.id);
    if (!conv) return res.status(404).json({ error: 'Conversación no encontrada' });

    // Este era el agujero más directo de todos: la comprobación de
    // pertenencia existía, pero solo decidía si marcar como leído — los
    // mensajes se devolvían igual a quien preguntara. Con los ids de
    // conversación siendo `conv_<timestamp>_<6 chars>`, enumerar y leer
    // conversaciones ajenas era cuestión de un bucle (hallazgo C-01).
    if (conv.buyer_id !== userId && conv.seller_id !== userId) {
      return res.status(403).json({ error: 'No tienes acceso a esta conversación' });
    }

    const messages = db.getMessages(req.params.id);
    db.markConversationMessagesRead(req.params.id, userId);

    res.json({ messages });
  });

  // POST /api/chat/send - enviar un mensaje de texto (anónimo, no requiere auth)
  app.post('/api/chat/send', requireAuth, (req, res) => {
    const { productId, sellerId, text, conversationId, replyToMessageId } = req.body;
    // `senderId` ya no se lee del cuerpo: era lo que permitía enviar mensajes
    // firmados con el nombre de otra persona.
    const userId = req.user.id;

    if (!text || !text.trim()) {
      return res.status(400).json({ error: 'El mensaje no puede estar vacío' });
    }

    const { conversation, error } = resolveConversation({ conversationId, productId, sellerId, userId });
    if (error) return res.status(error.status).json({ error: error.error });

    const replyError = validarCita(replyToMessageId, conversation.id);
    if (replyError) return res.status(400).json({ error: replyError });

    const trimmedText = text.trim();
    const msgId = `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    db.createMessage(msgId, conversation.id, userId, trimmedText, null, replyToMessageId || null);

    const messages = notifyNewMessage(app, conversation, userId, trimmedText.slice(0, 100));
    res.status(201).json({ messages, conversationId: conversation.id });
  });

  // POST /api/chat/send-image - enviar un mensaje con una imagen (multipart).
  // La imagen se convierte a WebP antes de guardarse para que pese menos,
  // igual que se hace con las fotos de producto y el logo de negocio.
  app.post('/api/chat/send-image', requireAuth, (req, res) => {
    upload.single('image')(req, res, async (err) => {
      if (err) {
        return res.status(400).json({ error: 'Error al procesar la imagen: ' + err.message });
      }
      if (!req.file) {
        return res.status(400).json({ error: 'No se envió ninguna imagen' });
      }

      const { productId, sellerId, conversationId, replyToMessageId } = req.body;
      const userId = req.user.id;

      const { conversation, error } = resolveConversation({ conversationId, productId, sellerId, userId });
      if (error) {
        fs.unlink(req.file.path, () => {});
        return res.status(error.status).json({ error: error.error });
      }

      const replyError = validarCita(replyToMessageId, conversation.id);
      if (replyError) {
        fs.unlink(req.file.path, () => {});
        return res.status(400).json({ error: replyError });
      }

      let imageUrl;
      try {
        imageUrl = await convertToWebp(req.file.path);
      } catch (convErr) {
        console.error('Error convirtiendo imagen de chat a WebP:', convErr);
        // Fallback: usar el archivo original (sí existe en disco)
        imageUrl = '/uploads/' + path.basename(req.file.path);
      }

      const msgId = `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      db.createMessage(msgId, conversation.id, userId, '', imageUrl, replyToMessageId || null);

      const messages = notifyNewMessage(app, conversation, userId, '📷 Foto');
      res.status(201).json({ messages, conversationId: conversation.id });
    });
  });

  // DELETE /api/chat/messages/:id - eliminar un mensaje propio (el senderId debe coincidir)
  app.delete('/api/chat/messages/:id', requireAuth, (req, res) => {
    // `db.deleteMessage` ya exigía que el mensaje fuera del `senderId` que se
    // le pasara; el problema era que ese senderId lo elegía quien llamaba, así
    // que la comprobación se cumplía siempre. Ahora es el del token.
    const senderId = req.user.id;
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
