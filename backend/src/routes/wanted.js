const db = require('../database');
const { sellers, categories } = require('../data');
const { sendPush } = require('../push');
const { requireAuth } = require('../auth');
const { validateLocation, validatePaymentMethods } = require('../validation/sellerProfile');

const VALID_TYPES = ['producto', 'servicio'];
const DAILY_LIMIT = 3;

/**
 * Junta sellerObj/categoryObj a una publicación "se busca", con el mismo
 * patrón que attachRelations en products.js, para que el detalle de
 * "se busca" traiga los mismos datos del publicante/categoría que ya trae
 * el detalle de producto (nombre, avatar, rating, ícono/color de categoría)
 * en vez de solo un userId/categoryId crudo.
 */
function attachWantedRelations(post) {
  if (!post) return post;
  return {
    ...post,
    postType: 'se_busca',
    sellerObj: sellers.find(s => s.id === post.userId) || {
      id: post.userId,
      name: post.sellerName || 'Usuario',
      avatarInitials: post.userId.slice(0, 2).toUpperCase(),
      major: '',
      isBusiness: false,
      logoUrl: null,
      rating: 0,
      reviews: 0,
      verified: false,
    },
    categoryObj: categories.find(c => c.id === post.categoryId) || null,
  };
}

/**
 * Valida los campos de contenido de una publicación "se busca". Se usa
 * tanto en la creación (POST) como en la edición (PUT) para no duplicar
 * las reglas. Devuelve { error } si algo es inválido, o los valores
 * normalizados listos para persistir.
 */
function validateWantedFields({ title, categoryId, type, priceMin, priceMax }) {
  if (!title || !title.trim()) return { error: 'title es requerido' };
  if (!categoryId) return { error: 'categoryId es requerido' };
  if (!VALID_TYPES.includes(type)) {
    return { error: `type debe ser uno de: ${VALID_TYPES.join(', ')}` };
  }

  const parsedPriceMin = priceMin !== undefined && priceMin !== null ? Number(priceMin) : null;
  const parsedPriceMax = priceMax !== undefined && priceMax !== null ? Number(priceMax) : null;
  if (parsedPriceMin !== null && Number.isNaN(parsedPriceMin)) {
    return { error: 'priceMin debe ser un número válido' };
  }
  if (parsedPriceMax !== null && Number.isNaN(parsedPriceMax)) {
    return { error: 'priceMax debe ser un número válido' };
  }

  return { title: title.trim(), categoryId, type, priceMin: parsedPriceMin, priceMax: parsedPriceMax };
}

function register(app) {
  // POST /api/wanted - crear una publicación "Se busca"
  // Requiere autenticación: el autor se obtiene del JWT, no del body, para
  // que publicar "se busca" exija cuenta igual que publicar un producto
  // (POST /api/products) y nadie pueda spoofear la autoría con otro userId.
  app.post('/api/wanted', requireAuth, (req, res) => {
    const { description } = req.body;
    const userId = req.user.id;

    const validated = validateWantedFields(req.body);
    if (validated.error) return res.status(400).json({ error: validated.error });
    const { title, categoryId, type, priceMin: parsedPriceMin, priceMax: parsedPriceMax } = validated;

    // Ubicación puntual de la búsqueda (Nivel 2): solo cuentas de negocio.
    const sellerRecord = sellers.find(s => s.id === userId);
    let postLocation = null;
    if (sellerRecord?.isBusiness) {
      const locationResult = validateLocation(req.body?.locationLat, req.body?.locationLng);
      if (locationResult.error) return res.status(400).json({ error: locationResult.error });
      postLocation = locationResult.value;
    }

    // Métodos de pago de esta publicación (opcional): si no se manda,
    // queda null y el cliente usa los del perfil del publicante.
    const paymentMethodsResult = validatePaymentMethods(req.body?.paymentMethods);
    if (paymentMethodsResult.error) return res.status(400).json({ error: paymentMethodsResult.error });

    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().replace('T', ' ').slice(0, 19);
    const countToday = db.countWantedPostsSince(userId, since);
    if (countToday >= DAILY_LIMIT) {
      return res.status(429).json({ error: `Ya publicaste el máximo de ${DAILY_LIMIT} búsquedas hoy` });
    }

    const id = `wanted_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const post = db.createWantedPost({
      id,
      userId,
      title,
      description: description || null,
      categoryId,
      type,
      priceMin: parsedPriceMin,
      priceMax: parsedPriceMax,
      locationLat: postLocation ? postLocation.lat : null,
      locationLng: postLocation ? postLocation.lng : null,
      paymentMethods: paymentMethodsResult.value,
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

    res.status(201).json(attachWantedRelations(post));
  });

  // GET /api/wanted - feed de publicaciones
  app.get('/api/wanted', (req, res) => {
    const { category, status, type } = req.query;
    const posts = db.listWantedPosts({ categoryId: category, status, type });
    res.json(posts.map(attachWantedRelations));
  });

  // GET /api/wanted/:id - detalle
  app.get('/api/wanted/:id', (req, res) => {
    const post = db.getWantedPostById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Publicación no encontrada' });
    res.json(attachWantedRelations(post));
  });

  // POST /api/wanted/:id/view - registra una vista de detalle (mismo
  // criterio simple que POST /api/products/:id/view: no cuenta si quien
  // pide es el dueño, sin exigir JWT).
  app.post('/api/wanted/:id/view', (req, res) => {
    const post = db.getWantedPostById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Publicación no encontrada' });

    const userId = req.body?.userId;
    if (!userId || post.userId !== userId) {
      db.incrementWantedPostViews(post.id);
    }
    res.status(204).end();
  });

  // PUT /api/wanted/:id - editar una publicación "se busca" (solo el dueño)
  // A diferencia del resto de wanted.js, usa requireAuth (JWT real) en vez
  // de confiar en un userId de body, para que un no-dueño reciba 403 de
  // verdad y no pueda spoofear la autoría solo mandando otro userId.
  app.put('/api/wanted/:id', requireAuth, (req, res) => {
    const post = db.getWantedPostById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Publicación no encontrada' });
    if (post.userId !== req.user.id) {
      return res.status(403).json({ error: 'No tienes permiso para editar esta publicación' });
    }
    if (post.status === 'resuelta') {
      return res.status(400).json({ error: 'No se puede editar una búsqueda ya resuelta' });
    }

    const validated = validateWantedFields(req.body);
    if (validated.error) return res.status(400).json({ error: validated.error });

    const paymentMethodsResult = validatePaymentMethods(req.body?.paymentMethods);
    if (paymentMethodsResult.error) return res.status(400).json({ error: paymentMethodsResult.error });

    const updated = db.updateWantedPost(req.params.id, {
      title: validated.title,
      description: req.body.description || null,
      categoryId: validated.categoryId,
      type: validated.type,
      priceMin: validated.priceMin,
      priceMax: validated.priceMax,
      paymentMethods: paymentMethodsResult.value,
    });
    res.json(attachWantedRelations(updated));
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
    res.json(attachWantedRelations(db.resolveWantedPost(req.params.id, resolvedWithUserId)));
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
