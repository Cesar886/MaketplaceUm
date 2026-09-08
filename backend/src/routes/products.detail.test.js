// Tests del detalle de producto con sus dos carruseles.
//
// Lo que se protege aquí no es el algoritmo (eso vive en
// database.related.test.js) sino el CONTRATO con el cliente:
//
//  1. Que `relatedProducts` y `sellerOtherProducts` traigan exactamente el
//     mismo shape que el resto de la app usa para poblar ProductCard. Si un
//     campo faltara, el síntoma en Flutter no sería un error de compilación:
//     sería una tarjeta sin precio o sin vendedor dentro del carrusel.
//  2. Que vacío sea `[]` y nunca `null`, para que la pantalla oculte la
//     sección con un `isEmpty` y no con chequeos de nulos repartidos.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-detalle-')),
  'test.db',
);
// auth.js revienta al cargarse si no hay JWT_SECRET (a propósito: ver el
// comentario ahí). Este archivo solo llama endpoints públicos, pero el
// require del router lo arrastra igual.
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');

db.initDatabase();

const { products } = require('../data');
const { register } = require('./products');

let baseUrl;
let servidor;

test.before(async () => {
  const app = express();
  app.use(express.json());
  register(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

let contador = 0;

/**
 * Siembra un producto en la tabla (de donde salen los carruseles) y en el
 * array en memoria (de donde la ruta resuelve el detalle). Los dos, porque
 * así es como funciona la app: `data.js` mantiene el catálogo cacheado.
 */
function sembrarProducto({ id, category = 'cat_x', seller = 's_x' } = {}) {
  const n = ++contador;
  const productId = id || `d_${n}`;
  db.getDb().prepare(`
    INSERT OR IGNORE INTO sellers (id, name, avatarInitials, admin_status)
    VALUES (?, ?, 'DP', 'active')
  `).run(seller, `Detalle ${seller}`);
  db.getDb().prepare(`
    INSERT INTO products (id, title, price, priceNum, category, description, seller, created_at)
    VALUES (@id, @title, '100', 100, @category, 'desc', @seller, datetime('now'))
  `).run({ id: productId, title: `Xilofono${n}`, category, seller });

  // Se relee de la base en vez de armar el objeto a mano: así el array en
  // memoria contiene exactamente lo que `data.js` cargaría al arrancar, que
  // es contra lo que este test compara shapes.
  const producto = db.getProductById(productId);
  products.push(producto);
  return producto;
}

async function pedirDetalle(id) {
  const res = await fetch(`${baseUrl}/api/products/${id}`);
  return { status: res.status, body: await res.json() };
}

test('el detalle incluye ambos carruseles con el shape del feed', async () => {
  const actual = sembrarProducto({ id: 'det_actual', category: 'cat_det', seller: 's_dueno' });
  const relacionado = sembrarProducto({ id: 'det_rel', category: 'cat_det', seller: 's_ajeno' });
  const delVendedor = sembrarProducto({ id: 'det_vend', category: 'cat_otra', seller: 's_dueno' });

  const { status, body } = await pedirDetalle(actual.id);
  assert.strictEqual(status, 200);

  assert.deepStrictEqual(body.relatedProducts.map(p => p.id), [relacionado.id]);
  assert.deepStrictEqual(body.sellerOtherProducts.map(p => p.id), [delVendedor.id]);

  // El shape se compara contra el que sirve GET /api/products, que es el que
  // ya alimenta las tarjetas del home: mismo juego de campos, sin extras ni
  // faltantes que obliguen a mapear distinto en el cliente.
  const listado = await (await fetch(`${baseUrl}/api/products`)).json();
  const referencia = listado.find(p => p.id === relacionado.id);

  assert.deepStrictEqual(
    Object.keys(body.relatedProducts[0]).sort(),
    Object.keys(referencia).sort(),
  );
  assert.deepStrictEqual(
    Object.keys(body.sellerOtherProducts[0]).sort(),
    Object.keys(referencia).sort(),
  );

  // Y los campos que la tarjeta lee de verdad vienen poblados, no en null.
  const tarjeta = body.relatedProducts[0];
  assert.strictEqual(typeof tarjeta.price, 'number');
  assert.ok(tarjeta.sellerObj, 'sin sellerObj la tarjeta no puede pintar al vendedor');
  assert.ok(Object.hasOwn(tarjeta, 'computed_status'));
  assert.ok(Object.hasOwn(tarjeta, 'productRating'));
});

test('sin relacionados ni otros productos, los arrays llegan vacíos y no null', async () => {
  const solo = sembrarProducto({ id: 'det_solo', category: 'cat_solo', seller: 's_solo' });

  const { body } = await pedirDetalle(solo.id);

  assert.deepStrictEqual(body.relatedProducts, []);
  assert.deepStrictEqual(body.sellerOtherProducts, []);
});

test('el producto actual nunca aparece en sus propios carruseles', async () => {
  const actual = sembrarProducto({ id: 'det_yo', category: 'cat_yo', seller: 's_yo' });
  sembrarProducto({ id: 'det_yo_2', category: 'cat_yo', seller: 's_yo' });

  const { body } = await pedirDetalle(actual.id);

  const todos = [...body.relatedProducts, ...body.sellerOtherProducts].map(p => p.id);
  assert.ok(!todos.includes(actual.id));
});

test('un producto que no existe sigue devolviendo 404', async () => {
  const { status } = await pedirDetalle('no_existe');
  assert.strictEqual(status, 404);
});
