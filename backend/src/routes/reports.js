const db = require('../database');
const {
  requireAuth
} = require('../auth');
const {
  createReportLimiter
} = require('../security');
const TARGET_TYPES = new Set(['user', 'product', 'wanted', 'chat']);
function safeText(value, max) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

/**
 * Resuelve la cuenta afectada usando exclusivamente datos de la base.
 *
 * `targetUserId` no se acepta del cliente: de hacerlo, un reporte sobre una
 * publicación podría señalar a una cuenta distinta de su autor y llevar al
 * administrador al expediente equivocado. Las consultas leen las tablas
 * crudas (sin exigir que la cuenta/publicación siga visible) para que una
 * baja o moderación ocurrida entre abrir el formulario y enviarlo no destruya
 * la evidencia del reporte.
 */
async function resolveTarget({ reporterId, targetType, targetId }) {
  const database = db.getDb();
  if (targetType === 'user') {
    const target = await database.prepare('SELECT id FROM sellers WHERE id = ?').get(targetId);
    return target ? { targetUserId: target.id } : null;
  }
  if (targetType === 'product') {
    const target = await database.prepare('SELECT seller FROM products WHERE id = ?').get(targetId);
    return target ? { targetUserId: target.seller || null } : null;
  }
  if (targetType === 'wanted') {
    const target = await database.prepare('SELECT user_id FROM wanted_posts WHERE id = ?').get(targetId);
    return target ? { targetUserId: target.user_id } : null;
  }
  if (targetType !== 'chat') return null;

  const conversation = await database.prepare(`
    SELECT buyer_id, seller_id FROM conversations WHERE id = ?
  `).get(targetId);
  if (!conversation) return null;
  if (conversation.buyer_id === reporterId) {
    return { targetUserId: conversation.seller_id };
  }
  if (conversation.seller_id === reporterId) {
    return { targetUserId: conversation.buyer_id };
  }
  return { forbidden: true };
}
function register(app) {
  // Una sesion de invitado es suficiente: cualquier persona puede reportar
  // sin crear una cuenta, pero el id anonimo firmado evita aceptar una
  // identidad inventada por el cliente y permite aplicar limites anti-spam.
  app.post('/api/reports', requireAuth, createReportLimiter(), async (req, res, next) => {
    const targetType = req.body?.targetType;
    const targetId = safeText(req.body?.targetId, 180);
    const reason = safeText(req.body?.reason, 120);
    const details = safeText(req.body?.details, 1000);
    if (!TARGET_TYPES.has(targetType) || !targetId || reason.length < 3) {
      return res.status(400).json({
        error: 'Reporte invalido.'
      });
    }
    try {
      const target = await resolveTarget({
        reporterId: req.user.id,
        targetType,
        targetId
      });
      // Inexistente y conversación ajena comparten respuesta para no convertir
      // este endpoint en un oráculo de ids de chats privados.
      if (!target || target.forbidden) {
        return res.status(404).json({
          error: 'Objetivo no disponible para reportar.'
        });
      }
      const report = await db.createReport({
        reporterId: req.user.id,
        targetType,
        targetId,
        targetUserId: target.targetUserId,
        reason,
        details
      });
      return res.status(201).json({
        report
      });
    } catch (error) {
      return next(error);
    }
  });
  app.get('/api/me/reports', requireAuth, async (req, res) => {
    if (req.user.anon) return res.json({
      reports: []
    });
    const rows = await db.getDb().prepare(`
      SELECT id, target_type, target_id, reason, details, status,
             created_at, updated_at, resolved_at
        FROM reports
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
