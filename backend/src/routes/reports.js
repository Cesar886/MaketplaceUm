const db = require('../database');
const {
  requireAuth
} = require('../auth');
const TARGET_TYPES = new Set(['user', 'product', 'wanted', 'chat']);
function safeText(value, max) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}
function register(app) {
  app.post('/api/reports', requireAuth, async (req, res) => {
    if (req.user.anon) {
      return res.status(403).json({
        error: 'Inicia sesion para reportar.'
      });
    }
    const targetType = req.body?.targetType;
    const targetId = safeText(req.body?.targetId, 180);
    const targetUserId = safeText(req.body?.targetUserId, 180) || null;
    const reason = safeText(req.body?.reason, 120);
    const details = safeText(req.body?.details, 1000);
    if (!TARGET_TYPES.has(targetType) || !targetId || reason.length < 3) {
      return res.status(400).json({
        error: 'Reporte invalido.'
      });
    }
    try {
      const report = await db.createReport({
        reporterId: req.user.id,
        targetType,
        targetId,
        targetUserId,
        reason,
        details
      });
      return res.status(201).json({
        report
      });
    } catch (error) {
      return res.status(400).json({
        error: error.message || 'Reporte invalido.'
      });
    }
  });
  app.get('/api/me/reports', requireAuth, async (req, res) => {
    if (req.user.anon) return res.json({
      reports: []
    });
    const rows = await db.getDb().prepare(`
      SELECT * FROM reports
       WHERE reporter_id = ?
       ORDER BY created_at DESC, id DESC
       LIMIT 50
    `).all(req.user.id);
    return res.json({
      reports: rows
    });
  });
}
module.exports = {
  register
};
