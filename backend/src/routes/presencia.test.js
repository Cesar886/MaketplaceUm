// Integración de la presencia sobre HTTP: el toggle de privacidad y los dos
// sitios que exponen el estado (lista de chats y perfil de vendedor).
//
// Mismo patrón que routes/sellers.test.js: Express real y SQLite temporal.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-presencia-http-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');
const { registerSeller } = require('../data');
const privacyRoute = require('./privacy');
const chatRoute = require('./chat');
const sellersRoute = require('./sellers');

db.initDatabase();

/** Registro de presencia falso: se le dice a mano quién está en línea. */
const enLinea = new Set();
const registroFalso = {
  estaEnLinea: (userId) => enLinea.has(userId),
};

let baseUrl;
let servidor;

test.before(async () => {
  const app = express();
  app.use(express.json());
  app.set('presencia', registroFalso);
  privacyRoute.register(app);
  chatRoute.register(app);
  sellersRoute.register(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  enLinea.clear();
  await new Promise(r => servidor.close(r));
});

let contador = 0;

function crearVendedor() {
  const id = `pres_http_${++contador}`;
  registerSeller({
    id,
    name: `Test ${id}`,
    avatarInitials: 'TT',
    major: '',
    isBusiness: false,
    verified: true,
    tipo_cuenta: 'estudiante',
  });
  return { id, token: generateToken(id) };
}

async function pedir(ruta, { metodo = 'GET', token, body } = {}) {
  const res = await fetch(`${baseUrl}${ruta}`, {
    method: metodo,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}

/** Deja a `comprador` y `vendedor` con una conversación abierta. */
function crearConversacion(compradorId, vendedorId) {
  const convId = `conv_${compradorId}_${vendedorId}`;
  db.createConversation(convId, null, compradorId, vendedorId);
  return convId;
}

// ─── Toggle de privacidad ────────────────────────────────────

test('GET /api/me/privacy exige sesión', async () => {
  const res = await pedir('/api/me/privacy');
  assert.equal(res.status, 401);
});

test('una cuenta nueva arranca compartiendo su estado en línea', async () => {
  const yo = crearVendedor();

  const res = await pedir('/api/me/privacy', { token: yo.token });

  assert.equal(res.status, 200);
  assert.equal(res.body.showOnlineStatus, true);
});

test('PATCH /api/me/privacy apaga el estado y el GET lo confirma', async () => {
  const yo = crearVendedor();

  const patch = await pedir('/api/me/privacy', {
    metodo: 'PATCH',
    token: yo.token,
    body: { showOnlineStatus: false },
  });

  assert.equal(patch.status, 200);
  assert.equal(patch.body.showOnlineStatus, false);
  const get = await pedir('/api/me/privacy', { token: yo.token });
  assert.equal(get.body.showOnlineStatus, false);
});

test('PATCH /api/me/privacy rechaza un valor que no es booleano', async () => {
  const yo = crearVendedor();

  const res = await pedir('/api/me/privacy', {
    metodo: 'PATCH',
    token: yo.token,
    body: { showOnlineStatus: 'sí' },
  });

  assert.equal(res.status, 400);
});

test('PATCH /api/me/privacy exige sesión', async () => {
  const res = await pedir('/api/me/privacy', {
    metodo: 'PATCH',
    body: { showOnlineStatus: false },
  });
  assert.equal(res.status, 401);
});

// ─── Lista de chats ──────────────────────────────────────────

test('la lista de chats marca en línea al interlocutor conectado', async () => {
  const yo = crearVendedor();
  const otro = crearVendedor();
  crearConversacion(yo.id, otro.id);
  enLinea.add(otro.id);

  const res = await pedir(`/api/chat/conversations?userId=${yo.id}`, { token: yo.token });

  assert.equal(res.status, 200);
  assert.equal(res.body.conversations[0].otherUser.isOnline, true);
  assert.equal(res.body.conversations[0].otherUser.lastActive, null);
});

test('la lista de chats devuelve la última actividad del interlocutor desconectado', async () => {
  const yo = crearVendedor();
  const otro = crearVendedor();
  crearConversacion(yo.id, otro.id);
  db.setUltimaActividad(otro.id, '2026-08-17T09:00:00.000Z');

  const res = await pedir(`/api/chat/conversations?userId=${yo.id}`, { token: yo.token });

  assert.equal(res.body.conversations[0].otherUser.isOnline, false);
  assert.equal(res.body.conversations[0].otherUser.lastActive, '2026-08-17T09:00:00.000Z');
});

test('quien apagó su estado no ve el de su interlocutor en la lista de chats', async () => {
  const yo = crearVendedor();
  const otro = crearVendedor();
  crearConversacion(yo.id, otro.id);
  enLinea.add(otro.id);
  db.setMostrarEstadoEnLinea(yo.id, false);

  const res = await pedir(`/api/chat/conversations?userId=${yo.id}`, { token: yo.token });

  assert.equal(res.body.conversations[0].otherUser.isOnline, false);
  assert.equal(res.body.conversations[0].otherUser.lastActive, null);
});

test('no se ve el estado de un interlocutor que lo tiene oculto', async () => {
  const yo = crearVendedor();
  const otro = crearVendedor();
  crearConversacion(yo.id, otro.id);
  enLinea.add(otro.id);
  db.setMostrarEstadoEnLinea(otro.id, false);

  const res = await pedir(`/api/chat/conversations?userId=${yo.id}`, { token: yo.token });

  assert.equal(res.body.conversations[0].otherUser.isOnline, false);
});

// ─── Perfil de vendedor ──────────────────────────────────────

test('el perfil de un vendedor conectado lo reporta en línea', async () => {
  const yo = crearVendedor();
  const otro = crearVendedor();
  enLinea.add(otro.id);

  const res = await pedir(`/api/sellers/${otro.id}`, { token: yo.token });

  assert.equal(res.status, 200);
  assert.equal(res.body.isOnline, true);
});

test('un visitante sin sesión no ve la presencia en el perfil', async () => {
  const otro = crearVendedor();
  enLinea.add(otro.id);

  const res = await pedir(`/api/sellers/${otro.id}`);

  assert.equal(res.body.isOnline, false);
  assert.equal(res.body.lastActive, null);
});
