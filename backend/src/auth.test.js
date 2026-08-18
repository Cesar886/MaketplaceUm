const test = require('node:test');
const assert = require('node:assert');

process.env.JWT_SECRET = 'secreto-de-prueba';

const jwt = require('jsonwebtoken');
const { generateToken, verificarToken } = require('./auth');

// `verificarToken` existe para el handshake de Socket.IO, que no pasa por
// middlewares de Express y necesita resolver un token a un userId a secas.

test('verificarToken devuelve el userId de un token válido', () => {
  assert.equal(verificarToken(generateToken('u1')), 'u1');
});

test('verificarToken devuelve null si el token está firmado con otro secreto', () => {
  const ajeno = jwt.sign({ sub: 'u1' }, 'otro-secreto');
  assert.equal(verificarToken(ajeno), null);
});

test('verificarToken devuelve null si el token expiró', () => {
  const expirado = jwt.sign({ sub: 'u1' }, process.env.JWT_SECRET, { expiresIn: -10 });
  assert.equal(verificarToken(expirado), null);
});

test('verificarToken devuelve null ante basura o ausencia de token', () => {
  assert.equal(verificarToken('no-es-un-jwt'), null);
  assert.equal(verificarToken(null), null);
  assert.equal(verificarToken(undefined), null);
});
