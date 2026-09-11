const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-reports-privacy-'));
process.env.MERCADITO_DB_PATH = path.join(tempDir, 'test.db');
process.env.JWT_SECRET = 'seller-secret-reports-privacy-123456789012345';
process.env.ADMIN_JWT_SECRET = 'admin-secret-reports-privacy-123456789012345';
process.env.ADMIN_TOTP_ENCRYPTION_KEY = 'totp-secret-reports-privacy-123456789012345';
process.env.REPORTS_ACCOUNT_EMAIL = 'reportes-oficial@example.com';

const express = require('express');
const db = require('../database');
const { encryptTotpSecret, issueAdminToken } = require('../adminAuth');
const { generateAnonToken, generateToken, generateSession } = require('../auth');
const reportsRoute = require('./reports');
const privacyRoute = require('./privacy');
const { router: adminRouter } = require('./admin');

db.initDatabase();
const database = db.getDb();
const adminId = Number(database.prepare(`INSERT INTO admins
  (username, password_hash, totp_secret_encrypted) VALUES (?, ?, ?)`)
  .run('reportadmin', 'unused', encryptTotpSecret('JBSWY3DPEHPK3PXP')).lastInsertRowid);
const reportsAccountId = 'rp_reports_official';
database.prepare(`INSERT INTO sellers
  (id, name, email, phone, avatarInitials, tipo_cuenta, verified, last_active)
  VALUES (?, 'Reportes Mercadito UM', ?, '8180000000', 'RM', 'negocio', 1, datetime('now'))`)
  .run(reportsAccountId, process.env.REPORTS_ACCOUNT_EMAIL);

let sequence = 0;
let server;
let baseUrl;

test.before(async () => {
  const app = express();
  app.use(express.json());
  app.set('io', { in: () => ({ disconnectSockets() {} }) });
  reportsRoute.register(app);
  privacyRoute.register(app);
  app.use('/api/admin', adminRouter());
  app.use((error, _req, res, _next) => res.status(500).json({ error: error.message }));
  server = http.createServer(app);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(async () => {
  await new Promise(resolve => server.close(resolve));
  database.close();
  fs.rmSync(tempDir, { recursive: true, force: true });
});

function seller() {
  const id = `rp_user_${++sequence}`;
  database.prepare(`INSERT INTO sellers
    (id, name, email, phone, avatarInitials, tipo_cuenta, verified, last_active)
    VALUES (?, ?, ?, ?, 'RP', 'estudiante', 1, datetime('now'))`)
    .run(id, `Reportes ${sequence}`, `${id}@example.com`, '8180000000');
  return { id, token: generateToken(id) };
}

function product(ownerId) {
  const id = `rp_product_${++sequence}`;
  database.prepare(`INSERT INTO products (id, title, seller)
    VALUES (?, 'Producto reportable', ?)`).run(id, ownerId);
  return id;
}

function wanted(ownerId) {
  const id = `rp_wanted_${++sequence}`;
  database.prepare(`INSERT INTO wanted_posts
    (id, user_id, title, category_id, type)
    VALUES (?, ?, 'Búsqueda reportable', 'otros', 'producto')`).run(id, ownerId);
  return id;
}

async function createReport(reporter, body) {
  return jsonRequest('/api/reports', {
    method: 'POST',
    headers: userHeaders(reporter),
    body,
  });
}

function adminHeaders() {
  return {
    Authorization: `Bearer ${issueAdminToken({ id: adminId, username: 'reportadmin', token_version: 0 })}`,
    'Content-Type': 'application/json',
  };
}

function userHeaders(user) {
  return { Authorization: `Bearer ${user.token}`, 'Content-Type': 'application/json' };
}

async function jsonRequest(route, { method = 'GET', headers, body } = {}) {
  const res = await fetch(baseUrl + route, {
    method,
    headers: headers || { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, body: await res.json().catch(() => null) };
}

test('admin puede resolver sin explicacion y no se envia mensaje ni notificacion', async () => {
  const reporter = seller();
  const target = seller();

  const created = await jsonRequest('/api/reports', {
    method: 'POST',
    headers: userHeaders(reporter),
    body: {
      targetType: 'user',
      targetId: target.id,
      targetUserId: reporter.id,
      reason: 'Actividad sospechosa',
      details: 'Pidio deposito fuera de la app.',
    },
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  assert.equal(created.body.report.status, 'received');
  assert.equal(created.body.report.reporter_id, reporter.id);
  assert.equal(created.body.report.target_user_id, target.id);

  const listed = await jsonRequest('/api/admin/reports?status=received&targetType=user', {
    headers: adminHeaders(),
  });
  assert.equal(listed.status, 200, JSON.stringify(listed.body));
  assert.equal(listed.body.total, 1);

  const updated = await jsonRequest(`/api/admin/reports/${created.body.report.id}`, {
    method: 'PATCH',
    headers: adminHeaders(),
    body: { status: 'resolved', adminNote: 'Se contacto al usuario reportado.' },
  });
  assert.equal(updated.status, 200, JSON.stringify(updated.body));
  assert.equal(updated.body.report.status, 'resolved');
  assert.equal(updated.body.reporterMessageSent, false);
  assert.ok(updated.body.report.resolved_at);

  const notif = database.prepare(
    'SELECT type, title, body, data FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 1',
  ).get(reporter.id);
  assert.equal(notif, undefined);
  assert.equal(database.prepare(
    `SELECT COUNT(*) AS total FROM messages m JOIN conversations c ON c.id = m.conversation_id
      WHERE (c.buyer_id = ? AND c.seller_id = ?) OR (c.buyer_id = ? AND c.seller_id = ?)`,
  ).get(reporter.id, reportsAccountId, reportsAccountId, reporter.id).total, 0);

  const audit = database.prepare(
    "SELECT action, details_json FROM admin_audit_log WHERE entity_id = ? ORDER BY id DESC LIMIT 1",
  ).get(created.body.report.id);
  assert.equal(audit.action, 'report.update');
  const auditDetails = JSON.parse(audit.details_json);
  assert.equal(auditDetails.reporterNotified, false);
  assert.equal(auditDetails.notificationChannel, null);

  const mine = await jsonRequest('/api/me/reports', { headers: userHeaders(reporter) });
  assert.equal(mine.status, 200, JSON.stringify(mine.body));
  assert.equal(mine.body.reports[0].id, created.body.report.id);
  assert.equal('admin_note' in mine.body.reports[0], false);
  assert.equal('resolved_by_admin_id' in mine.body.reports[0], false);
  assert.equal('reporter_id' in mine.body.reports[0], false);
});

test('respuesta opcional crea un chat real desde la cuenta oficial sin auditar el texto', async () => {
  const reporter = seller();
  const target = seller();
  const created = await jsonRequest('/api/reports', {
    method: 'POST',
    headers: userHeaders(reporter),
    body: {
      targetType: 'user', targetId: target.id, targetUserId: target.id,
      reason: 'Actividad sospechosa',
    },
  });
  const reporterMessage = 'Gracias por reportarlo. El caso ya fue atendido.';
  const updated = await jsonRequest(`/api/admin/reports/${created.body.report.id}`, {
    method: 'PATCH',
    headers: adminHeaders(),
    body: { status: 'resolved', reporterMessage },
  });

  assert.equal(updated.status, 200, JSON.stringify(updated.body));
  assert.equal(updated.body.reporterMessageSent, true);
  const conversation = database.prepare(`SELECT * FROM conversations
    WHERE buyer_id = ? AND seller_id = ? AND product_id IS NULL AND wanted_post_id IS NULL`)
    .get(reporter.id, reportsAccountId);
  assert.ok(conversation);
  const message = database.prepare('SELECT sender_id, text FROM messages WHERE conversation_id = ?').get(conversation.id);
  assert.deepEqual(message, { sender_id: reportsAccountId, text: reporterMessage });

  const notification = database.prepare(
    'SELECT type, body, data FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 1',
  ).get(reporter.id);
  assert.equal(notification.type, 'new_chat');
  assert.match(notification.body, /Reportes Mercadito UM/);
  assert.equal(JSON.parse(notification.data).conversationId, conversation.id);

  const audit = database.prepare(
    'SELECT details_json FROM admin_audit_log WHERE entity_id = ? ORDER BY id DESC LIMIT 1',
  ).get(created.body.report.id);
  const auditDetails = JSON.parse(audit.details_json);
  assert.equal(auditDetails.reporterNotified, true);
  assert.equal(auditDetails.notificationChannel, 'chat');
  assert.doesNotMatch(audit.details_json, /Gracias por reportarlo/);

  const retried = await jsonRequest(`/api/admin/reports/${created.body.report.id}`, {
    method: 'PATCH',
    headers: adminHeaders(),
    body: { status: 'resolved', reporterMessage: 'Este reintento no debe crear otro mensaje.' },
  });
  assert.equal(retried.status, 200, JSON.stringify(retried.body));
  assert.equal(retried.body.reporterMessageSent, true);
  assert.equal(retried.body.reporterMessageAlreadySent, true);
  assert.equal(database.prepare('SELECT COUNT(*) AS total FROM messages WHERE conversation_id = ?')
    .get(conversation.id).total, 1);
  assert.equal(database.prepare('SELECT COUNT(*) AS total FROM notifications WHERE user_id = ?')
    .get(reporter.id).total, 1);
  const retryAudit = database.prepare(
    'SELECT details_json FROM admin_audit_log WHERE entity_id = ? ORDER BY id DESC LIMIT 1',
  ).get(created.body.report.id);
  assert.equal(JSON.parse(retryAudit.details_json).reporterMessageCreated, false);
  assert.doesNotMatch(retryAudit.details_json, /Este reintento/);
});

test('dos reintentos concurrentes solo crean una respuesta de chat', async () => {
  const reporter = seller();
  const target = seller();
  const created = await jsonRequest('/api/reports', {
    method: 'POST', headers: userHeaders(reporter),
    body: { targetType: 'user', targetId: target.id, reason: 'Actividad sospechosa' },
  });
  const route = `/api/admin/reports/${created.body.report.id}`;
  const [first, second] = await Promise.all([
    jsonRequest(route, {
      method: 'PATCH', headers: adminHeaders(),
      body: { status: 'resolved', reporterMessage: 'Atendimos tu reporte.' },
    }),
    jsonRequest(route, {
      method: 'PATCH', headers: adminHeaders(),
      body: { status: 'resolved', reporterMessage: 'Atendimos tu reporte.' },
    }),
  ]);

  assert.equal(first.status, 200, JSON.stringify(first.body));
  assert.equal(second.status, 200, JSON.stringify(second.body));
  assert.deepEqual(
    [first.body.reporterMessageAlreadySent, second.body.reporterMessageAlreadySent].sort(),
    [false, true],
  );
  const conversation = database.prepare(`SELECT id FROM conversations
    WHERE buyer_id = ? AND seller_id = ?`).get(reporter.id, reportsAccountId);
  assert.ok(conversation);
  assert.equal(database.prepare('SELECT COUNT(*) AS total FROM messages WHERE conversation_id = ?')
    .get(conversation.id).total, 1);
  assert.equal(database.prepare('SELECT COUNT(*) AS total FROM notifications WHERE user_id = ?')
    .get(reporter.id).total, 1);
});

test('un bloqueo no impide cerrar el reporte y evita por completo el chat oficial', async () => {
  const reporter = seller();
  const target = seller();
  const created = await jsonRequest('/api/reports', {
    method: 'POST', headers: userHeaders(reporter),
    body: { targetType: 'user', targetId: target.id, reason: 'Posible fraude' },
  });
  db.setChatUserSetting(reporter.id, reportsAccountId, 'blocked', true);

  const updated = await jsonRequest(`/api/admin/reports/${created.body.report.id}`, {
    method: 'PATCH', headers: adminHeaders(),
    body: { status: 'resolved', reporterMessage: 'El caso fue atendido.' },
  });
  assert.equal(updated.status, 200, JSON.stringify(updated.body));
  assert.equal(updated.body.report.status, 'resolved');
  assert.equal(updated.body.reporterMessageSent, false);
  assert.equal(updated.body.reporterMessageSkipped, 'blocked');
  assert.match(updated.body.warning, /reporte se cerro/);
  assert.equal(database.prepare(`SELECT COUNT(*) AS total FROM conversations
    WHERE (buyer_id = ? AND seller_id = ?) OR (buyer_id = ? AND seller_id = ?)`)
    .get(reporter.id, reportsAccountId, reportsAccountId, reporter.id).total, 0);
  const audit = database.prepare(
    'SELECT details_json FROM admin_audit_log WHERE entity_id = ? ORDER BY id DESC LIMIT 1',
  ).get(created.body.report.id);
  const details = JSON.parse(audit.details_json);
  assert.equal(details.reporterNotified, false);
  assert.equal(details.notificationSkipped, 'blocked');
  assert.doesNotMatch(audit.details_json, /caso fue atendido/);
});

test('silenciar la cuenta oficial conserva el chat pero omite su notificacion', async () => {
  const reporter = seller();
  const target = seller();
  const reportedConversationId = `rp_reported_conv_${++sequence}`;
  db.createDirectConversation(reportedConversationId, reporter.id, target.id);
  const created = await jsonRequest('/api/reports', {
    method: 'POST', headers: userHeaders(reporter),
    body: { targetType: 'chat', targetId: reportedConversationId, reason: 'Mensajes sospechosos' },
  });
  db.setChatUserSetting(reporter.id, reportsAccountId, 'muted', true);

  const updated = await jsonRequest(`/api/admin/reports/${created.body.report.id}`, {
    method: 'PATCH', headers: adminHeaders(),
    body: { status: 'dismissed', reporterMessage: 'Terminamos de revisar el caso.' },
  });
  assert.equal(updated.status, 200, JSON.stringify(updated.body));
  assert.equal(updated.body.reporterMessageSent, true);
  const conversation = database.prepare(`SELECT id FROM conversations
    WHERE buyer_id = ? AND seller_id = ?`).get(reporter.id, reportsAccountId);
  assert.ok(conversation);
  assert.equal(database.prepare('SELECT COUNT(*) AS total FROM messages WHERE conversation_id = ?')
    .get(conversation.id).total, 1);
  assert.equal(database.prepare('SELECT COUNT(*) AS total FROM notifications WHERE user_id = ?')
    .get(reporter.id).total, 0);
});

test('producto y se busca derivan el autor y no confían en targetUserId', async () => {
  const reporter = seller();
  const owner = seller();
  const spoofed = seller();
  const productId = product(owner.id);
  const wantedId = wanted(owner.id);

  const productReport = await createReport(reporter, {
    targetType: 'product',
    targetId: productId,
    targetUserId: spoofed.id,
    reason: 'Información engañosa',
  });
  assert.equal(productReport.status, 201, JSON.stringify(productReport.body));
  assert.equal(productReport.body.report.target_user_id, owner.id);

  const wantedReport = await createReport(reporter, {
    targetType: 'wanted',
    targetId: wantedId,
    targetUserId: spoofed.id,
    reason: 'Solicitud sospechosa',
  });
  assert.equal(wantedReport.status, 201, JSON.stringify(wantedReport.body));
  assert.equal(wantedReport.body.report.target_user_id, owner.id);
});

test('un chat solo puede reportarlo un participante y deriva a la contraparte', async () => {
  const reporter = seller();
  const other = seller();
  const outsider = seller();
  const conversationId = `rp_conversation_${++sequence}`;
  await db.createDirectConversation(conversationId, reporter.id, other.id);

  const forbidden = await createReport(outsider, {
    targetType: 'chat',
    targetId: conversationId,
    targetUserId: outsider.id,
    reason: 'Conversación sospechosa',
  });
  assert.equal(forbidden.status, 404);

  const accepted = await createReport(reporter, {
    targetType: 'chat',
    targetId: conversationId,
    targetUserId: outsider.id,
    reason: 'Conversación sospechosa',
  });
  assert.equal(accepted.status, 201, JSON.stringify(accepted.body));
  assert.equal(accepted.body.report.target_user_id, other.id);
});

test('conserva objetivos retirados y rechaza ids que nunca existieron', async () => {
  const reporter = seller();
  const removedOwner = seller();
  const productId = product(removedOwner.id);
  database.prepare(`UPDATE products SET moderation_status = 'removed' WHERE id = ?`).run(productId);
  database.prepare(`UPDATE sellers SET admin_status = 'banned', deleted_at = datetime('now')
    WHERE id = ?`).run(removedOwner.id);

  const preserved = await createReport(reporter, {
    targetType: 'product',
    targetId: productId,
    targetUserId: 'cuenta_inventada',
    reason: 'Seguimiento de evidencia',
  });
  assert.equal(preserved.status, 201, JSON.stringify(preserved.body));
  assert.equal(preserved.body.report.target_user_id, removedOwner.id);

  const missing = await createReport(reporter, {
    targetType: 'user',
    targetId: 'cuenta_que_nunca_existio',
    reason: 'Actividad sospechosa',
  });
  assert.equal(missing.status, 404);
});

test('el payload no puede elegir remitente ni enviar mensajes antes de cerrar el caso', async () => {
  const reporter = seller();
  const target = seller();
  const created = await jsonRequest('/api/reports', {
    method: 'POST',
    headers: userHeaders(reporter),
    body: { targetType: 'user', targetId: target.id, reason: 'Posible fraude' },
  });

  const spoofed = await jsonRequest(`/api/admin/reports/${created.body.report.id}`, {
    method: 'PATCH', headers: adminHeaders(),
    body: { status: 'resolved', reporterMessage: 'Listo', senderId: reporter.id },
  });
  assert.equal(spoofed.status, 400);
  const tooEarly = await jsonRequest(`/api/admin/reports/${created.body.report.id}`, {
    method: 'PATCH', headers: adminHeaders(),
    body: { status: 'reviewing', reporterMessage: 'Aun lo revisamos' },
  });
  assert.equal(tooEarly.status, 400);
  assert.equal(db.getReportById(created.body.report.id).status, 'received');
});

test('un invitado puede reportar sin iniciar sesion ni crear una cuenta', async () => {
  const target = seller();
  const guest = generateAnonToken();

  const created = await jsonRequest('/api/reports', {
    method: 'POST',
    headers: userHeaders(guest),
    body: {
      targetType: 'user',
      targetId: target.id,
      targetUserId: target.id,
      reason: 'Posible fraude',
      details: 'Solicita un pago fuera de la plataforma.',
    },
  });

  assert.equal(created.status, 201, JSON.stringify(created.body));
  assert.equal(created.body.report.reporter_id, guest.anonId);
  assert.equal(created.body.report.reporterName, null);
  assert.equal(created.body.report.status, 'received');

  const updated = await jsonRequest(`/api/admin/reports/${created.body.report.id}`, {
    method: 'PATCH', headers: adminHeaders(),
    body: { status: 'dismissed', reporterMessage: 'Revisamos tu reporte y cerramos el caso.' },
  });
  assert.equal(updated.status, 200, JSON.stringify(updated.body));
  assert.equal(updated.body.reporterMessageSent, true);
  const conversation = database.prepare(`SELECT id FROM conversations
    WHERE buyer_id = ? AND seller_id = ? AND product_id IS NULL AND wanted_post_id IS NULL`)
    .get(guest.anonId, reportsAccountId);
  assert.ok(conversation, 'el invitado debe recibir un hilo persistente');
  assert.equal(database.prepare('SELECT sender_id FROM messages WHERE conversation_id = ?').get(conversation.id).sender_id, reportsAccountId);
});

test('reportar sin cuenta conserva una credencial anonima obligatoria', async () => {
  const created = await jsonRequest('/api/reports', {
    method: 'POST',
    body: {
      targetType: 'user',
      targetId: 'objetivo-publico',
      reason: 'Posible fraude',
    },
  });

  assert.equal(created.status, 401);
});

test('invitados distintos en la misma IP nunca comparten límite de reportes', async () => {
  for (let attempt = 0; attempt < 101; attempt += 1) {
    const guest = generateAnonToken();
    const response = await jsonRequest('/api/reports', {
      method: 'POST',
      headers: userHeaders(guest),
      body: {
        targetType: 'user',
        targetId: '',
        reason: 'x',
      },
    });
    assert.equal(response.status, 400);
  }
});

test('seguridad lista bloqueados/silenciados y el borrado de cuenta revoca datos personales', async () => {
  const owner = seller();
  const target = seller();
  const session = await generateSession(owner.id);
  db.setChatUserSetting(owner.id, target.id, 'blocked', true);
  db.setChatUserSetting(owner.id, target.id, 'muted', true);

  const security = await jsonRequest('/api/me/security', { headers: userHeaders(owner) });
  assert.equal(security.status, 200, JSON.stringify(security.body));
  assert.equal(security.body.users.length, 1);
  assert.equal(security.body.users[0].blocked, true);
  assert.equal(security.body.users[0].muted, true);

  const deleted = await jsonRequest('/api/me/account', {
    method: 'DELETE',
    headers: userHeaders(owner),
  });
  assert.equal(deleted.status, 200, JSON.stringify(deleted.body));

  const row = database.prepare(
    'SELECT email, phone, admin_status, deleted_at FROM sellers WHERE id = ?',
  ).get(owner.id);
  assert.equal(row.email, null);
  assert.equal(row.phone, null);
  assert.equal(row.admin_status, 'banned');
  assert.ok(row.deleted_at);
  assert.equal(db.getChatSafetySettings(owner.id).length, 0);

  const refreshed = await jsonRequest('/api/me/security', {
    headers: { Authorization: `Bearer ${session.token}` },
  });
  assert.equal(refreshed.status, 403);
});
