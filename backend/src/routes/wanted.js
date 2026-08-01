const db = require('../database');
const { sendPush } = require('../push');

const VALID_TYPES = ['producto', 'servicio'];
const DAILY_LIMIT = 3;

function register(app) {
  // POST /api/wanted - crear una publicación "Se busca"
  app.post('/api/wanted', (req, res) => {
    const { userId, title, description, categoryId, type, priceMin, priceMax } = req.body;

    if (!userId) return res.status(400).json({ error: 'userId es requerido' });
    if (!title || !title.trim()) return res.status(400).json({ error: 'title es requerido' });
    if (!categoryId) return res.status(400).json({ error: 'categoryId es requerido' });
    if (!VALID_TYPES.includes(type)) {
      return res.status(400).json({ error: `type debe ser uno de: ${VALID_TYPES.join(', ')}` });
    }

    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().replace('T', ' ').slice(0, 19);
    const countToday = db.countWantedPostsSince(userId, since);
    if (countToday >= DAILY_LIMIT) {
      return res.status(429).json({ error: `Ya publicaste el máximo de ${DAILY_LIMIT} búsquedas hoy` });
    }

    const id = `wanted_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const post = db.createWantedPost({
      id,
      userId,
      title: title.trim(),
      description: description || null,
      categoryId,
      type,
      priceMin: priceMin !== undefined ? Number(priceMin) : null,
      priceMax: priceMax !== undefined ? Number(priceMax) : null,
    });

    // Notificar a los interesados en esta categoría (mismo patrón que products.js)
    const interestedUsers = db.getUsersInterestedInCategory(categoryId).filter(u => u !== userId);
    if (interestedUsers.length > 0) {
      for (const targetUserId of interestedUsers) {
        const notifId = `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
        db.createNotification(
          notifId,
          targetUserId,
          'wanted_post',
          'Alguien busca algo en tu categoría',
          `${post.title}`,
          { wantedPostId: id, categoryId }
        );
      }
      sendPush(
        interestedUsers,
        'Se busca en tu categoría',
        post.title,
        { wantedPostId: id, categoryId, type: 'wanted_post' }
      );
    }

    res.status(201).json(post);
  });

  // GET /api/wanted - feed de publicaciones
  app.get('/api/wanted', (req, res) => {
    const { category, status, type } = req.query;
    const posts = db.listWantedPosts({ categoryId: category, status, type });
    res.json(posts);
  });

  // GET /api/wanted/:id - detalle
  app.get('/api/wanted/:id', (req, res) => {
    const post = db.getWantedPostById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Publicación no encontrada' });
    res.json(post);
  });

  // PATCH /api/wanted/:id/resolve - marcar como resuelta (solo el dueño)
  app.patch('/api/wanted/:id/resolve', (req, res) => {
    const { userId, resolvedWithUserId } = req.body;
    const post = db.getWantedPostById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Publicación no encontrada' });
    if (post.userId !== userId) {
      return res.status(403).json({ error: 'No tienes permiso para resolver esta publicación' });
    }
    if (post.status === 'resuelta') {
      return res.status(400).json({ error: 'Esta búsqueda ya fue resuelta' });
    }
    res.json(db.resolveWantedPost(req.params.id, resolvedWithUserId));
  });

  // POST /api/wanted/:id/respond - abrir/reusar chat con el publicador
  app.post('/api/wanted/:id/respond', (req, res) => {
    const { userId } = req.body;
    if (!userId) return res.status(400).json({ error: 'userId es requerido' });

    const post = db.getWantedPostById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Publicación no encontrada' });
    if (post.status === 'resuelta') {
      return res.status(400).json({ error: 'Esta búsqueda ya fue resuelta' });
    }
    if (post.userId === userId) {
      return res.status(400).json({ error: 'No puedes responder tu propia búsqueda' });
    }

    let conversation = db.findWantedConversation(post.id, post.userId, userId);
    if (!conversation) {
      const convId = `conv_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      // buyer_id/seller_id son solo etiquetas de columna heredadas del chat de productos;
      // aquí buyer = quien publicó el "se busca", seller = quien responde.
      db.createWantedConversation(convId, post.id, post.userId, userId);
      conversation = db.getDb().prepare('SELECT * FROM conversations WHERE id = ?').get(convId);
    }

    res.json({ conversationId: conversation.id });
  });
}

module.exports = { register };
