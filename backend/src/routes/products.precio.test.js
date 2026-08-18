// Edición de precio: cuándo se marca (y cuándo NO) un producto como oferta.
//
// El bug que originó estos tests: un producto de $5 se editó a $7,500 y la
// app lo pintó "en oferta", con $11,000 tachado y un badge de -32%. Nadie
// activó ninguna oferta: solo se subió el precio. El descuento salía de
// comparar el precio nuevo contra el MÁXIMO histórico de 30 días en vez de
// contra el precio que el producto tenía justo antes de la edición.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-precio-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');

db.initDatabase();

const { products } = require('../data');
const { register } = require('./products');
const { generateToken } = require('../auth');

const DUENO = 's_dueno';
let baseUrl;
let servidor;
let token;

test.before(async () => {
  const app = express();
  app.use(express.json());
  register(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
  token = generateToken(DUENO);
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

let contador = 0;

/** Siembra el producto en la tabla y en el array en memoria (ver data.js). */
function sembrarProducto({ price }) {
  const id = `pr_${++contador}`;
  db.getDb().prepare(`
    INSERT INTO products (id, title, price, priceNum, category, description, seller, created_at)
    VALUES (@id, @title, @price, @priceNum, 'cat_x', 'desc', @seller, datetime('now'))
  `).run({ id, title: `Producto${contador}`, price: String(price), priceNum: price, seller: DUENO });
  const producto = db.getProductById(id);
  products.push(producto);
  return producto;
}

/**
 * Escribe a mano una entrada de historial con antigüedad controlada.
 * `insertPriceHistory` siempre estampa `now`, y estos casos necesitan que el
 * cambio anterior quede fuera del cooldown de 72h para que la rama de oferta
 * llegue a evaluarse.
 */
function sembrarHistorial(productId, price, hace_horas) {
  db.getDb().prepare(`
    INSERT INTO price_history (product_id, price, changed_at)
    VALUES (?, ?, datetime('now', ?))
  `).run(productId, price, `-${hace_horas} hours`);
}

async function editarPrecio(id, price) {
  const res = await fetch(`${baseUrl}/api/products/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ price }),
  });
  return { status: res.status, body: await res.json() };
}

test('subir el precio no genera oferta aunque el histórico de 30d sea más alto', async () => {
  // La reproducción exacta del reporte: el producto llegó a $11,000 hace
  // semanas, hoy está en $5, y el dueño lo sube a $7,500.
  const producto = sembrarProducto({ price: 5 });
  sembrarHistorial(producto.id, 11000, 24 * 20);
  sembrarHistorial(producto.id, 5, 24 * 10);

  const { status, body } = await editarPrecio(producto.id, 7500);

  assert.strictEqual(status, 200);
  assert.strictEqual(body.price, 7500);
  assert.strictEqual(body.isOffer, false, 'subir el precio se marcó como oferta');
  assert.strictEqual(body.previousPrice, null, 'quedó un precio tachado fantasma');
  assert.strictEqual(body.discountLabel, null, 'quedó un badge de descuento fantasma');
  assert.strictEqual(body.offerExpiresAt, null);
});

test('bajar el precio sí genera oferta contra el precio inmediatamente anterior', async () => {
  const producto = sembrarProducto({ price: 1000 });
  sembrarHistorial(producto.id, 1000, 24 * 10);

  const { status, body } = await editarPrecio(producto.id, 700);

  assert.strictEqual(status, 200);
  assert.strictEqual(body.isOffer, true, 'una baja real de 30% debe seguir siendo oferta');
  assert.strictEqual(body.previousPrice, 1000, 'el tachado es el precio anterior real');
  assert.strictEqual(body.discountLabel, '-30%');
});

test('una baja menor al umbral del 5% no marca oferta', async () => {
  const producto = sembrarProducto({ price: 1000 });
  sembrarHistorial(producto.id, 1000, 24 * 10);

  const { body } = await editarPrecio(producto.id, 980);

  assert.strictEqual(body.isOffer, false);
  assert.strictEqual(body.previousPrice, null);
  assert.strictEqual(body.discountLabel, null);
});

test('editar el precio limpia la oferta anterior en vez de arrastrarla', async () => {
  // Producto que ya venía marcado en oferta; al reeditar el precio hacia
  // arriba, los campos de oferta tienen que quedar en null y no persistir
  // con los valores viejos.
  const producto = sembrarProducto({ price: 700 });
  sembrarHistorial(producto.id, 1000, 24 * 10);
  const enMemoria = products.find(p => p.id === producto.id);
  Object.assign(enMemoria, {
    isOffer: true,
    previousPrice: 1000,
    discountLabel: '-30%',
    offerExpiresAt: new Date(Date.now() + 86400000).toISOString(),
  });

  const { body } = await editarPrecio(producto.id, 900);

  assert.strictEqual(body.isOffer, false);
  assert.strictEqual(body.previousPrice, null);
  assert.strictEqual(body.discountLabel, null);
  assert.strictEqual(body.offerExpiresAt, null);
});
