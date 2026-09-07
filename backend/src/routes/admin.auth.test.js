const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const testDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-admin-auth-'));
process.env.MERCADITO_DB_PATH = path.join(testDir, 'admin.db');
process.env.JWT_SECRET = 'seller-jwt-secret-that-is-not-the-admin-secret';
process.env.ADMIN_JWT_SECRET = 'admin-jwt-secret-with-at-least-thirty-two-characters';
process.env.ADMIN_TOTP_ENCRYPTION_KEY = 'admin-totp-encryption-key-at-least-32-chars';
process.env.ADMIN_PANEL_ORIGIN = 'https://mercaditoum.site';

const bcrypt = require('bcryptjs');
const cors = require('cors');
const express = require('express');
const jwt = require('jsonwebtoken');
const speakeasy = require('speakeasy');
const db = require('../database');
const {
  ADMIN_TOKEN_AUDIENCE,
  ADMIN_TOKEN_ISSUER,
  decryptTotpSecret,
  encryptTotpSecret,
  issueAdminToken,
} = require('../adminAuth');
const {
  MAX_DETAILS_JSON_BYTES,
  registrarAuditoriaAdmin,
  serializarDetallesAuditoria,
} = require('../adminAudit');
const { adminCorsOrigin } = require('../security');
const adminRoutes = require('./admin');
const productRoutes = require('./products');
const wantedRoutes = require('./wanted');
const data = require('../data');
const {
  DEFAULT_PUBLICATION_POLICIES,
  PUBLICATION_POLICY_KEYS,
} = require('../publicationPolicy');
const userAuth = require('../auth');

db.initDatabase();
const database = db.getDb();
const base32Secret = speakeasy.generateSecret({ length: 32 }).base32;
const password = 'una-clave-admin-muy-larga';
const inserted = database.prepare(
  `INSERT INTO admins (username, password_hash, totp_secret_encrypted)
   VALUES (?, ?, ?)`,
).run('rootadmin', bcrypt.hashSync(password, 4), encryptTotpSecret(base32Secret));
const adminId = Number(inserted.lastInsertRowid);

const app = express();
app.disable('x-powered-by');
app.use('/api/admin', cors({
  origin: adminCorsOrigin,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
  allowedHeaders: ['Authorization', 'Content-Type'],
}));
app.use(express.json());
adminRoutes.register(app);
productRoutes.register(app);
wantedRoutes.register(app);
app.use((error, _req, res, _next) => {
  res.status(error.status || 500).json({ error: 'request rejected' });
});

const server = http.createServer(app);
let baseUrl;

test.before(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(async () => {
  await new Promise(resolve => server.close(resolve));
  database.close();
});

function headers(extra = {}) {
  return {
    Origin: process.env.ADMIN_PANEL_ORIGIN,
    'Content-Type': 'application/json',
    ...extra,
  };
}

function currentTotp() {
  return speakeasy.totp({ secret: base32Secret, encoding: 'base32' });
}

async function login(body, extraHeaders = {}) {
  return fetch(`${baseUrl}/api/admin/auth/login`, {
    method: 'POST',
    headers: headers(extraHeaders),
    body: JSON.stringify(body),
  });
}

function freshAdminToken() {
  const admin = database.prepare(
    'SELECT id, username, token_version FROM admins WHERE id = ?',
  ).get(adminId);
  return issueAdminToken(admin);
}

let auditAccountSequence = 0;

function createBusinessForAudit({ state, verified }) {
  const id = `admin_audit_business_${++auditAccountSequence}`;
  const now = new Date().toISOString();
  database.prepare(
    `INSERT INTO sellers (
       id, name, isBusiness, verified, tipo_cuenta, businessCategory
     ) VALUES (?, ?, 1, ?, 'negocio', 'Servicios')`,
  ).run(id, `Negocio auditado ${auditAccountSequence}`, verified ? 1 : 0);
  database.prepare(
    `INSERT INTO verificaciones (
       usuario_id, tipo_cuenta, estado, fecha_verificacion, creado_en,
       nombre_negocio, responsable_negocio, identidad_confirmada_en,
       solicitud_json
     ) VALUES (?, 'negocio', ?, ?, ?, ?, 'Responsable de prueba', ?, '{}')`,
  ).run(
    id,
    state,
    state === 'verificado' ? now : null,
    now,
    `Negocio auditado ${auditAccountSequence}`,
    now,
  );
  return id;
}

async function adminPost(pathname, body, extraHeaders = {}) {
  return fetch(baseUrl + pathname, {
    method: 'POST',
    headers: headers({
      Authorization: `Bearer ${freshAdminToken()}`,
      ...extraHeaders,
    }),
    body: JSON.stringify(body),
  });
}

async function adminRequest(method, pathname, body) {
  return fetch(baseUrl + pathname, {
    method,
    headers: headers({ Authorization: `Bearer ${freshAdminToken()}` }),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

function configurableValues(policy) {
  return {
    productsActive: policy.productsActive,
    productsDaily: policy.productsDaily,
    wantedActive: policy.wantedActive,
    wantedDaily: policy.wantedDaily,
    durationDays: policy.durationDays,
  };
}

test('admins guarda bcrypt y cifra la semilla TOTP con AES-GCM', () => {
  const row = database.prepare('SELECT * FROM admins WHERE id = ?').get(adminId);
  assert.match(row.password_hash, /^\$2[aby]\$/);
  assert.notEqual(row.password_hash, password);
  assert.match(row.totp_secret_encrypted, /^v1\./);
  assert.equal(row.totp_secret_encrypted.includes(base32Secret), false);
  assert.equal(decryptTotpSecret(row.totp_secret_encrypted), base32Secret);
});

test('usuario, password y TOTP incorrectos no revelan cuál falló', async () => {
  const attempts = [
    { username: 'no-existe', password, totp: currentTotp() },
    { username: 'rootadmin', password: 'incorrecta', totp: currentTotp() },
    { username: 'rootadmin', password, totp: '000000' },
  ];
  const responses = [];
  for (const body of attempts) {
    const response = await login(body);
    responses.push({ status: response.status, body: await response.json() });
  }
  assert.deepEqual(responses.map(item => item.status), [401, 401, 401]);
  assert.equal(new Set(responses.map(item => item.body.error)).size, 1);
});

test('login correcto emite JWT admin con namespace propio y abre la sesión', async () => {
  database.prepare('UPDATE admins SET last_totp_step = NULL WHERE id = ?').run(adminId);
  const response = await login({ username: 'ROOTADMIN', password, totp: currentTotp() });
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.admin.username, 'rootadmin');
  assert.equal(payload.expiresIn, 1800);

  const decoded = jwt.verify(payload.token, process.env.ADMIN_JWT_SECRET, {
    algorithms: ['HS256'],
    audience: ADMIN_TOKEN_AUDIENCE,
    issuer: ADMIN_TOKEN_ISSUER,
  });
  assert.equal(decoded.typ, 'admin');
  assert.equal(decoded.sub, String(adminId));

  const session = await fetch(`${baseUrl}/api/admin/auth/session`, {
    headers: headers({ Authorization: `Bearer ${payload.token}` }),
  });
  assert.equal(session.status, 200);
  assert.deepEqual((await session.json()).admin, { id: adminId, username: 'rootadmin' });
});

test('el mismo código TOTP no puede iniciar dos sesiones', async () => {
  database.prepare('UPDATE admins SET last_totp_step = NULL WHERE id = ?').run(adminId);
  const totp = currentTotp();
  assert.equal((await login({ username: 'rootadmin', password, totp })).status, 200);
  assert.equal((await login({ username: 'rootadmin', password, totp })).status, 401);
});

test('todos los endpoints admin salvo login exigen Bearer', async () => {
  const checks = [
    ['GET', '/api/admin/auth/session'],
    ['POST', '/api/admin/auth/logout'],
    ['GET', '/api/admin/config'],
    ['PUT', '/api/admin/config/externo'],
    ['DELETE', '/api/admin/config/externo'],
    ['GET', '/api/admin/revision/verificaciones?status=pending'],
    ['POST', '/api/admin/revision/verificaciones/cuenta/approve'],
  ];
  for (const [method, pathname] of checks) {
    const response = await fetch(baseUrl + pathname, {
      method,
      headers: headers(),
      body: method === 'POST' ? '{}' : undefined,
    });
    assert.equal(response.status, 401, `${method} ${pathname} quedó expuesto`);
  }
});

test('un JWT normal de seller nunca autoriza el namespace admin', async () => {
  const sellerToken = userAuth.generateToken('seller_1');
  const response = await fetch(`${baseUrl}/api/admin/auth/session`, {
    headers: headers({ Authorization: `Bearer ${sellerToken}` }),
  });
  assert.equal(response.status, 401);
});

test('desactivar un admin invalida de inmediato un JWT ya emitido', async () => {
  const token = freshAdminToken();
  database.prepare('UPDATE admins SET active = 0 WHERE id = ?').run(adminId);
  const response = await fetch(`${baseUrl}/api/admin/auth/session`, {
    headers: headers({ Authorization: `Bearer ${token}` }),
  });
  assert.equal(response.status, 401);
  database.prepare('UPDATE admins SET active = 1 WHERE id = ?').run(adminId);
});

test('logout revoca el JWT actual en el backend', async () => {
  const token = freshAdminToken();
  const authHeaders = headers({ Authorization: `Bearer ${token}` });
  const logout = await fetch(`${baseUrl}/api/admin/auth/logout`, {
    method: 'POST',
    headers: authHeaders,
    body: '{}',
  });
  assert.equal(logout.status, 204);
  const session = await fetch(`${baseUrl}/api/admin/auth/session`, { headers: authHeaders });
  assert.equal(session.status, 401);
});

test('CORS admin admite solo el origen exacto y falla cerrado sin Origin', async () => {
  const token = freshAdminToken();
  const valid = await fetch(`${baseUrl}/api/admin/auth/session`, {
    headers: headers({ Authorization: `Bearer ${token}` }),
  });
  assert.equal(valid.status, 200);
  assert.equal(valid.headers.get('access-control-allow-origin'), process.env.ADMIN_PANEL_ORIGIN);

  for (const origin of ['https://evil.example', null]) {
    const requestHeaders = origin
      ? { Origin: origin, Authorization: `Bearer ${token}` }
      : { Authorization: `Bearer ${token}` };
    const response = await fetch(`${baseUrl}/api/admin/auth/session`, {
      headers: requestHeaders,
    });
    assert.equal(response.status, 403);
    assert.equal(response.headers.get('access-control-allow-origin'), null);
  }
});

test('rate limit bloquea fuerza bruta por nombre de administrador', async () => {
  let limited = false;
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const response = await login({
      username: 'objetivo-distinto',
      password: 'incorrecta',
      totp: '000000',
    });
    if (response.status === 429) limited = true;
  }
  assert.equal(limited, true);
});

test('admin_audit_log tiene FK e impone identidad validada y detalles acotados', () => {
  const foreignKeys = database.prepare("PRAGMA foreign_key_list('admin_audit_log')").all();
  assert.equal(
    foreignKeys.some(key => key.table === 'admins' && key.from === 'admin_id'),
    true,
  );
  assert.throws(
    () => registrarAuditoriaAdmin(database, {}, {
      action: 'verification.approve',
      entityType: 'verification',
      entityId: 'cuenta-sin-admin',
    }),
    /administrador autenticado/,
  );
  assert.throws(
    () => serializarDetallesAuditoria({ value: 'x'.repeat(MAX_DETAILS_JSON_BYTES) }),
    /no pueden superar/,
  );
});

test('todas las mutaciones de verificacion admin auditan al actor confiable una sola vez', async () => {
  const approveId = createBusinessForAudit({ state: 'pendiente', verified: false });
  const rejectId = createBusinessForAudit({ state: 'pendiente', verified: false });
  const revokeId = createBusinessForAudit({ state: 'verificado', verified: true });
  const restoreId = createBusinessForAudit({ state: 'rechazado', verified: false });
  const setId = createBusinessForAudit({ state: 'rechazado', verified: false });

  const operations = [
    [`/api/admin/revision/verificaciones/${approveId}/approve`,
      { reason: 'Aprobacion revisada por el administrador' }, 'approved'],
    [`/api/admin/revision/verificaciones/${rejectId}/reject`,
      { reason: 'Documentacion insuficiente para verificar' }, 'rejected'],
    [`/api/admin/revision/verificaciones/${revokeId}/revoke`,
      { reason: 'Se retiro tras una revision administrativa' }, 'revoked'],
    [`/api/admin/revision/verificaciones/${restoreId}/restore`,
      { reason: 'Se restauro despues de una segunda revision' }, 'restored'],
  ];
  for (const [pathname, body, expectedStatus] of operations) {
    const response = await adminPost(pathname, body);
    const responseBody = await response.json();
    assert.equal(response.status, 200, `${pathname}: ${JSON.stringify(responseBody)}`);
    assert.equal(responseBody.status, expectedStatus);
  }

  const requestId = '00000000-0000-4000-8000-000000000001';
  const setBody = {
    verified: true,
    expectedVerified: false,
    requestId,
    reason: 'Reactivacion manual con identidad ya comprobada',
  };
  const setResponse = await adminPost(
    `/api/admin/revision/cuentas/${setId}/verificacion`,
    setBody,
    { 'x-revision-actor': 'actor-falsificado' },
  );
  const setResponseBody = await setResponse.json();
  assert.equal(setResponse.status, 200, JSON.stringify(setResponseBody));
  assert.deepEqual(setResponseBody, { status: 'verified', replayed: false });

  const replay = await adminPost(
    `/api/admin/revision/cuentas/${setId}/verificacion`,
    setBody,
    { 'x-revision-actor': 'otro-actor-falsificado' },
  );
  assert.equal(replay.status, 200);
  assert.deepEqual(await replay.json(), { status: 'verified', replayed: true });

  const ids = [approveId, rejectId, revokeId, restoreId, setId];
  const auditRows = database.prepare(
    `SELECT admin_id AS adminId, action, entity_type AS entityType,
       entity_id AS entityId, details_json AS detailsJson, created_at AS createdAt
     FROM admin_audit_log
     WHERE entity_id IN (?, ?, ?, ?, ?)
     ORDER BY id`,
  ).all(...ids);
  assert.equal(auditRows.length, 5);
  assert.deepEqual(
    auditRows.map(row => [row.entityId, row.action, row.entityType]),
    [
      [approveId, 'verification.approve', 'verification'],
      [rejectId, 'verification.reject', 'verification'],
      [revokeId, 'verification.revoke', 'verification'],
      [restoreId, 'verification.restore', 'verification'],
      [setId, 'verification.set', 'account'],
    ],
  );
  assert.equal(auditRows.every(row => row.adminId === adminId), true);
  assert.equal(auditRows.some(row => row.detailsJson.includes('actor-falsificado')), false);
  assert.equal(JSON.parse(auditRows.at(-1).detailsJson).requestId, requestId);

  const legacySetLog = database.prepare(
    `SELECT actor, decided_at AS decidedAt FROM verification_admin_log
     WHERE request_id = ?`,
  ).get(requestId);
  assert.equal(legacySetLog.actor, 'rootadmin');
  assert.equal(auditRows.at(-1).createdAt, legacySetLog.decidedAt);
});

test('si falla el audit, la mutacion de verificacion se revierte completa', async () => {
  const accountId = createBusinessForAudit({ state: 'pendiente', verified: false });
  database.exec(`
    DROP TRIGGER IF EXISTS test_force_admin_audit_failure;
    CREATE TRIGGER test_force_admin_audit_failure
    BEFORE INSERT ON admin_audit_log
    BEGIN
      SELECT RAISE(ABORT, 'forced admin audit failure');
    END;
  `);

  let response;
  try {
    response = await adminPost(
      `/api/admin/revision/verificaciones/${accountId}/approve`,
      { reason: 'Esta operacion debe revertirse por completo' },
    );
  } finally {
    database.exec('DROP TRIGGER IF EXISTS test_force_admin_audit_failure');
  }
  assert.equal(response.status, 500);
  assert.deepEqual(
    database.prepare(
      `SELECT s.verified, v.estado
       FROM sellers s JOIN verificaciones v ON v.usuario_id = s.id
       WHERE s.id = ?`,
    ).get(accountId),
    { verified: 0, estado: 'pendiente' },
  );
  assert.equal(
    database.prepare(
      'SELECT COUNT(*) AS total FROM verification_review_log WHERE usuario_id = ?',
    ).get(accountId).total,
    0,
  );
  assert.equal(
    database.prepare(
      'SELECT COUNT(*) AS total FROM admin_audit_log WHERE entity_id = ?',
    ).get(accountId).total,
    0,
  );
});

test('config se siembra con exactamente los cinco limites vigentes', () => {
  const rows = database.prepare(
    `SELECT key, products_active AS productsActive,
       products_daily AS productsDaily, wanted_active AS wantedActive,
       wanted_daily AS wantedDaily, duration_days AS durationDays,
       updated_by_admin_id AS updatedByAdminId
     FROM config ORDER BY key`,
  ).all();
  assert.equal(rows.length, 5);
  assert.deepEqual(
    rows.map(row => row.key).sort(),
    [...PUBLICATION_POLICY_KEYS].sort(),
  );
  for (const row of rows) {
    assert.deepEqual(configurableValues(row), DEFAULT_PUBLICATION_POLICIES[row.key]);
    assert.equal(row.updatedByAdminId, null);
  }
});

test('CRUD admin de config actualiza, consulta y resetea sin eliminar la fila', async () => {
  const key = 'externo';
  const updatedValues = {
    productsActive: 12,
    productsDaily: 4,
    wantedActive: 6,
    wantedDaily: 2,
    durationDays: 45,
  };

  const allResponse = await adminRequest('GET', '/api/admin/config');
  const allBody = await allResponse.json();
  assert.equal(allResponse.status, 200);
  assert.deepEqual(allBody.config.map(item => item.key), [...PUBLICATION_POLICY_KEYS]);

  const updateResponse = await adminRequest('PUT', `/api/admin/config/${key}`, updatedValues);
  const updateBody = await updateResponse.json();
  assert.equal(updateResponse.status, 200, JSON.stringify(updateBody));
  assert.deepEqual(configurableValues(updateBody.config), updatedValues);
  assert.equal(updateBody.config.updatedByAdminId, adminId);

  const getResponse = await adminRequest('GET', `/api/admin/config/${key}`);
  const getBody = await getResponse.json();
  assert.equal(getResponse.status, 200);
  assert.deepEqual(getBody.config, updateBody.config);

  const updateAudit = database.prepare(
    `SELECT admin_id AS adminId, details_json AS detailsJson
     FROM admin_audit_log
     WHERE action = 'config.update' AND entity_type = 'config' AND entity_id = ?
     ORDER BY id DESC LIMIT 1`,
  ).get(key);
  assert.equal(updateAudit.adminId, adminId);
  const updateDetails = JSON.parse(updateAudit.detailsJson);
  assert.deepEqual(
    configurableValues(updateDetails.before),
    DEFAULT_PUBLICATION_POLICIES[key],
  );
  assert.deepEqual(configurableValues(updateDetails.after), updatedValues);

  const resetResponse = await adminRequest('DELETE', `/api/admin/config/${key}`);
  const resetBody = await resetResponse.json();
  assert.equal(resetResponse.status, 200, JSON.stringify(resetBody));
  assert.equal(resetBody.resetToDefaults, true);
  assert.match(resetBody.message, /fila se conservo/i);
  assert.deepEqual(
    configurableValues(resetBody.config),
    DEFAULT_PUBLICATION_POLICIES[key],
  );
  assert.equal(database.prepare('SELECT COUNT(*) AS total FROM config').get().total, 5);

  const resetAudit = database.prepare(
    `SELECT admin_id AS adminId, details_json AS detailsJson
     FROM admin_audit_log
     WHERE action = 'config.reset' AND entity_type = 'config' AND entity_id = ?
     ORDER BY id DESC LIMIT 1`,
  ).get(key);
  assert.equal(resetAudit.adminId, adminId);
  const resetDetails = JSON.parse(resetAudit.detailsJson);
  assert.deepEqual(configurableValues(resetDetails.before), updatedValues);
  assert.deepEqual(
    configurableValues(resetDetails.after),
    DEFAULT_PUBLICATION_POLICIES[key],
  );
});

test('PUT config exige el payload exacto y enteros dentro de rangos seguros', async () => {
  const key = 'um_sin_verificar';
  const valid = { ...DEFAULT_PUBLICATION_POLICIES[key] };
  const invalidPayloads = [
    { ...valid, durationDays: 0 },
    { ...valid, productsActive: -1 },
    { ...valid, productsDaily: 101 },
    { ...valid, wantedActive: 1.5 },
    { ...valid, wantedDaily: '2' },
    { ...valid, unexpected: 1 },
    { productsActive: valid.productsActive },
  ];
  const auditBefore = database.prepare(
    "SELECT COUNT(*) AS total FROM admin_audit_log WHERE entity_type = 'config' AND entity_id = ?",
  ).get(key).total;

  for (const payload of invalidPayloads) {
    const response = await adminRequest('PUT', `/api/admin/config/${key}`, payload);
    assert.equal(response.status, 400, JSON.stringify(await response.json()));
  }
  for (const [method, pathname] of [
    ['GET', '/api/admin/config/desconocido'],
    ['PUT', '/api/admin/config/desconocido'],
    ['DELETE', '/api/admin/config/desconocido'],
  ]) {
    const response = await adminRequest(method, pathname, method === 'PUT' ? valid : undefined);
    assert.equal(response.status, 404);
  }

  const current = database.prepare(
    `SELECT products_active AS productsActive, products_daily AS productsDaily,
       wanted_active AS wantedActive, wanted_daily AS wantedDaily,
       duration_days AS durationDays FROM config WHERE key = ?`,
  ).get(key);
  assert.deepEqual(current, valid);
  const auditAfter = database.prepare(
    "SELECT COUNT(*) AS total FROM admin_audit_log WHERE entity_type = 'config' AND entity_id = ?",
  ).get(key).total;
  assert.equal(auditAfter, auditBefore);
});

test('una falla del audit revierte de forma atomica la actualizacion de config', async () => {
  const key = 'um_verificado';
  const before = database.prepare(
    `SELECT products_active AS productsActive, products_daily AS productsDaily,
       wanted_active AS wantedActive, wanted_daily AS wantedDaily,
       duration_days AS durationDays, updated_by_admin_id AS updatedByAdminId,
       updated_at AS updatedAt FROM config WHERE key = ?`,
  ).get(key);
  database.exec(`
    DROP TRIGGER IF EXISTS test_force_config_audit_failure;
    CREATE TRIGGER test_force_config_audit_failure
    BEFORE INSERT ON admin_audit_log
    BEGIN
      SELECT RAISE(ABORT, 'forced config audit failure');
    END;
  `);

  let response;
  try {
    response = await adminRequest('PUT', `/api/admin/config/${key}`, {
      productsActive: 31,
      productsDaily: 7,
      wantedActive: 11,
      wantedDaily: 4,
      durationDays: 61,
    });
  } finally {
    database.exec('DROP TRIGGER IF EXISTS test_force_config_audit_failure');
  }
  assert.equal(response.status, 500);
  const after = database.prepare(
    `SELECT products_active AS productsActive, products_daily AS productsDaily,
       wanted_active AS wantedActive, wanted_daily AS wantedDaily,
       duration_days AS durationDays, updated_by_admin_id AS updatedByAdminId,
       updated_at AS updatedAt FROM config WHERE key = ?`,
  ).get(key);
  assert.deepEqual(after, before);
});

test('products y wanted consumen el limite actualizado sin reiniciar el servidor', async () => {
  const key = 'negocio_verificado';
  const liveValues = {
    productsActive: 41,
    productsDaily: 0,
    wantedActive: 11,
    wantedDaily: 0,
    durationDays: 7,
  };
  const updateResponse = await adminRequest('PUT', `/api/admin/config/${key}`, liveValues);
  assert.equal(updateResponse.status, 200, JSON.stringify(await updateResponse.json()));

  try {
    const sellerId = 'seller_live_config';
    database.prepare(
      `INSERT INTO sellers (
         id, name, isBusiness, verified, tipo_cuenta, paymentMethods
       ) VALUES (?, 'Negocio con config viva', 1, 1, 'negocio', '[]')`,
    ).run(sellerId);
    data.refrescarSellers();
    const sellerToken = userAuth.generateToken(sellerId);

    const productResponse = await fetch(`${baseUrl}/api/products`, {
      method: 'POST',
      headers: headers({ Authorization: `Bearer ${sellerToken}` }),
      body: '{}',
    });
    const productBody = await productResponse.json();
    assert.equal(productResponse.status, 429, JSON.stringify(productBody));
    assert.equal(productBody.code, 'PRODUCT_DAILY_LIMIT');
    assert.deepEqual(configurableValues(productBody.limits), liveValues);

    const wantedResponse = await fetch(`${baseUrl}/api/wanted`, {
      method: 'POST',
      headers: headers({ Authorization: `Bearer ${sellerToken}` }),
      body: JSON.stringify({
        title: 'Busco un articulo de prueba',
        description: 'Solicitud usada para probar el limite dinamico.',
        categoryId: 'prueba-config',
        type: 'producto',
      }),
    });
    const wantedBody = await wantedResponse.json();
    assert.equal(wantedResponse.status, 429, JSON.stringify(wantedBody));
    assert.equal(wantedBody.code, 'WANTED_DAILY_LIMIT');
    assert.deepEqual(configurableValues(wantedBody.limits), liveValues);
  } finally {
    const resetResponse = await adminRequest('DELETE', `/api/admin/config/${key}`);
    assert.equal(resetResponse.status, 200);
  }
});
