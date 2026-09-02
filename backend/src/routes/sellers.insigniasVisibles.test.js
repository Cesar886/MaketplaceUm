// Qué insignias muestra un perfil.
//
// Se guarda la lista de insignias OCULTAS, no la de visibles, y estos tests
// fijan la consecuencia que motivó esa decisión: una insignia recién ganada
// aparece sola, sin que su dueño tenga que ir a marcarla, y las cuentas que
// nunca tocaron el ajuste las muestran todas.
//
// El filtrado ocurre en el servidor y no en el cliente: un perfil pedido sin
// sesión (o por cualquier otra cuenta) no debe traer siquiera el booleano de
// una insignia oculta.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-insignias-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');
const { sellers, registerSeller } = require('../data');
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

/** Vendedor con las dos insignias que usan estos tests ya ganadas:
 *  Leyenda (100 ventas) y Vendedor confiable (4.5 con 10 reseñas). */
function crearVendedorCondecorado() {
  const id = `seller_vis_${++contador}`;
  registerSeller({
    id,
    name: `Vis ${id}`,
    avatarInitials: 'VV',
    major: '',
    isBusiness: false,
    verified: true,
    tipo_cuenta: 'estudiante',
    rating: 5,
    reviews: 30,
  });

  const stmt = db.getDb().prepare(
    `INSERT INTO orders (id, buyer_id, vendor_id, amount, status)
     VALUES (?, ?, ?, 100, 'paid')`,
  );
  for (let i = 0; i < 100; i++) stmt.run(`ord_vis_${id}_${i}`, id, id);

  sellers.length = 0;
  sellers.push(...db.getSellers());
  return { id, token: generateToken(id) };
}

async function perfil(id, token) {
  const res = await fetch(`${baseUrl}/api/sellers/${id}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return { status: res.status, body: await res.json() };
}

async function ocultar(id, token, claves) {
  const res = await fetch(`${baseUrl}/api/sellers/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ insigniasOcultas: claves }),
  });
  return { status: res.status, body: await res.json() };
}

test('por defecto un perfil muestra todas las insignias que tiene', async () => {
  const v = crearVendedorCondecorado();

  const { body } = await perfil(v.id);

  assert.strictEqual(body.leyendaMercadito, true);
  assert.strictEqual(body.vendedorConfiable, true);
});

test('una insignia oculta desaparece del perfil público', async () => {
  const v = crearVendedorCondecorado();

  await ocultar(v.id, v.token, ['leyenda']);
  const { body } = await perfil(v.id);

  assert.strictEqual(body.leyendaMercadito, false);
});

test('ocultar una insignia no toca las demás', async () => {
  const v = crearVendedorCondecorado();

  await ocultar(v.id, v.token, ['leyenda']);
  const { body } = await perfil(v.id);

  assert.strictEqual(body.vendedorConfiable, true);
});

test('el dueño ve su perfil como lo ve el resto, no con las ocultas puestas', async () => {
  const v = crearVendedorCondecorado();

  await ocultar(v.id, v.token, ['leyenda']);
  const { body } = await perfil(v.id, v.token);

  assert.strictEqual(body.leyendaMercadito, false);
});

test('el dueño recibe insigniasGanadas con los valores reales, para poder editarlas', async () => {
  const v = crearVendedorCondecorado();

  await ocultar(v.id, v.token, ['leyenda']);
  const { body } = await perfil(v.id, v.token);

  // Sigue siendo suya aunque no se muestre: es lo que la pantalla de
  // selección necesita para pintar el switch encendible.
  assert.strictEqual(body.insigniasGanadas.leyenda, true);
  assert.deepStrictEqual(body.insigniasOcultas, ['leyenda']);
});

test('insigniasGanadas es privado: no viaja en el perfil que ve otra cuenta', async () => {
  const v = crearVendedorCondecorado();
  const otro = crearVendedorCondecorado();

  const anonimo = await perfil(v.id);
  const ajeno = await perfil(v.id, otro.token);

  assert.strictEqual(anonimo.body.insigniasGanadas, undefined);
  assert.strictEqual(ajeno.body.insigniasGanadas, undefined);
});

test('QUÉ insignias escondió alguien tampoco es público', async () => {
  const v = crearVendedorCondecorado();
  const otro = crearVendedorCondecorado();
  await ocultar(v.id, v.token, ['leyenda']);

  // Enseñar la lista de ocultas anularía el punto del ajuste: cualquiera
  // sabría que tiene la Leyenda y que decidió no presumirla.
  assert.strictEqual((await perfil(v.id)).body.insigniasOcultas, undefined);
  assert.strictEqual(
    (await perfil(v.id, otro.token)).body.insigniasOcultas,
    undefined,
  );
});

test('una insignia ganada DESPUÉS de configurar el ajuste aparece sola', async () => {
  const v = crearVendedorCondecorado();
  await ocultar(v.id, v.token, ['leyenda']);

  // Gana "Vendedor de oro" más tarde: como se guardan las ocultas y no las
  // visibles, no hace falta volver al ajuste para que se vea.
  db.getDb()
    .prepare(
      `INSERT INTO orders (id, buyer_id, vendor_id, amount, status)
       VALUES (?, ?, ?, 100000, 'paid')`,
    )
    .run(`ord_oro_${v.id}`, v.id, v.id);

  const { body } = await perfil(v.id);
  assert.strictEqual(body.vendedorDeOro, true);
});

test('volver a mostrar una insignia la devuelve al perfil', async () => {
  const v = crearVendedorCondecorado();

  await ocultar(v.id, v.token, ['leyenda']);
  await ocultar(v.id, v.token, []);
  const { body } = await perfil(v.id);

  assert.strictEqual(body.leyendaMercadito, true);
});

test('se pueden ocultar varias a la vez', async () => {
  const v = crearVendedorCondecorado();

  await ocultar(v.id, v.token, ['leyenda', 'vendedor_confiable']);
  const { body } = await perfil(v.id);

  assert.strictEqual(body.leyendaMercadito, false);
  assert.strictEqual(body.vendedorConfiable, false);
});

// ═══ Validación ══════════════════════════════════════════════

test('una clave de insignia inventada se rechaza con 400', async () => {
  const v = crearVendedorCondecorado();

  const res = await ocultar(v.id, v.token, ['insignia_que_no_existe']);

  assert.strictEqual(res.status, 400);
});

test('claves repetidas se rechazan en vez de guardarse dos veces', async () => {
  const v = crearVendedorCondecorado();

  const res = await ocultar(v.id, v.token, ['leyenda', 'leyenda']);

  assert.strictEqual(res.status, 400);
});

test('insigniasOcultas tiene que ser una lista', async () => {
  const v = crearVendedorCondecorado();

  const res = await ocultar(v.id, v.token, 'leyenda');

  assert.strictEqual(res.status, 400);
});

test('verificado y socio fundador no son ocultables desde aquí', async () => {
  const v = crearVendedorCondecorado();

  // Se pintan también en tarjetas, comentarios y chat: ocultarlas es otra
  // feature con otro alcance, así que su clave no está en el catálogo.
  const res = await ocultar(v.id, v.token, ['verificado']);

  assert.strictEqual(res.status, 400);
});

test('nadie puede cambiar qué insignias muestra el perfil de otro', async () => {
  const v = crearVendedorCondecorado();
  const intruso = crearVendedorCondecorado();

  const res = await ocultar(v.id, intruso.token, ['leyenda']);

  assert.strictEqual(res.status, 403);
  assert.strictEqual((await perfil(v.id)).body.leyendaMercadito, true);
});
