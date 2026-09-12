const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

process.env.JWT_SECRET = 'secreto-de-prueba';
process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-auth-unit-')),
  'test.db',
);

const jwt = require('jsonwebtoken');
const db = require('./database');
const { generateToken, verificarToken } = require('./auth');

db.initDatabase();
db.getDb().prepare(
  `INSERT INTO sellers (id, name, email, avatarInitials)
   VALUES ('u1', 'Usuario Uno', 'u1@example.com', 'UU')`,
).run();

// `verificarToken` existe para el handshake de Socket.IO, que no pasa por
// middlewares de Express y necesita resolver un token a un userId a secas.

test('verificarToken devuelve el userId de un token válido', async () => {
  assert.equal(await verificarToken(generateToken('u1')), 'u1');
});

test('verificarToken devuelve null si el token está firmado con otro secreto', async () => {
  const ajeno = jwt.sign({ sub: 'u1' }, 'otro-secreto');
  assert.equal(await verificarToken(ajeno), null);
});

test('verificarToken devuelve null si el token expiró', async () => {
  const expirado = jwt.sign({ sub: 'u1' }, process.env.JWT_SECRET, { expiresIn: -10 });
  assert.equal(await verificarToken(expirado), null);
});

test('verificarToken devuelve null ante basura o ausencia de token', async () => {
  assert.equal(await verificarToken('no-es-un-jwt'), null);
  assert.equal(await verificarToken(null), null);
  assert.equal(await verificarToken(undefined), null);
});

// ─── Cuentas de Google ───────────────────────────────────────
//
// Estas pruebas existen por un agujero concreto: /api/auth/register trata
// una fila SIN password_hash como "cuenta legacy" y le rellena la contraseña
// que le manden (ver migración 21). Una cuenta creada con Google no tiene
// password_hash, así que sin esta comprobación bastaría con saber el correo
// de alguien para ponerle contraseña y quedarse con su cuenta.

const { esCuentaDeGoogle } = require('./auth');

test('una fila con auth_provider google es una cuenta de Google', () => {
  assert.equal(esCuentaDeGoogle({ auth_provider: 'google', password_hash: null }), true);
});

test('una cuenta de contraseña sin hash (legacy) NO es una cuenta de Google', () => {
  assert.equal(esCuentaDeGoogle({ auth_provider: 'password', password_hash: null }), false);
});

test('una fila de una base anterior a la migración tampoco lo es', () => {
  assert.equal(esCuentaDeGoogle({ password_hash: null }), false);
});

test('ausencia de fila no es una cuenta de Google', () => {
  assert.equal(esCuentaDeGoogle(null), false);
  assert.equal(esCuentaDeGoogle(undefined), false);
});
