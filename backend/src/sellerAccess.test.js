const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

process.env.JWT_SECRET = 'seller-access-test-secret';
process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-seller-access-')),
  'test.db',
);

const jwt = require('jsonwebtoken');
const dbModule = require('./database');
const {
  getSellerAccess,
  getSellerTokenAccess,
  invalidateSellerSessions,
} = require('./sellerAccess');
const {
  generateAnonToken,
  generateSession,
  generateToken,
  optionalAuth,
  refreshSession,
  requireAuth,
  verificarToken,
} = require('./auth');

dbModule.initDatabase();
const database = dbModule.getDb();
let sequence = 0;

function createSeller(overrides = {}) {
  const id = overrides.id || `moderated_${++sequence}`;
  database.prepare(
    `INSERT INTO sellers (
       id, name, email, avatarInitials, admin_status,
       admin_status_reason, admin_status_until, auth_invalid_before
     ) VALUES (?, ?, ?, 'MC', ?, ?, ?, ?)`,
  ).run(
    id,
    `Moderated ${sequence}`,
    `${id}@example.com`,
    overrides.adminStatus || 'active',
    overrides.reason || null,
    overrides.until || null,
    overrides.invalidBefore || 0,
  );
  return id;
}

async function invokeMiddleware(middleware, token) {
  const req = { headers: token ? { authorization: `Bearer ${token}` } : {} };
  const res = {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
  let nextCalls = 0;
  await middleware(req, res, () => { nextCalls += 1; });
  return { req, res, nextCalls };
}

test('la migracion agrega estado seguro y rechaza valores fuera del catalogo', () => {
  const columns = database.prepare("PRAGMA table_info('sellers')").all().map(row => row.name);
  assert.ok(columns.includes('admin_status'));
  assert.ok(columns.includes('admin_status_reason'));
  assert.ok(columns.includes('admin_status_until'));
  assert.ok(columns.includes('auth_invalid_before'));

  const id = createSeller();
  const row = database.prepare(
    'SELECT admin_status, auth_invalid_before FROM sellers WHERE id = ?',
  ).get(id);
  assert.deepEqual(row, { admin_status: 'active', auth_invalid_before: 0 });
  assert.throws(
    () => database.prepare('UPDATE sellers SET admin_status = ? WHERE id = ?').run('shadowban', id),
    /CHECK constraint failed/,
  );
});

test('active permite acceso; banned y suspension vigente fallan cerrados', async () => {
  const active = createSeller();
  const banned = createSeller({ adminStatus: 'banned', reason: 'fraude confirmado' });
  const suspended = createSeller({
    adminStatus: 'suspended',
    reason: 'revision temporal',
    until: new Date(Date.now() + 60_000).toISOString(),
  });

  assert.equal((await getSellerAccess(database, active)).allowed, true);
  assert.equal((await getSellerAccess(database, banned)).code, 'ACCOUNT_BANNED');
  assert.equal((await getSellerAccess(database, banned)).reason, 'fraude confirmado');
  const suspendedAccess = await getSellerAccess(database, suspended);
  assert.equal(suspendedAccess.code, 'ACCOUNT_SUSPENDED');
  assert.equal(suspendedAccess.reason, 'revision temporal');
  assert.ok(suspendedAccess.suspendedUntil);
});

test('una suspension vencida vuelve a active y limpia sus metadatos', async () => {
  const id = createSeller({
    adminStatus: 'suspended',
    reason: 'ya cumplida',
    until: '2024-01-01 00:00:00',
  });

  assert.equal((await getSellerAccess(database, id, { nowMs: Date.parse('2024-01-02T00:00:00Z') })).allowed, true);
  assert.deepEqual(
    database.prepare(
      `SELECT admin_status, admin_status_reason, admin_status_until
         FROM sellers WHERE id = ?`,
    ).get(id),
    { admin_status: 'active', admin_status_reason: null, admin_status_until: null },
  );
});

test('una fecha de suspension corrupta no levanta la sancion por accidente', async () => {
  const id = createSeller({ adminStatus: 'suspended', until: 'fecha-imposible' });
  assert.equal((await getSellerAccess(database, id)).code, 'ACCOUNT_SUSPENDED');
  assert.equal(
    database.prepare('SELECT admin_status FROM sellers WHERE id = ?').get(id).admin_status,
    'suspended',
  );
});

test('un usuario inexistente o claim sin identidad nunca se autoriza', async () => {
  assert.equal((await getSellerAccess(database, 'no-existe')).code, 'SESSION_INVALIDATED');
  assert.equal((await getSellerTokenAccess(database, {})).allowed, false);
});

test('auth_invalid_before corta incluso JWT emitidos en el mismo segundo', async () => {
  const id = createSeller({ invalidBefore: 1_800_000_000_456 });
  assert.equal((await getSellerTokenAccess(database, {
    sub: id,
    iat: 1_800_000_000,
    auth_time_ms: 1_800_000_000_455,
  })).code, 'SESSION_INVALIDATED');
  assert.equal((await getSellerTokenAccess(database, {
    sub: id,
    iat: 1_800_000_000,
    auth_time_ms: 1_800_000_000_456,
  })).allowed, true);

  // Compatibilidad con JWT anteriores al claim de milisegundos.
  database.prepare('UPDATE sellers SET auth_invalid_before = ? WHERE id = ?')
    .run(1_800_000_001_000, id);
  assert.equal((await getSellerTokenAccess(database, { sub: id, iat: 1_800_000_000 })).allowed, false);
  assert.equal((await getSellerTokenAccess(database, { sub: id, iat: 1_800_000_001 })).allowed, true);
});

test('invalidar sesiones es monotono, atomico y revoca todos los refresh tokens', async () => {
  const id = createSeller();
  const first = await generateSession(id);
  const second = await generateSession(id);
  assert.ok(await refreshSession(first.refreshToken));
  assert.ok(await refreshSession(second.refreshToken));

  assert.equal(await invalidateSellerSessions(database, id, { nowMs: 5_000 }), true);
  assert.equal(await refreshSession(first.refreshToken), null);
  assert.equal(await refreshSession(second.refreshToken), null);
  assert.equal(
    database.prepare(
      'SELECT COUNT(*) AS count FROM refresh_sessions WHERE user_id = ? AND revoked_at IS NULL',
    ).get(id).count,
    0,
  );
  assert.equal(
    database.prepare('SELECT auth_invalid_before FROM sellers WHERE id = ?').get(id).auth_invalid_before,
    5_001,
  );

  await invalidateSellerSessions(database, id, { nowMs: 4_000 });
  assert.equal(
    database.prepare('SELECT auth_invalid_before FROM sellers WHERE id = ?').get(id).auth_invalid_before,
    5_001,
  );
  assert.equal(await invalidateSellerSessions(database, 'ausente'), false);
});

test('requireAuth bloquea estado/corte y optionalAuth degrada a visitante', async () => {
  const id = createSeller();
  const token = generateToken(id);
  assert.equal((await invokeMiddleware(requireAuth, token)).nextCalls, 1);

  database.prepare(
    `UPDATE sellers SET admin_status = 'suspended', admin_status_until = ? WHERE id = ?`,
  ).run(new Date(Date.now() + 60_000).toISOString(), id);

  const required = await invokeMiddleware(requireAuth, token);
  assert.equal(required.nextCalls, 0);
  assert.equal(required.res.statusCode, 403);
  assert.equal(required.res.body.error, 'ACCOUNT_SUSPENDED');

  const optional = await invokeMiddleware(optionalAuth, token);
  assert.equal(optional.nextCalls, 1);
  assert.equal(optional.req.user, undefined);
  assert.equal(await verificarToken(token), null);
});

test('un token de invitado valido conserva REST opcional/obligatorio y sockets', async () => {
  const guest = generateAnonToken();
  const required = await invokeMiddleware(requireAuth, guest.token);
  const optional = await invokeMiddleware(optionalAuth, guest.token);

  assert.equal(required.nextCalls, 1);
  assert.deepEqual(required.req.user.anon, true);
  assert.equal(optional.nextCalls, 1);
  assert.deepEqual(optional.req.user, { id: guest.anonId, anon: true });
  assert.equal(await verificarToken(guest.token), guest.anonId);

  const forgedShape = jwt.sign(
    { sub: 'cuenta-real', anon: true },
    process.env.JWT_SECRET,
    { algorithm: 'HS256' },
  );
  assert.equal((await invokeMiddleware(requireAuth, forgedShape)).res.statusCode, 401);
  assert.equal(await verificarToken(forgedShape), null);
});

test('refresh no permite rodear suspension o baneo', async () => {
  const suspended = createSeller();
  const suspendedSession = await generateSession(suspended);
  database.prepare(
    `UPDATE sellers SET admin_status = 'suspended', admin_status_until = ? WHERE id = ?`,
  ).run(new Date(Date.now() + 60_000).toISOString(), suspended);
  assert.equal(await refreshSession(suspendedSession.refreshToken), null);

  const banned = createSeller();
  const bannedSession = await generateSession(banned);
  database.prepare("UPDATE sellers SET admin_status = 'banned' WHERE id = ?").run(banned);
  assert.equal(await refreshSession(bannedSession.refreshToken), null);
});
