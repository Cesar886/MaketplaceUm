const db = require('../database');
const { requireAuth } = require('../auth');
const { sendPush } = require('../push');

function register(app) {
  // GET /api/notifications - obtener notificaciones del usuario autenticado
  app.get('/api/notifications', requireAuth, (req, res) => {
    const notifications = db.getNotifications(req.user.id);
    const unreadCount = db.getUnreadNotificationCount(req.user.id);
    res.json({ notifications, unreadCount });
  });

  // PATCH /api/notifications/:id/read - marcar una notificación como leída
  app.patch('/api/notifications/:id/read', requireAuth, (req, res) => {
    db.markNotificationRead(req.params.id);
    res.json({ success: true });
  });

  // PATCH /api/notifications/read-all - marcar todas como leídas
  app.patch('/api/notifications/read-all', requireAuth, (req, res) => {
    db.markAllNotificationsRead(req.user.id);
    res.json({ success: true });
  });

  // PATCH /api/notifications/read-by-conversation - marcar como leídas las de
  // un chat. Lo llama la app al abrir la conversación: los mensajes ya se
  // marcan leídos solos al pedirlos, pero las notificaciones in-app que
  // alimentan el badge de la campana no, y el contador se quedaba inflado.
  app.patch('/api/notifications/read-by-conversation', requireAuth, (req, res) => {
    const { conversationId } = req.body;
    if (!conversationId) {
      return res.status(400).json({ error: 'conversationId es requerido' });
    }
    const marcadas = db.markNotificationsReadForConversation(req.user.id, conversationId);
    res.json({
      success: true,
      marcadas,
      unreadCount: db.getUnreadNotificationCount(req.user.id),
    });
  });

  // GET /api/notifications/unread-count - obtener solo el conteo
  app.get('/api/notifications/unread-count', requireAuth, (req, res) => {
    const count = db.getUnreadNotificationCount(req.user.id);
    res.json({ count });
  });

  // ─── Category Interests ────────────────────────────────────

  // GET /api/notifications/interests - obtener categorías seguidas
  app.get('/api/notifications/interests', requireAuth, (req, res) => {
    const interests = db.getCategoryInterests(req.user.id);
    res.json({ interests });
  });

  // POST /api/notifications/interests - seguir una categoría
  app.post('/api/notifications/interests', requireAuth, (req, res) => {
    const { categoryId } = req.body;
    if (!categoryId) return res.status(400).json({ error: 'categoryId es requerido' });
    db.addCategoryInterest(req.user.id, categoryId);
    const interests = db.getCategoryInterests(req.user.id);
    res.json({ interests });
  });

  // DELETE /api/notifications/interests/:categoryId - dejar de seguir
  app.delete('/api/notifications/interests/:categoryId', requireAuth, (req, res) => {
    db.removeCategoryInterest(req.user.id, req.params.categoryId);
    const interests = db.getCategoryInterests(req.user.id);
    res.json({ interests });
  });

  // ─── Push Tokens (FCM) ───────────────────────────────────────────

  // POST /api/notifications/register-push - registrar un FCM device token
  app.post('/api/notifications/register-push', requireAuth, (req, res) => {
    const { playerId } = req.body;
    if (!playerId) return res.status(400).json({ error: 'playerId es requerido' });
    db.registerPushToken(req.user.id, playerId, req.body.platform || 'unknown');
    res.json({ success: true });
  });

  // DELETE /api/notifications/register-push - desregistrar un FCM device token
  app.delete('/api/notifications/register-push', requireAuth, (req, res) => {
    const { playerId } = req.body;
    if (!playerId) return res.status(400).json({ error: 'playerId es requerido' });
    db.unregisterPushToken(req.user.id, playerId);
    res.json({ success: true });
  });

  // DELETE /api/notifications/register-push/all - desregistrar todos los tokens del usuario
  app.delete('/api/notifications/register-push/all', requireAuth, (req, res) => {
    db.unregisterAllPushTokensForUser(req.user.id);
    res.json({ success: true });
  });

  // POST /api/notifications/register-push-anon - FCM token para usuarios anónimos (sin auth)
  // El userId debe tener el prefijo 'anon_' (formato generado por AnonymousId en Flutter)
  // y NO puede coincidir con un usuario autenticado, para evitar hijacking de notificaciones.
  app.post('/api/notifications/register-push-anon', (req, res) => {
    const { playerId, userId, platform } = req.body;
    if (!playerId || !userId) {
      return res.status(400).json({ error: 'playerId y userId son requeridos' });
    }

    // Solo se aceptan IDs anónimos (prefijo 'anon_')
    if (!userId.startsWith('anon_')) {
      return res.status(400).json({ error: 'userId inválido para registro anónimo' });
    }

    // Rechazar si el ID corresponde a un usuario autenticado en la base de datos
    const existingSeller = db.getDb().prepare('SELECT id FROM sellers WHERE id = ?').get(userId);
    if (existingSeller) {
      return res.status(403).json({ error: 'userId no permitido' });
    }

    db.registerPushToken(userId, playerId, platform || 'android');
    res.json({ success: true });
  });
}

module.exports = { register };
