const express = require('express');
const path = require('path');
const crypto = require('crypto');
const {
  registrarAuditoriaAdmin
} = require('../adminAudit');
const {
  createAdminBackup
} = require('../adminBackup');
const db = require('../database');
const {
  products,
  refrescarSellers
} = require('../data');
const {
  invalidateSellerSessions
} = require('../sellerAccess');
const {
  sendPush
} = require('../push');
const MAX_ID = 180;
const MAX_REASON = 500;
const MAX_SEARCH = 100;
const MAX_BULK = 100;
const MAX_REPORTER_MESSAGE = 1000;
const ACCOUNT_STATUSES = new Set(['active', 'suspended', 'banned']);
const MODERATION_STATUSES = new Set(['visible', 'removed', 'spam']);
const REPORT_STATUSES = new Set(['received', 'reviewing', 'resolved', 'dismissed']);
const CLOSED_REPORT_STATUSES = new Set(['resolved', 'dismissed']);
function validId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= MAX_ID && !/[\u0000-\u001f\u007f]/.test(value);
}
function reason(value) {
  const normalized = typeof value === 'string' ? value.trim() : '';
  return normalized.length >= 10 && normalized.length <= MAX_REASON ? normalized : null;
}
function queryText(value) {
  const normalized = typeof value === 'string' ? value.trim() : '';
  return normalized.length <= MAX_SEARCH ? normalized : null;
}
function pageParams(query) {
  const page = Number(query.page || 1);
  const limit = Number(query.limit || 25);
  if (!Number.isSafeInteger(page) || page < 1 || page > 100000 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
    return null;
  }
  return {
    page,
    limit,
    offset: (page - 1) * limit
  };
}
function escapeLike(value) {
  return value.replace(/[\\%_]/g, match => `\\${match}`);
}
async function normalizeExpiredSuspensions(database) {
  await database.prepare(`UPDATE sellers
    SET admin_status = 'active', admin_status_reason = NULL, admin_status_until = NULL
    WHERE admin_status = 'suspended' AND admin_status_until IS NOT NULL
      AND datetime(admin_status_until) <= datetime('now')`).run();
}
async function userRow(database, id) {
  return await database.prepare(`
    SELECT s.id, s.name, s.email, s.phone, s.tipo_cuenta AS accountType,
      s.tipo_verificacion AS verificationType, s.isBusiness AS isBusiness,
      s.verified, s.admin_status AS adminStatus,
      s.admin_status_reason AS adminStatusReason,
      s.admin_status_until AS adminStatusUntil,
      s.created_at AS createdAt, s.last_active AS lastActive,
      s.profile_views AS profileViews,
      (SELECT COUNT(*) FROM products p WHERE p.seller = s.id) AS productCount,
      (SELECT COUNT(*) FROM wanted_posts w WHERE w.user_id = s.id) AS wantedCount,
      (SELECT COUNT(*) FROM conversations c
        WHERE c.buyer_id = s.id OR c.seller_id = s.id) AS conversationCount
    FROM sellers s WHERE s.id = ?
  `).get(id);
}
function parseStatusPayload(body, {
  bulk = false
} = {}) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
  const allowed = new Set(bulk ? ['ids', 'status', 'reason', 'until'] : ['status', 'reason', 'until', 'expectedStatus']);
  if (Object.keys(body).some(key => !allowed.has(key))) return null;
  if (!ACCOUNT_STATUSES.has(body.status)) return null;
  const safeReason = reason(body.reason);
  if (!safeReason) return null;
  let until = null;
  if (body.status === 'suspended') {
    const parsed = typeof body.until === 'string' ? Date.parse(body.until) : NaN;
    const oneYear = Date.now() + 366 * 86400000;
    if (!Number.isFinite(parsed) || parsed <= Date.now() || parsed > oneYear) return null;
    until = new Date(parsed).toISOString();
  } else if (body.until !== null && body.until !== undefined && body.until !== '') {
    return null;
  }
  const expectedStatus = body.expectedStatus === undefined ? null : body.expectedStatus;
  if (expectedStatus !== null && !ACCOUNT_STATUSES.has(expectedStatus)) return null;
  return {
    status: body.status,
    reason: safeReason,
    until,
    expectedStatus
  };
}
function statusAction(status) {
  if (status === 'banned') return 'account.ban';
  if (status === 'suspended') return 'account.suspend';
  return 'account.reactivate';
}
function disconnectUser(req, userId) {
  const io = req.app.get('io');
  if (io?.in) io.in(`user:${userId}`).disconnectSockets(true);
}
function notificationId() {
  return `notif_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}
async function notifyModeration(userId, type, title, body, data) {
  if (!userId) return;
  const payload = {
    ...data,
    type
  };
  await db.createNotification(notificationId(), userId, type, title, body, payload);
  await sendPush([userId], title, body, payload);
}
async function notifyPublicationModerated(ownerId, kind, publication, status, moderationReason) {
  const label = kind === 'wanted' ? 'solicitud' : 'publicación';
  const title = status === 'spam' ? 'Tu publicación fue marcada como spam' : 'Tu publicación fue retirada';
  const body = `Tu ${label} "${publication.title}" ya no está visible. Motivo: ${moderationReason}`;
  await notifyModeration(ownerId, 'publication_moderated', title, body, {
    publicationKind: kind,
    publicationId: publication.id,
    moderationStatus: status,
    reason: moderationReason
  });
}

function parseReportUpdate(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
  const allowed = new Set(['status', 'reporterMessage', 'adminNote']);
  if (Object.keys(body).some(key => !allowed.has(key)) || !REPORT_STATUSES.has(body.status)) return null;

  if (body.reporterMessage !== undefined && typeof body.reporterMessage !== 'string') return null;
  if (body.adminNote !== undefined && typeof body.adminNote !== 'string') return null;
  const reporterMessage = (body.reporterMessage || '').trim();
  const adminNote = (body.adminNote || '').trim();
  if (reporterMessage.length > MAX_REPORTER_MESSAGE || adminNote.length > MAX_REASON * 2) return null;
  if (reporterMessage && !CLOSED_REPORT_STATUSES.has(body.status)) return null;
  if (/\u0000/.test(reporterMessage) || /\u0000/.test(adminNote)) return null;
  return {
    status: body.status,
    reporterMessage,
    adminNote
  };
}

async function configuredReportsAccount(database) {
  const email = String(process.env.REPORTS_ACCOUNT_EMAIL || '').trim().toLowerCase();
  if (!email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return null;
  const account = await database.prepare(`SELECT id, name, email, admin_status AS adminStatus
    FROM sellers WHERE lower(email) = lower(?)`).get(email);
  if (!account || account.adminStatus && account.adminStatus !== 'active') return null;
  return account;
}

/**
 * Crea una respuesta de chat usando únicamente la cuenta que el servidor
 * identifica por REPORTS_ACCOUNT_EMAIL. Ni el id del remitente ni el correo
 * se aceptan en el payload administrativo, para impedir suplantaciones.
 *
 * conversations/messages no tienen FK hacia sellers a propósito: el otro
 * participante puede ser una sesión invitada que conserva su id firmado.
 */
async function createOfficialReportMessage(database, report, account, text) {
  const messageId = `msg_report_${crypto.createHash('sha256').update(report.id).digest('hex').slice(0, 32)}`;
  const existingMessage = await database.prepare(`SELECT id, conversation_id, sender_id, text, created_at, read
    FROM messages WHERE id = ?`).get(messageId);
  if (existingMessage) {
    const existingConversation = await database.prepare('SELECT * FROM conversations WHERE id = ?').get(existingMessage.conversation_id);
    if (!existingConversation || existingMessage.sender_id !== account.id
        || ![existingConversation.buyer_id, existingConversation.seller_id].includes(report.reporter_id)) {
      throw new Error('El identificador de respuesta del reporte ya esta ocupado por otro mensaje.');
    }
    return {
      account,
      alreadySent: true,
      conversation: existingConversation,
      created: false,
      message: existingMessage,
      skipped: null
    };
  }

  if (account.id === report.reporter_id) {
    return {
      account,
      alreadySent: false,
      created: false,
      skipped: 'same_account'
    };
  }
  if (await db.areUsersBlocked(account.id, report.reporter_id)) {
    return {
      account,
      alreadySent: false,
      created: false,
      skipped: 'blocked'
    };
  }

  let conversation = await db.findDirectConversation(account.id, report.reporter_id);
  let firstMessage = false;
  if (!conversation) {
    const conversationId = `conv_${Date.now()}_${crypto.randomBytes(6).toString('hex')}`;
    // La cuenta oficial queda como seller para que el hilo tenga el mismo
    // sentido estable aunque quien reportó sea un invitado sin fila seller.
    await db.createDirectConversation(conversationId, report.reporter_id, account.id);
    conversation = await database.prepare('SELECT * FROM conversations WHERE id = ?').get(conversationId);
    firstMessage = true;
  } else {
    const count = await database.prepare('SELECT COUNT(*) AS total FROM messages WHERE conversation_id = ?').get(conversation.id);
    firstMessage = Number(count?.total || 0) === 0;
  }

  await db.createMessage(messageId, conversation.id, account.id, text);
  const message = await database.prepare(`SELECT id, conversation_id, sender_id, text, created_at, read
    FROM messages WHERE id = ?`).get(messageId);
  const type = firstMessage ? 'new_chat' : 'new_message';
  const title = firstMessage ? 'Nuevo chat' : 'Nuevo mensaje';
  const preview = text.length > 100 ? `${text.slice(0, 99)}…` : text;
  const body = `${account.name || 'Reportes'}: ${preview}`;
  const payload = {
    conversationId: conversation.id,
    productId: null,
    senderId: account.id,
    reportId: report.id,
    type
  };
  const muted = await db.isChatUserMuted(report.reporter_id, account.id);
  if (!muted) {
    await db.createNotification(notificationId(), report.reporter_id, type, title, body, payload);
  }
  return {
    account,
    alreadySent: false,
    body,
    conversation,
    created: true,
    message,
    muted,
    payload,
    skipped: null,
    title
  };
}

async function deliverOfficialReportMessage(app, report, delivery) {
  try {
    if (!delivery.muted) {
      await sendPush([report.reporter_id], delivery.title, delivery.body, delivery.payload);
    }
    const io = app.get('io');
    if (!io) return;
    io.to?.(`conv:${delivery.conversation.id}`).emit?.('new:message', {
      message: {
        id: delivery.message.id,
        conversationId: delivery.message.conversation_id,
        senderId: delivery.message.sender_id,
        text: delivery.message.text,
        imageUrl: null,
        createdAt: delivery.message.created_at,
        read: !!delivery.message.read,
        replyToMessageId: null,
        replyTo: null
      },
      conversationId: delivery.conversation.id
    });
    io.to?.(`user:${report.reporter_id}`).emit?.('conversation:updated', {
      conversationId: delivery.conversation.id
    });
  } catch (error) {
    // El mensaje ya quedó guardado de forma atómica con el cierre. Una falla
    // transitoria de push/socket no debe convertir una entrega persistida en
    // error ni provocar que el administrador reintente y duplique el chat.
    console.error('[reports] No se pudo emitir la respuesta ya guardada:', error.message);
  }
}
async function applyAccountStatus(database, req, id, parsed, createdAt) {
  const before = await userRow(database, id);
  if (!before) return {
    notFound: true
  };
  if (parsed.expectedStatus && before.adminStatus !== parsed.expectedStatus) {
    return {
      conflict: true,
      currentStatus: before.adminStatus
    };
  }
  if (before.adminStatus === parsed.status && (before.adminStatusUntil || null) === parsed.until) {
    return {
      unchanged: true,
      user: before
    };
  }
  await database.prepare(`UPDATE sellers SET admin_status = ?, admin_status_reason = ?,
    admin_status_until = ? WHERE id = ?`).run(parsed.status, parsed.status === 'active' ? null : parsed.reason, parsed.until, id);
  if (!(await invalidateSellerSessions(database, id))) throw new Error('No se pudo invalidar la sesion.');
  const after = await userRow(database, id);
  await registrarAuditoriaAdmin(database, req, {
    action: statusAction(parsed.status),
    entityType: 'account',
    entityId: id,
    details: {
      before: {
        status: before.adminStatus,
        until: before.adminStatusUntil
      },
      after: {
        status: after.adminStatus,
        until: after.adminStatusUntil
      },
      reason: parsed.reason
    },
    createdAt
  });
  return {
    user: after
  };
}
function router() {
  const api = express.Router();
  api.get('/dashboard', async (_req, res) => {
    const database = db.getDb();
    await normalizeExpiredSuspensions(database);
    const users = await database.prepare(`SELECT
      COUNT(*) AS total,
      SUM(CASE WHEN admin_status = 'active' THEN 1 ELSE 0 END) AS enabled,
      SUM(CASE WHEN admin_status = 'active'
        AND last_active >= datetime('now', '-7 days') THEN 1 ELSE 0 END) AS active7d,
      SUM(CASE WHEN admin_status = 'suspended' THEN 1 ELSE 0 END) AS suspended,
      SUM(CASE WHEN admin_status = 'banned' THEN 1 ELSE 0 END) AS banned
      FROM sellers`).get();
    const publications = await database.prepare(`SELECT
      (SELECT COUNT(*) FROM products WHERE created_at >= datetime('now', 'start of day'))
       + (SELECT COUNT(*) FROM wanted_posts WHERE created_at >= datetime('now', 'start of day')) AS today,
      (SELECT COUNT(*) FROM products WHERE created_at >= datetime('now', '-7 days'))
       + (SELECT COUNT(*) FROM wanted_posts WHERE created_at >= datetime('now', '-7 days')) AS week,
      (SELECT COUNT(*) FROM products WHERE created_at >= datetime('now', 'start of day')) AS productsToday,
      (SELECT COUNT(*) FROM wanted_posts WHERE created_at >= datetime('now', 'start of day')) AS wantedToday`).get();
    const pending = (await database.prepare("SELECT COUNT(*) AS total FROM verificaciones WHERE estado = 'pendiente'").get())?.total ?? 0;
    res.json({
      users: {
        ...users,
        activeDefinition: 'Actividad registrada en los últimos 7 días'
      },
      publications,
      pendingVerifications: pending
    });
  });
  api.get('/users', async (req, res) => {
    const pagination = pageParams(req.query);
    const search = queryText(req.query.q);
    const status = String(req.query.status || 'all');
    if (!pagination || search === null || status !== 'all' && !ACCOUNT_STATUSES.has(status)) {
      return res.status(400).json({
        error: 'Filtros de usuarios inválidos.'
      });
    }
    const database = db.getDb();
    await normalizeExpiredSuspensions(database);
    const where = [];
    const params = [];
    if (status !== 'all') {
      where.push('s.admin_status = ?');
      params.push(status);
    }
    if (search) {
      const like = `%${escapeLike(search)}%`;
      where.push(`(s.id LIKE ? ESCAPE '\\' OR s.name LIKE ? ESCAPE '\\'
        OR COALESCE(s.email, '') LIKE ? ESCAPE '\\')`);
      params.push(like, like, like);
    }
    const clause = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const total = (await database.prepare(`SELECT COUNT(*) AS total FROM sellers s ${clause}`).get(...params)).total;
    const users = await database.prepare(`SELECT s.id, s.name, s.email,
      s.tipo_cuenta AS accountType, s.tipo_verificacion AS verificationType,
      s.isBusiness AS isBusiness, s.verified,
      s.admin_status AS adminStatus, s.admin_status_until AS adminStatusUntil,
      s.created_at AS createdAt, s.last_active AS lastActive,
      (SELECT COUNT(*) FROM products p WHERE p.seller = s.id) AS productCount,
      (SELECT COUNT(*) FROM wanted_posts w WHERE w.user_id = s.id) AS wantedCount
      FROM sellers s ${clause}
      ORDER BY COALESCE(s.last_active, s.created_at) DESC, s.id DESC
      LIMIT ? OFFSET ?`).all(...params, pagination.limit, pagination.offset);
    return res.json({
      users,
      total,
      page: pagination.page,
      limit: pagination.limit
    });
  });
  api.get('/users/:id', async (req, res) => {
    if (!validId(req.params.id)) return res.status(400).json({
      error: 'Cuenta inválida.'
    });
    const database = db.getDb();
    await normalizeExpiredSuspensions(database);
    const user = await userRow(database, req.params.id);
    if (!user) return res.status(404).json({
      error: 'Cuenta no encontrada.'
    });
    const recentActivity = await database.prepare(`
      SELECT kind, id, title, "createdAt", status FROM (
        SELECT 'product' AS kind, id, title, created_at AS createdAt,
          moderation_status AS status FROM products WHERE seller = ?
        UNION ALL
        SELECT 'wanted' AS kind, id, title, created_at AS createdAt,
          moderation_status AS status FROM wanted_posts WHERE user_id = ?
      ) ORDER BY "createdAt" DESC LIMIT 20`).all(req.params.id, req.params.id);
    return res.json({
      user,
      recentActivity
    });
  });
  api.patch('/users/:id/status', async (req, res) => {
    if (!validId(req.params.id)) return res.status(400).json({
      error: 'Cuenta inválida.'
    });
    const parsed = parseStatusPayload(req.body);
    if (!parsed) return res.status(400).json({
      error: 'Estado, motivo o vigencia inválidos.'
    });
    const database = db.getDb();
    const createdAt = new Date().toISOString();
    const result = await database.transaction(async () => await applyAccountStatus(database, req, req.params.id, parsed, createdAt))();
    if (result.notFound) return res.status(404).json({
      error: 'Cuenta no encontrada.'
    });
    if (result.conflict) return res.status(409).json({
      error: 'La cuenta cambió desde que se abrió.',
      currentStatus: result.currentStatus
    });
    if (!result.unchanged) {
      disconnectUser(req, req.params.id);
      await refrescarSellers();
    }
    return res.json({
      user: result.user,
      unchanged: !!result.unchanged
    });
  });
  api.post('/users/bulk/status', async (req, res) => {
    const parsed = parseStatusPayload(req.body, {
      bulk: true
    });
    const ids = Array.isArray(req.body?.ids) ? [...new Set(req.body.ids)] : [];
    if (!parsed || parsed.status === 'active' || ids.length < 1 || ids.length > MAX_BULK || ids.some(id => !validId(id))) {
      return res.status(400).json({
        error: 'Operación masiva inválida (máximo 100 cuentas).'
      });
    }
    const database = db.getDb();
    const existing = (await database.prepare(`SELECT id FROM sellers WHERE id IN (${ids.map(() => '?').join(',')})`).all(...ids)).map(row => row.id);
    if (existing.length !== ids.length) {
      return res.status(404).json({
        error: 'Una o más cuentas no existen; no se hizo ningún cambio.'
      });
    }
    let backupPath;
    try {
      backupPath = await createAdminBackup(database, `accounts-${parsed.status}`);
    } catch (error) {
      console.error('[admin-backup] operación masiva abortada:', error.message);
      return res.status(503).json({
        error: 'No se pudo verificar el backup; no se hizo ningún cambio.'
      });
    }
    const createdAt = new Date().toISOString();
    await database.transaction(async () => {
      for (const id of ids) {
        const result = await applyAccountStatus(database, req, id, parsed, createdAt);
        if (!result.user && !result.unchanged) throw new Error('La cuenta cambió durante la operación.');
      }
    })();
    for (const id of ids) disconnectUser(req, id);
    await refrescarSellers();
    return res.json({
      updated: ids.length,
      backupCreated: true,
      backupId: path.basename(backupPath)
    });
  });
  api.post('/users/:id/reset-limits', async (req, res) => {
    if (!validId(req.params.id)) return res.status(400).json({
      error: 'Cuenta inválida.'
    });
    const scope = req.body?.scope;
    if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body) || Object.keys(req.body).some(key => key !== 'scope') || !['products', 'wanted', 'all'].includes(scope)) {
      return res.status(400).json({
        error: 'Scope inválido.'
      });
    }
    const database = db.getDb();
    if (!(await database.prepare('SELECT 1 FROM sellers WHERE id = ?').get(req.params.id))) {
      return res.status(404).json({
        error: 'Cuenta no encontrada.'
      });
    }
    const now = new Date().toISOString();
    const before = (await database.prepare('SELECT products_reset_at, wanted_reset_at FROM publication_limit_resets WHERE user_id = ?').get(req.params.id)) || null;
    await database.transaction(async () => {
      await database.prepare(`INSERT INTO publication_limit_resets (
        user_id, products_reset_at, wanted_reset_at, updated_by_admin_id, updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET
        products_reset_at = CASE WHEN excluded.products_reset_at IS NOT NULL
          THEN excluded.products_reset_at ELSE publication_limit_resets.products_reset_at END,
        wanted_reset_at = CASE WHEN excluded.wanted_reset_at IS NOT NULL
          THEN excluded.wanted_reset_at ELSE publication_limit_resets.wanted_reset_at END,
        updated_by_admin_id = excluded.updated_by_admin_id,
        updated_at = excluded.updated_at`).run(req.params.id, scope === 'products' || scope === 'all' ? now : null, scope === 'wanted' || scope === 'all' ? now : null, req.admin.id, now);
      const after = await database.prepare('SELECT products_reset_at, wanted_reset_at FROM publication_limit_resets WHERE user_id = ?').get(req.params.id);
      await registrarAuditoriaAdmin(database, req, {
        action: 'account.limits_reset',
        entityType: 'account',
        entityId: req.params.id,
        details: {
          scope,
          before,
          after
        },
        createdAt: now
      });
    })();
    return res.json({
      reset: true,
      scope,
      resetAt: now
    });
  });
  const publicationUnion = `
    SELECT 'product' AS kind, p.id, p.title, p.seller AS ownerId,
      COALESCE(s.name, p.seller) AS ownerName, p.created_at AS createdAt,
      p.moderation_status AS moderationStatus, p.status AS domainStatus,
      COALESCE(p.views, 0) AS views
    FROM products p LEFT JOIN sellers s ON s.id = p.seller
    UNION ALL
    SELECT 'wanted' AS kind, w.id, w.title, w.user_id AS ownerId,
      COALESCE(s.name, w.user_id) AS ownerName, w.created_at AS createdAt,
      w.moderation_status AS moderationStatus, w.status AS domainStatus,
      COALESCE(w.views, 0) AS views
    FROM wanted_posts w LEFT JOIN sellers s ON s.id = w.user_id`;
  api.get('/publications', async (req, res) => {
    const pagination = pageParams(req.query);
    const search = queryText(req.query.q);
    const kind = String(req.query.kind || 'all');
    const status = String(req.query.status || 'all');
    if (!pagination || search === null || !['all', 'product', 'wanted'].includes(kind) || status !== 'all' && !MODERATION_STATUSES.has(status)) {
      return res.status(400).json({
        error: 'Filtros de publicaciones inválidos.'
      });
    }
    const where = [];
    const params = [];
    if (kind !== 'all') {
      where.push('kind = ?');
      params.push(kind);
    }
    if (status !== 'all') {
      where.push('"moderationStatus" = ?');
      params.push(status);
    }
    if (search) {
      const like = `%${escapeLike(search)}%`;
      where.push(`(id LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\'
        OR "ownerName" LIKE ? ESCAPE '\\' OR "ownerId" LIKE ? ESCAPE '\\')`);
      params.push(like, like, like, like);
    }
    const clause = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const database = db.getDb();
    const total = (await database.prepare(`SELECT COUNT(*) AS total FROM (${publicationUnion}) ${clause}`).get(...params)).total;
    const publications = await database.prepare(`SELECT * FROM (${publicationUnion}) ${clause}
      ORDER BY "createdAt" DESC, id DESC LIMIT ? OFFSET ?`).all(...params, pagination.limit, pagination.offset);
    return res.json({
      publications,
      total,
      page: pagination.page,
      limit: pagination.limit
    });
  });
  async function moderatePublication(req, res, targetStatus) {
    const kind = req.params.kind;
    if (!['product', 'wanted'].includes(kind) || !validId(req.params.id)) {
      return res.status(400).json({
        error: 'Publicación inválida.'
      });
    }
    const body = req.body;
    const safeReason = reason(body?.reason);
    if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some(key => !['reason', 'expectedStatus'].includes(key)) || !safeReason || body.expectedStatus !== undefined && !MODERATION_STATUSES.has(body.expectedStatus)) {
      return res.status(400).json({
        error: 'Motivo o estado esperado inválido.'
      });
    }
    const table = kind === 'product' ? 'products' : 'wanted_posts';
    const database = db.getDb();
    const ownerColumn = kind === 'product' ? 'seller' : 'user_id';
    const before = await database.prepare(`SELECT id, title, ${ownerColumn} AS ownerId,
      moderation_status AS status
      FROM ${table} WHERE id = ?`).get(req.params.id);
    if (!before) return res.status(404).json({
      error: 'Publicación no encontrada.'
    });
    if (body.expectedStatus && before.status !== body.expectedStatus) {
      return res.status(409).json({
        error: 'La publicación cambió desde que se abrió.',
        currentStatus: before.status
      });
    }
    if (before.status === targetStatus) {
      return res.json({
        id: before.id,
        moderationStatus: before.status,
        unchanged: true
      });
    }
    const now = new Date().toISOString();
    await database.transaction(async () => {
      await database.prepare(`UPDATE ${table} SET moderation_status = ?, moderation_reason = ?,
        moderated_at = ?, moderated_by_admin_id = ? WHERE id = ?`).run(targetStatus, safeReason, now, req.admin.id, req.params.id);
      await registrarAuditoriaAdmin(database, req, {
        action: targetStatus === 'spam' ? 'publication.spam' : 'publication.delete',
        entityType: kind,
        entityId: req.params.id,
        details: {
          title: before.title,
          before: before.status,
          after: targetStatus,
          reason: safeReason
        },
        createdAt: now
      });
      await notifyPublicationModerated(before.ownerId, kind, before, targetStatus, safeReason);
    })();
    if (kind === 'product') {
      const index = products.findIndex(product => product.id === req.params.id);
      if (index !== -1) products.splice(index, 1);
    }
    return res.json({
      id: before.id,
      moderationStatus: targetStatus,
      unchanged: false
    });
  }
  api.delete('/publications/:kind/:id', async (req, res) => await moderatePublication(req, res, 'removed'));
  api.patch('/publications/:kind/:id/spam', async (req, res) => await moderatePublication(req, res, 'spam'));
  api.get('/audit-log', async (req, res) => {
    const pagination = pageParams(req.query);
    const action = queryText(req.query.action);
    const entityType = queryText(req.query.entityType);
    if (!pagination || action === null || entityType === null) {
      return res.status(400).json({
        error: 'Filtros de auditoría inválidos.'
      });
    }
    const where = [];
    const params = [];
    if (action) {
      where.push('l.action = ?');
      params.push(action);
    }
    if (entityType) {
      where.push('l.entity_type = ?');
      params.push(entityType);
    }
    const clause = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const database = db.getDb();
    const total = (await database.prepare(`SELECT COUNT(*) AS total FROM admin_audit_log l ${clause}`).get(...params)).total;
    const entries = (await database.prepare(`SELECT l.id, l.action,
      l.entity_type AS entityType, l.entity_id AS entityId,
      l.details_json AS detailsJson, l.created_at AS createdAt,
      a.username AS adminUsername
      FROM admin_audit_log l JOIN admins a ON a.id = l.admin_id
      ${clause} ORDER BY l.created_at DESC, l.id DESC LIMIT ? OFFSET ?`).all(...params, pagination.limit, pagination.offset)).map(entry => {
      let details = {};
      try {
        details = JSON.parse(entry.detailsJson);
      } catch {}
      const {
        detailsJson,
        ...safe
      } = entry;
      return {
        ...safe,
        details
      };
    });
    return res.json({
      entries,
      total,
      page: pagination.page,
      limit: pagination.limit
    });
  });
  api.get('/reports', async (req, res) => {
    const pagination = pageParams(req.query);
    const status = String(req.query.status || 'all');
    const targetType = String(req.query.targetType || 'all');
    if (!pagination) return res.status(400).json({
      error: 'Paginacion invalida.'
    });
    const result = await db.listReports({
      status,
      targetType,
      limit: pagination.limit,
      offset: pagination.offset
    });
    if (!result) return res.status(400).json({
      error: 'Filtros de reportes invalidos.'
    });
    return res.json({
      ...result,
      page: pagination.page,
      limit: pagination.limit
    });
  });
  api.get('/reports/:id', async (req, res) => {
    if (!validId(req.params.id)) return res.status(400).json({
      error: 'Reporte invalido.'
    });
    const report = await db.getReportById(req.params.id);
    if (!report) return res.status(404).json({
      error: 'Reporte no encontrado.'
    });
    return res.json({ report });
  });
  api.patch('/reports/:id', async (req, res) => {
    if (!validId(req.params.id)) return res.status(400).json({
      error: 'Reporte invalido.'
    });
    const parsed = parseReportUpdate(req.body);
    if (!parsed) {
      return res.status(400).json({
        error: 'Estado o mensaje invalidos.'
      });
    }

    const database = db.getDb();
    const current = await db.getReportById(req.params.id);
    if (!current) return res.status(404).json({
      error: 'Reporte no encontrado.'
    });

    let account = null;
    if (parsed.reporterMessage) {
      account = await configuredReportsAccount(database);
      if (!account) return res.status(503).json({
        error: 'La cuenta oficial de Reportes no esta configurada o no esta activa.'
      });
    }

    let result;
    let delivery = null;
    await database.transaction(async () => {
      result = await db.updateReportStatus({
        id: req.params.id,
        status: parsed.status,
        adminNote: parsed.adminNote,
        adminId: req.admin.id
      });
      if (!result) throw new Error('El reporte dejo de existir durante la operacion.');
      if (parsed.reporterMessage) {
        delivery = await createOfficialReportMessage(database, result.after, account, parsed.reporterMessage);
      }
      await registrarAuditoriaAdmin(database, req, {
        action: 'report.update',
        entityType: 'report',
        entityId: req.params.id,
        details: {
          before: result.before.status,
          after: result.after.status,
          targetType: result.after.target_type,
          targetId: result.after.target_id,
          reporterNotified: Boolean(delivery?.created || delivery?.alreadySent),
          reporterMessageCreated: Boolean(delivery?.created),
          notificationChannel: delivery?.created || delivery?.alreadySent ? 'chat' : null,
          notificationSkipped: delivery?.skipped || null
        },
        createdAt: new Date().toISOString()
      });
    })();
    if (delivery?.created) await deliverOfficialReportMessage(req.app, result.after, delivery);
    const reporterMessageSent = Boolean(delivery?.created || delivery?.alreadySent);
    const reporterMessageSkipped = delivery?.skipped || null;
    return res.json({
      report: result.after,
      reporterMessageSent,
      reporterMessageAlreadySent: Boolean(delivery?.alreadySent),
      reporterMessageSkipped,
      ...(reporterMessageSkipped ? {
        warning: reporterMessageSkipped === 'blocked'
          ? 'El reporte se cerro, pero no se envio el mensaje porque existe un bloqueo entre las cuentas.'
          : 'El reporte se cerro, pero la cuenta oficial no puede enviarse un mensaje a si misma.'
      } : {})
    });
  });
  return api;
}
module.exports = {
  router
};
