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

const express = require('express');
const db = require('../database');
const { encryptTotpSecret, issueAdminToken } = require('../adminAuth');
const { generateToken, generateSession } = require('../auth');
const reportsRoute = require('./reports');
const privacyRoute = require('./privacy');
const { router: adminRouter } = require('./admin');

db.initDatabase();
const database = db.getDb();
const adminId = Number(database.prepare(`INSERT INTO admins
  (username, password_hash, totp_secret_encrypted) VALUES (?, ?, ?)`)
  .run('reportadmin', 'unused', encryptTotpSecret('JBSWY3DPEHPK3PXP')).lastInsertRowid);

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

test('un reporte se crea como caso estructurado y admin puede resolverlo con auditoria', async () => {
  const reporter = seller();
  const target = seller();

  const created = await jsonRequest('/api/reports', {
    method: 'POST',
    headers: userHeaders(reporter),
    body: {
      targetType: 'user',
      targetId: target.id,
      targetUserId: target.id,
      reason: 'Actividad sospechosa',
      details: 'Pidio deposito fuera de la app.',
    },
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  assert.equal(created.body.report.status, 'received');
  assert.equal(created.body.report.reporter_id, reporter.id);

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
  assert.ok(updated.body.report.resolved_at);

  const notif = database.prepare(
    'SELECT type, title, body, data FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 1',
  ).get(reporter.id);
  assert.equal(notif.type, 'report_status_updated');
  assert.equal(notif.title, 'Tu reporte fue resuelto');
  assert.match(notif.body, /Se contacto al usuario reportado/);
  assert.equal(JSON.parse(notif.data).reportId, created.body.report.id);

  const audit = database.prepare(
    "SELECT action FROM admin_audit_log WHERE entity_id = ? ORDER BY id DESC LIMIT 1",
  ).get(created.body.report.id);
  assert.equal(audit.action, 'report.update');
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
