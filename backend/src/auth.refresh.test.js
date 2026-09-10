const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-refresh-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba-refresh';

const jwt = require('jsonwebtoken');
const db = require('./database');
const {
  generateSession,
  refreshSession,
  revokeRefreshToken,
  verificarToken,
} = require('./auth');

db.initDatabase();
db.getDb().prepare(
  `INSERT INTO sellers (id, name, email, avatarInitials)
   VALUES ('usuario-refresh', 'Usuario Refresh', 'refresh@example.com', 'UR')`,
).run();

test('el JWT de acceso dura treinta días', async () => {
  const session = await generateSession('usuario-refresh');
  const payload = jwt.decode(session.token);
  assert.ok(payload.exp - payload.iat >= 30 * 24 * 60 * 60 - 2);
  assert.equal(await verificarToken(session.token), 'usuario-refresh');
});

test('la credencial persistente emite tokens nuevos y no se guarda en claro', async () => {
  const session = await generateSession('usuario-refresh');
  const renewed = await refreshSession(session.refreshToken);

  assert.equal(await verificarToken(renewed.token), 'usuario-refresh');
  assert.notEqual(renewed.token, session.token);
  const stored = db.getDb().prepare(
    'SELECT token_hash, revoked_at FROM refresh_sessions WHERE user_id = ?',
  ).all('usuario-refresh');
  assert.ok(stored.length >= 1);
  assert.ok(stored.every(row => row.token_hash !== session.refreshToken));
  assert.ok(stored.every(row => row.revoked_at === null));
});

test('logout revoca la renovación persistente', async () => {
  const session = await generateSession('usuario-refresh');
  assert.ok(await refreshSession(session.refreshToken));

  await revokeRefreshToken(session.refreshToken, 'usuario-refresh');

  assert.equal(await refreshSession(session.refreshToken), null);
});

test('una credencial inventada no renueva ninguna sesión', async () => {
  assert.equal(await refreshSession('x'.repeat(64)), null);
});
