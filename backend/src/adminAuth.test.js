const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const bcrypt = require('bcryptjs');
const cors = require('cors');
const express = require('express');
const jwt = require('jsonwebtoken');
const speakeasy = require('speakeasy');

const TEMP_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-admin-auth-'));
const DB_PATH = path.join(TEMP_DIR, 'admin-auth.test.db');
const ADMIN_ORIGIN = 'https://panel.mercaditoum.test';
const ADMIN_JWT_SECRET = 'admin-jwt-secret-for-tests-32-bytes-minimum';
const ADMIN_TOTP_ENCRYPTION_KEY = 'admin-totp-encryption-key-for-tests-32-bytes';
const USERNAME = 'admin.prueba';
const PASSWORD = 'Password-administrativo-de-prueba-1';
const TOTP_SECRET = speakeasy.generateSecret({ length: 20 }).base32;

// Estas variables deben existir antes de cargar database/adminAuth: ambos
// módulos leen configuración durante su inicialización.
process.env.MERCADITO_DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'jwt-de-usuarios-ordinarios-para-pruebas';
process.env.ADMIN_JWT_SECRET = ADMIN_JWT_SECRET;
process.env.ADMIN_TOTP_ENCRYPTION_KEY = ADMIN_TOTP_ENCRYPTION_KEY;
process.env.ADMIN_PANEL_ORIGIN = ADMIN_ORIGIN;
process.env.NODE_ENV = 'test';

const db = require('./database');
const { adminCorsOrigin } = require('./security');
const {
  ADMIN_TOKEN_AUDIENCE,
  ADMIN_TOKEN_ISSUER,
  ADMIN_TOKEN_TTL_SECONDS,
  adminAuthConfigured,
  authenticateAdmin,
  decryptTotpSecret,
  encryptTotpSecret,
  issueAdminToken,
  requireAdmin,
} = require('./adminAuth');

db.initDatabase();

const database = db.getDb();
const passwordHash = bcrypt.hashSync(PASSWORD, 4);
const encryptedTotp = encryptTotpSecret(TOTP_SECRET);
const inserted = database.prepare(
  `INSERT INTO admins (username, password_hash, totp_secret_encrypted)
   VALUES (?, ?, ?)`,
).run(USERNAME, passwordHash, encryptedTotp);
const ADMIN_ID = Number(inserted.lastInsertRowid);

function resetAdmin() {
  database.prepare(
    `UPDATE admins SET active = 1, token_version = 0, last_totp_step = NULL,
       last_login_at = NULL WHERE id = ?`,
  ).run(ADMIN_ID);
  database.prepare('DELETE FROM admin_revoked_tokens').run();
}

function currentTotp() {
  return speakeasy.totp({ secret: TOTP_SECRET, encoding: 'base32', step: 30 });
}

function wrongTotp(validTotp) {
  return validTotp === '000000' ? '111111' : '000000';
}

function currentAdmin() {
  return database.prepare(
    'SELECT id, username, token_version FROM admins WHERE id = ?',
  ).get(ADMIN_ID);
}

function createMiddlewareApp() {
  const app = express();
  app.get('/protected', requireAdmin, (req, res) => {
    res.json({ admin: req.admin, session: req.adminSession });
  });
  return app;
}

function createAdminRoutesApp() {
  // Se carga aquí, y no arriba, para que las pruebas unitarias de adminAuth
  // sigan dando un diagnóstico útil mientras routes/admin.js se implementa.
  const adminRoutes = require('./routes/admin');
  assert.equal(typeof adminRoutes.register, 'function');

  const app = express();
  app.disable('x-powered-by');
  // Reproduce el montaje de index.js sin importarlo (index.js abre :3000 y
  // agenda jobs). Así se prueba el CORS real de Express, no solo su callback.
  app.use('/api/admin', cors({
    origin: adminCorsOrigin,
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'],
    allowedHeaders: ['Authorization', 'Content-Type'],
    credentials: false,
    maxAge: 600,
  }));
  app.use(express.json({ limit: '1mb', strict: true }));
  adminRoutes.register(app);
  app.use((error, _req, res, _next) => {
    res.status(error.status || 500).json({ error: error.message });
  });
  return app;
}

async function start(app) {
  const server = http.createServer(app);
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  return {
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    close: () => new Promise((resolve, reject) => {
      server.close(error => (error ? reject(error) : resolve()));
    }),
  };
}

async function request(baseUrl, route, {
  method = 'GET',
  origin = ADMIN_ORIGIN,
  token,
  body,
  headers: extraHeaders = {},
} = {}) {
  const headers = { ...extraHeaders };
  if (origin !== null) headers.Origin = origin;
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  const response = await fetch(baseUrl + route, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let payload = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = text;
    }
  }
  return { response, payload, text };
}

test.beforeEach(() => {
  process.env.ADMIN_JWT_SECRET = ADMIN_JWT_SECRET;
  process.env.ADMIN_TOTP_ENCRYPTION_KEY = ADMIN_TOTP_ENCRYPTION_KEY;
  process.env.ADMIN_PANEL_ORIGIN = ADMIN_ORIGIN;
  process.env.NODE_ENV = 'test';
  resetAdmin();
});

test.after(() => {
  database.close();
  fs.rmSync(TEMP_DIR, { recursive: true, force: true });
});

test('la migración crea admins sin guardar contraseña ni TOTP en claro', () => {
  const columns = database.prepare('PRAGMA table_info(admins)').all();
  const names = new Set(columns.map(column => column.name));
  assert.ok(names.has('username'));
  assert.ok(names.has('password_hash'));
  assert.ok(names.has('totp_secret_encrypted'));
  assert.ok(names.has('active'));
  assert.ok(names.has('token_version'));

  const stored = database.prepare(
    'SELECT password_hash, totp_secret_encrypted FROM admins WHERE id = ?',
  ).get(ADMIN_ID);
  assert.notEqual(stored.password_hash, PASSWORD);
  assert.match(stored.password_hash, /^\$2[aby]\$/);
  assert.notEqual(stored.totp_secret_encrypted, TOTP_SECRET);
  assert.equal(decryptTotpSecret(stored.totp_secret_encrypted), TOTP_SECRET);
});

test('falla cerrado cuando los secretos administrativos no cumplen el mínimo', () => {
  process.env.ADMIN_JWT_SECRET = 'corto';
  assert.equal(adminAuthConfigured(), false);
  assert.throws(() => issueAdminToken(currentAdmin()), /32 caracteres/);

  process.env.ADMIN_JWT_SECRET = ADMIN_JWT_SECRET;
  process.env.ADMIN_TOTP_ENCRYPTION_KEY = 'corta';
  assert.equal(adminAuthConfigured(), false);
  assert.throws(() => encryptTotpSecret(TOTP_SECRET), /32 caracteres/);
});

test('exige contraseña y TOTP correctos y emite un JWT administrativo propio', async () => {
  const totp = currentTotp();

  const wrongPassword = await authenticateAdmin({
    username: USERNAME,
    password: 'password-incorrecto',
    totp,
  });
  assert.equal(wrongPassword.authenticated, false);

  const wrongCode = await authenticateAdmin({
    username: USERNAME,
    password: PASSWORD,
    totp: wrongTotp(totp),
  });
  assert.equal(wrongCode.authenticated, false);

  const authenticated = await authenticateAdmin({
    username: `  ${USERNAME.toUpperCase()}  `,
    password: PASSWORD,
    totp,
  });
  assert.equal(authenticated.authenticated, true);
  assert.equal(authenticated.admin.id, ADMIN_ID);
  assert.equal(authenticated.admin.username, USERNAME);
  assert.equal(authenticated.expiresIn, ADMIN_TOKEN_TTL_SECONDS);

  const payload = jwt.verify(authenticated.token, ADMIN_JWT_SECRET, {
    algorithms: ['HS256'],
    audience: ADMIN_TOKEN_AUDIENCE,
    issuer: ADMIN_TOKEN_ISSUER,
  });
  assert.equal(payload.typ, 'admin');
  assert.equal(payload.sub, String(ADMIN_ID));
  assert.equal(payload.username, USERNAME);
  assert.equal(payload.ver, 0);
  assert.equal(typeof payload.jti, 'string');
  assert.ok(payload.exp - payload.iat <= ADMIN_TOKEN_TTL_SECONDS);
});

test('un código TOTP aceptado no se puede reutilizar', async () => {
  const credentials = { username: USERNAME, password: PASSWORD, totp: currentTotp() };
  const first = await authenticateAdmin(credentials);
  const replay = await authenticateAdmin(credentials);

  assert.equal(first.authenticated, true);
  assert.equal(replay.authenticated, false);
  const row = database.prepare(
    'SELECT last_totp_step, last_login_at FROM admins WHERE id = ?',
  ).get(ADMIN_ID);
  assert.ok(Number.isSafeInteger(row.last_totp_step));
  assert.ok(row.last_login_at);
});

test('un administrador inactivo no puede iniciar ni conservar sesión', async t => {
  const token = issueAdminToken(currentAdmin());
  database.prepare('UPDATE admins SET active = 0 WHERE id = ?').run(ADMIN_ID);

  const login = await authenticateAdmin({
    username: USERNAME,
    password: PASSWORD,
    totp: currentTotp(),
  });
  assert.equal(login.authenticated, false);

  const server = await start(createMiddlewareApp());
  t.after(server.close);
  const { response } = await request(server.baseUrl, '/protected', { token });
  assert.equal(response.status, 401);
});

test('requireAdmin rechaza un JWT de usuario aunque esté firmado con la clave admin', async t => {
  // Incluso una mala configuración que reutilizara claves no debe convertir
  // un token ordinario en uno administrativo: faltan typ/aud/iss/ver.
  const userToken = jwt.sign(
    { sub: 'usuario-normal' },
    ADMIN_JWT_SECRET,
    { algorithm: 'HS256', expiresIn: '30m', jwtid: 'jwt-de-usuario' },
  );
  const server = await start(createMiddlewareApp());
  t.after(server.close);

  const { response } = await request(server.baseUrl, '/protected', { token: userToken });
  assert.equal(response.status, 401);
});

test('requireAdmin resuelve identidad desde el token y no desde cabeceras falsificables', async t => {
  const token = issueAdminToken(currentAdmin());
  const server = await start(createMiddlewareApp());
  t.after(server.close);

  const { response, payload } = await request(server.baseUrl, '/protected', {
    token,
    headers: { 'X-Revision-Actor': 'atacante', 'X-Admin-User': 'atacante' },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(payload.admin, { id: ADMIN_ID, username: USERNAME });
  assert.equal(typeof payload.session.jti, 'string');
  assert.ok(Number.isSafeInteger(payload.session.expiresAt));
});

test('todas las rutas administrativas salvo login exigen token', async t => {
  const server = await start(createAdminRoutesApp());
  t.after(server.close);
  const protectedRoutes = [
    ['GET', '/api/admin/auth/session'],
    ['POST', '/api/admin/auth/logout'],
    ['GET', '/api/admin/revision/verificaciones?status=pending'],
    ['GET', '/api/admin/revision/cuentas'],
    ['GET', '/api/admin/revision/historial'],
  ];

  for (const [method, route] of protectedRoutes) {
    const { response, text } = await request(server.baseUrl, route, { method });
    assert.equal(response.status, 401, `${method} ${route}: ${text}`);
  }
});

test('el login público exige password+TOTP y habilita una sesión protegida', async t => {
  const server = await start(createAdminRoutesApp());
  t.after(server.close);

  const rejected = await request(server.baseUrl, '/api/admin/auth/login', {
    method: 'POST',
    body: { username: USERNAME, password: PASSWORD, totp: '12345' },
  });
  assert.equal(rejected.response.status, 401);

  const accepted = await request(server.baseUrl, '/api/admin/auth/login', {
    method: 'POST',
    body: { username: USERNAME, password: PASSWORD, totp: currentTotp() },
  });
  assert.equal(accepted.response.status, 200, accepted.text);
  assert.equal(typeof accepted.payload.token, 'string');

  const session = await request(server.baseUrl, '/api/admin/auth/session', {
    token: accepted.payload.token,
  });
  assert.equal(session.response.status, 200, session.text);
  assert.equal(session.payload.admin.id, ADMIN_ID);
  assert.equal(session.payload.admin.username, USERNAME);
});

test('CORS administrativo rechaza origen malicioso y permite solo el configurado', async t => {
  const server = await start(createAdminRoutesApp());
  t.after(server.close);

  const malicious = await request(server.baseUrl, '/api/admin/auth/login', {
    method: 'POST',
    origin: 'https://evil.example',
    body: { username: USERNAME, password: PASSWORD, totp: currentTotp() },
  });
  assert.equal(malicious.response.status, 403);
  assert.equal(malicious.response.headers.get('access-control-allow-origin'), null);

  const missing = await request(server.baseUrl, '/api/admin/auth/login', {
    method: 'POST',
    origin: null,
    body: { username: USERNAME, password: PASSWORD, totp: currentTotp() },
  });
  assert.equal(missing.response.status, 403);

  const preflight = await request(server.baseUrl, '/api/admin/auth/session', {
    method: 'OPTIONS',
    headers: {
      'Access-Control-Request-Method': 'GET',
      'Access-Control-Request-Headers': 'authorization',
    },
  });
  assert.equal(preflight.response.status, 204, preflight.text);
  assert.equal(
    preflight.response.headers.get('access-control-allow-origin'),
    ADMIN_ORIGIN,
  );
  assert.match(
    preflight.response.headers.get('access-control-allow-headers') || '',
    /authorization/i,
  );

  const allowed = await request(server.baseUrl, '/api/admin/auth/login', {
    method: 'POST',
    body: { username: USERNAME, password: 'incorrecta', totp: currentTotp() },
  });
  assert.equal(allowed.response.status, 401);
  assert.equal(
    allowed.response.headers.get('access-control-allow-origin'),
    ADMIN_ORIGIN,
  );
});
