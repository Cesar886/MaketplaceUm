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
}

module.exports = { register };
