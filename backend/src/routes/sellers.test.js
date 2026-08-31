// Integración contra un servidor Express real y una SQLite temporal con el
// schema real (mismo patrón que routes/verificacion.test.js).

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-sellers-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');
const { registerSeller } = require('../data');
const sellersRoute = require('./sellers');

db.initDatabase();

let baseUrl;
let servidor;

test.before(async () => {
  const app = express();
  app.use(express.json());
  sellersRoute.register(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

let contador = 0;

function crearVendedor({ isBusiness }) {
  const id = `seller_test_${++contador}`;
  registerSeller({
    id,
    name: `Test ${id}`,
    avatarInitials: 'TT',
    major: '',
    isBusiness,
    verified: true,
    tipo_cuenta: isBusiness ? 'negocio' : 'estudiante',
  });
  return { id, token: generateToken(id) };
}

async function patch(id, token, body) {
  const res = await fetch(`${baseUrl}/api/sellers/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

async function get(id, token) {
  const res = await fetch(`${baseUrl}/api/sellers/${id}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return { status: res.status, body: await res.json() };
}

test('un negocio guarda sus redes sociales y las ve reflejadas en su perfil público', async () => {
  const negocio = crearVendedor({ isBusiness: true });

  const patchRes = await patch(negocio.id, negocio.token, {
    facebookUrl: 'https://facebook.com/minegocio',
    instagramUrl: 'https://instagram.com/minegocio',
    whatsappNumber: '5215512345678',
    tiktokUrl: 'https://tiktok.com/@minegocio',
    twitterUrl: 'https://x.com/minegocio',
  });
  assert.strictEqual(patchRes.status, 200);
  assert.strictEqual(patchRes.body.facebookUrl, 'https://facebook.com/minegocio');
  assert.strictEqual(patchRes.body.whatsappNumber, '5215512345678');

  const publicRes = await get(negocio.id);
  assert.strictEqual(publicRes.status, 200);
  assert.strictEqual(publicRes.body.instagramUrl, 'https://instagram.com/minegocio');
  assert.strictEqual(publicRes.body.tiktokUrl, 'https://tiktok.com/@minegocio');
  assert.strictEqual(publicRes.body.twitterUrl, 'https://x.com/minegocio');
});

test('actualizar solo un campo de red social no borra los demás (actualización parcial)', async () => {
  const negocio = crearVendedor({ isBusiness: true });
  await patch(negocio.id, negocio.token, {
    facebookUrl: 'https://facebook.com/minegocio',
    instagramUrl: 'https://instagram.com/minegocio',
  });

  const segundo = await patch(negocio.id, negocio.token, {
    instagramUrl: 'https://instagram.com/nuevo',
  });
  assert.strictEqual(segundo.status, 200);
  assert.strictEqual(segundo.body.facebookUrl, 'https://facebook.com/minegocio');
  assert.strictEqual(segundo.body.instagramUrl, 'https://instagram.com/nuevo');
});

test('mandar "" en un campo ya lleno lo limpia a null', async () => {
  const negocio = crearVendedor({ isBusiness: true });
  await patch(negocio.id, negocio.token, { facebookUrl: 'https://facebook.com/minegocio' });

  const limpiado = await patch(negocio.id, negocio.token, { facebookUrl: '' });
  assert.strictEqual(limpiado.status, 200);
  assert.strictEqual(limpiado.body.facebookUrl, null);
});

test('rechaza un link de la plataforma equivocada con mensaje claro', async () => {
  const negocio = crearVendedor({ isBusiness: true });
  const res = await patch(negocio.id, negocio.token, {
    instagramUrl: 'https://facebook.com/minegocio',
  });
  assert.strictEqual(res.status, 400);
  assert.match(res.body.error, /Instagram/);
});

test('rechaza un whatsappNumber con formato inválido', async () => {
  const negocio = crearVendedor({ isBusiness: true });
  const res = await patch(negocio.id, negocio.token, { whatsappNumber: '+52 1234' });
  assert.strictEqual(res.status, 400);
});

test('una cuenta que no es negocio no puede guardar redes sociales', async () => {
  const noNegocio = crearVendedor({ isBusiness: false });
  const res = await patch(noNegocio.id, noNegocio.token, {
    facebookUrl: 'https://facebook.com/algo',
  });
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.facebookUrl, null);
  const row = db.getDb().prepare('SELECT facebook_url FROM sellers WHERE id = ?').get(noNegocio.id);
  assert.strictEqual(row.facebook_url, null);
});

// ─── Insignia del enigma escondido ───────────────────────────
//
// Lo que se protege: que la posición aparezca en el perfil de quien lo
// resolvió (es lo único que la insignia necesita para pintarse) y que en el
// de todos los demás sea null — un `0` o un campo ausente harían que la app
// pintara "Enigma #0" o reventara al leerlo.

test('el perfil de quien no ha resuelto el enigma trae enigmaPosicion en null', async () => {
  const vendedor = crearVendedor({ isBusiness: false });

  const res = await get(vendedor.id);

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.enigmaPosicion, null);
});

test('el perfil público muestra la posición de quien sí lo resolvió', async () => {
  const vendedor = crearVendedor({ isBusiness: false });
  const { posicion } = db.registrarResolucionEnigma(vendedor.id);

  // Sin token: es el perfil como lo ve cualquiera, que es donde tiene que
  // lucirse la insignia.
  const res = await get(vendedor.id);

  assert.strictEqual(res.body.enigmaPosicion, posicion);
  assert.ok(posicion >= 1);
});
