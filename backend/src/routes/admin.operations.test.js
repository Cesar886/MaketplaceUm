const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-admin-ops-'));
process.env.MERCADITO_DB_PATH = path.join(tempDir, 'test.db');
process.env.MERCADITO_BACKUP_DIR = path.join(tempDir, 'backups');
process.env.JWT_SECRET = 'seller-secret-admin-ops-123456789012345';
process.env.ADMIN_JWT_SECRET = 'admin-secret-admin-ops-123456789012345';
process.env.ADMIN_TOTP_ENCRYPTION_KEY = 'totp-secret-admin-ops-123456789012345';

const express = require('express');
const db = require('../database');
const { encryptTotpSecret, issueAdminToken } = require('../adminAuth');
const { generateSession, refreshSession } = require('../auth');
const { router: adminRouter } = require('./admin');

db.initDatabase();
const database = db.getDb();
const adminId = Number(database.prepare(`INSERT INTO admins
  (username, password_hash, totp_secret_encrypted) VALUES (?, ?, ?)`)
  .run('opsadmin', 'unused', encryptTotpSecret('JBSWY3DPEHPK3PXP')).lastInsertRowid);

let sequence = 0;
function seller() {
  const id = `ops_seller_${++sequence}`;
  database.prepare(`INSERT INTO sellers
    (id, name, email, avatarInitials, tipo_cuenta, last_active)
    VALUES (?, ?, ?, 'OP', 'estudiante', datetime('now'))`)
    .run(id, `Operación ${sequence}`, `${id}@example.com`);
  return id;
}

function product(owner, title = 'Producto de prueba') {
  const id = `ops_product_${++sequence}`;
  db.insertProduct({
    id, title, price: 20, category: 'otros', description: 'Descripción válida',
    seller: owner, images: [], stock_quantity: 1,
  });
  return id;
}

function wanted(owner, title = 'Búsqueda de prueba') {
  const id = `ops_wanted_${++sequence}`;
  db.createWantedPost({ id, userId: owner, title, categoryId: 'otros', type: 'producto' });
  return id;
}

let server;
let baseUrl;
test.before(async () => {
  const app = express();
  app.use(express.json());
  app.set('io', { in: () => ({ disconnectSockets() {} }) });
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

function authHeaders() {
  return {
    Authorization: `Bearer ${issueAdminToken({ id: adminId, username: 'opsadmin', token_version: 0 })}`,
    'Content-Type': 'application/json',
  };
}

async function request(route, { method = 'GET', body, auth = true } = {}) {
  return fetch(baseUrl + route, {
    method,
    headers: auth ? authHeaders() : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

test('dashboard y operaciones quedan protegidos por el JWT admin', async () => {
  assert.equal((await request('/api/admin/dashboard', { auth: false })).status, 401);
  const response = await request('/api/admin/dashboard');
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(typeof payload.pendingVerifications, 'number');
  assert.match(payload.users.activeDefinition, /7 días/);
});

test('suspender una cuenta corta JWT y refresh y registra auditoría atómica', async () => {
  const id = seller();
  const session = await generateSession(id);
  const response = await request(`/api/admin/users/${id}/status`, {
    method: 'PATCH',
    body: {
      status: 'suspended', expectedStatus: 'active',
      reason: 'Revisión preventiva solicitada por soporte',
      until: new Date(Date.now() + 86400000).toISOString(),
    },
  });
  assert.equal(response.status, 200, await response.text());
  assert.equal(await refreshSession(session.refreshToken), null);
  const row = database.prepare('SELECT admin_status FROM sellers WHERE id = ?').get(id);
  assert.equal(row.admin_status, 'suspended');
  const audit = database.prepare(
    "SELECT action FROM admin_audit_log WHERE entity_id = ? ORDER BY id DESC LIMIT 1",
  ).get(id);
  assert.equal(audit.action, 'account.suspend');
});

test('si falla la auditoría, un baneo se revierte completo', async () => {
  const id = seller();
  database.exec(`CREATE TRIGGER fail_ops_audit BEFORE INSERT ON admin_audit_log
    BEGIN SELECT RAISE(ABORT, 'forced audit failure'); END`);
  let response;
  try {
    response = await request(`/api/admin/users/${id}/status`, {
      method: 'PATCH',
      body: { status: 'banned', expectedStatus: 'active', reason: 'Fraude confirmado por soporte', until: null },
    });
  } finally {
    database.exec('DROP TRIGGER fail_ops_audit');
  }
  assert.equal(response.status, 500);
  assert.equal(
    database.prepare('SELECT admin_status FROM sellers WHERE id = ?').get(id).admin_status,
    'active',
  );
});

test('reset de cupos cambia la ventana efectiva sin borrar publicaciones', async () => {
  const id = seller();
  product(id);
  wanted(id);
  const beforeProducts = database.prepare('SELECT COUNT(*) AS n FROM products WHERE seller = ?').get(id).n;
  const response = await request(`/api/admin/users/${id}/reset-limits`, {
    method: 'POST', body: { scope: 'all' },
  });
  assert.equal(response.status, 200, await response.text());
  assert.equal(database.prepare('SELECT COUNT(*) AS n FROM products WHERE seller = ?').get(id).n, beforeProducts);
  assert.ok(db.getPublicationLimitSince(id, 'products', '2000-01-01T00:00:00.000Z') > '2000');
  assert.equal(
    database.prepare("SELECT action FROM admin_audit_log WHERE entity_id = ? ORDER BY id DESC LIMIT 1").get(id).action,
    'account.limits_reset',
  );
});

test('spam y eliminación lógica ocultan publicaciones públicas y conservan evidencia', async () => {
  const id = seller();
  const productId = product(id, 'Producto spam');
  const wantedId = wanted(id, 'Búsqueda eliminada');

  const spam = await request(`/api/admin/publications/product/${productId}/spam`, {
    method: 'PATCH', body: { reason: 'Contenido repetitivo identificado como spam', expectedStatus: 'visible' },
  });
  assert.equal(spam.status, 200, await spam.text());
  assert.equal(db.getProductById(productId), null);
  assert.equal(database.prepare('SELECT COUNT(*) AS n FROM products WHERE id = ?').get(productId).n, 1);

  const removed = await request(`/api/admin/publications/wanted/${wantedId}`, {
    method: 'DELETE', body: { reason: 'Publicación incompatible con las reglas', expectedStatus: 'visible' },
  });
  assert.equal(removed.status, 200, await removed.text());
  assert.equal(db.getWantedPostById(wantedId), null);
  const actions = database.prepare(
    'SELECT action FROM admin_audit_log WHERE entity_id IN (?, ?) ORDER BY id',
  ).all(productId, wantedId).map(row => row.action);
  assert.deepEqual(actions, ['publication.spam', 'publication.delete']);

  const notifications = database.prepare(
    'SELECT type, title, body, data FROM notifications WHERE user_id = ? ORDER BY created_at ASC',
  ).all(id);
  assert.equal(notifications.length, 2);
  assert.equal(notifications[0].type, 'publication_moderated');
  assert.equal(notifications[0].title, 'Tu publicación fue marcada como spam');
  assert.match(notifications[0].body, /Producto spam/);
  assert.match(notifications[0].body, /Contenido repetitivo/);
  assert.equal(JSON.parse(notifications[0].data).publicationId, productId);
  assert.equal(notifications[1].title, 'Tu publicación fue retirada');
  assert.match(notifications[1].body, /Búsqueda eliminada/);
  assert.equal(JSON.parse(notifications[1].data).publicationId, wantedId);
});

test('una moderación desde reportes puede omitir toda explicación al propietario', async () => {
  const owner = seller();
  const productId = product(owner, 'Producto reportado');

  const response = await request(`/api/admin/publications/product/${productId}/spam`, {
    method: 'PATCH',
    body: {
      reason: 'Medida administrativa vinculada al reporte rep_prueba',
      expectedStatus: 'visible',
      notifyOwner: false,
    },
  });
  assert.equal(response.status, 200, await response.text());
  assert.equal(database.prepare(
    'SELECT COUNT(*) AS total FROM notifications WHERE user_id = ?',
  ).get(owner).total, 0);
  const audit = database.prepare(
    'SELECT details_json FROM admin_audit_log WHERE entity_id = ? ORDER BY id DESC LIMIT 1',
  ).get(productId);
  assert.equal(JSON.parse(audit.details_json).ownerNotified, false);
});

test('operación masiva aborta si no puede respaldar y crea backup antes de aplicar', async () => {
  const first = seller();
  const second = seller();
  const impossible = path.join(tempDir, 'not-a-directory');
  fs.writeFileSync(impossible, 'x');
  process.env.MERCADITO_BACKUP_DIR = impossible;
  const failed = await request('/api/admin/users/bulk/status', {
    method: 'POST', body: {
      ids: [first, second], status: 'banned', until: null,
      reason: 'Cuentas coordinadas para fraude confirmado',
    },
  });
  assert.equal(failed.status, 503);
  assert.equal(database.prepare('SELECT COUNT(*) AS n FROM sellers WHERE id IN (?, ?) AND admin_status = ?')
    .get(first, second, 'active').n, 2);

  process.env.MERCADITO_BACKUP_DIR = path.join(tempDir, 'valid-backups');
  const succeeded = await request('/api/admin/users/bulk/status', {
    method: 'POST', body: {
      ids: [first, second], status: 'banned', until: null,
      reason: 'Cuentas coordinadas para fraude confirmado',
    },
  });
  assert.equal(succeeded.status, 200);
  const payload = await succeeded.json();
  assert.equal(payload.backupCreated, true);
  assert.equal(fs.existsSync(path.join(process.env.MERCADITO_BACKUP_DIR, payload.backupId)), true);
  assert.equal(database.prepare('SELECT COUNT(*) AS n FROM sellers WHERE id IN (?, ?) AND admin_status = ?')
    .get(first, second, 'banned').n, 2);
});

test('listados de usuarios, publicaciones y auditoría son paginados', async () => {
  for (const route of [
    '/api/admin/users?page=1&limit=10',
    '/api/admin/publications?page=1&limit=10',
    '/api/admin/audit-log?page=1&limit=10',
  ]) {
    const response = await request(route);
    assert.equal(response.status, 200, route);
    const payload = await response.json();
    assert.equal(payload.page, 1);
    assert.equal(payload.limit, 10);
    assert.equal(typeof payload.total, 'number');
  }
});

test('publicaciones se pueden localizar por id exacto para enfocar un reporte', async () => {
  const owner = seller();
  const productId = product(owner, 'Título que no contiene el identificador');
  const wantedId = wanted(owner, 'Solicitud sin el identificador en el título');

  for (const [kind, id] of [['product', productId], ['wanted', wantedId]]) {
    const response = await request(`/api/admin/publications?q=${encodeURIComponent(id)}&kind=${kind}`);
    const responseText = await response.text();
    assert.equal(response.status, 200, responseText);
    const payload = JSON.parse(responseText);
    assert.equal(payload.total, 1);
    assert.equal(payload.publications[0].id, id);
    assert.equal(payload.publications[0].kind, kind);
  }
});

test('un enlace de revisión recupera el reporte exacto después de recargar', async () => {
  const reporterId = seller();
  const targetId = seller();
  const report = db.createReport({
    reporterId,
    targetType: 'user',
    targetId,
    targetUserId: targetId,
    reason: 'Actividad sospechosa',
  });

  const response = await request(`/api/admin/reports/${encodeURIComponent(report.id)}`);
  const responseText = await response.text();
  assert.equal(response.status, 200, responseText);
  const payload = JSON.parse(responseText);
  assert.equal(payload.report.id, report.id);
  assert.equal(payload.report.reporter_id, reporterId);
  assert.equal(payload.report.target_user_id, targetId);
});

test('el detalle administrativo expone las visitas acumuladas del perfil', async () => {
  const id = seller();
  database.prepare('UPDATE sellers SET profile_views = 37 WHERE id = ?').run(id);

  const response = await request(`/api/admin/users/${id}`);
  const responseText = await response.text();
  assert.equal(response.status, 200, responseText);
  const payload = JSON.parse(responseText);
  assert.equal(payload.user.profileViews, 37);
});
