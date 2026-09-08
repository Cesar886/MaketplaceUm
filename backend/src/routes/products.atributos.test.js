// Tests de extremo a extremo de las preguntas dinámicas por categoría.
//
// La validación pura vive en validation/atributosCategoria.test.js. Aquí se
// protege lo que solo se rompe al cruzar las tres capas que tiene un producto
// en este proyecto (columna SQLite ↔ array en memoria de data.js ↔ JSON de la
// ruta):
//
//  1. Que las respuestas SOBREVIVAN A saveData(). El upsert de insertProduct
//     enumera columnas a mano: olvidar `atributos_categoria` ahí no rompe
//     ningún test de validación, pero borra las respuestas de cada producto
//     en el siguiente guardado del catálogo.
//  2. Que `atributos` viaje en las TRES respuestas (listado, búsqueda y
//     detalle) con la misma forma, para que el cliente no mapee distinto
//     según de dónde venga la tarjeta.
//  3. Que cambiar de categoría no deje colgando atributos de la anterior.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-atributos-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');

db.initDatabase();

// Los casos de migración insertan filas a mano; desde que existe moderación
// también deben apuntar a una cuenta activa para ser legibles públicamente.
db.getDb().prepare(`
  INSERT INTO sellers (id, name, avatarInitials, admin_status)
  VALUES ('v_x', 'Vendedor legado', 'VL', 'active')
`).run();

const { products, saveData } = require('../data');
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

function crearVendedor() {
  const id = `v_${++contador}`;
  db.getDb().prepare(`
    INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta)
    VALUES (?, ?, ?, 'VV', '', 0, 1, 'estudiante')
  `).run(id, `Vendedor ${id}`, `${id}@ejemplo.com`);
  return { id, token: generateToken(id) };
}

async function publicar(vendedor, cuerpo) {
  const res = await fetch(`${baseUrl}/api/products`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${vendedor.token}`,
    },
    body: JSON.stringify({
      title: `Producto ${++contador}`,
      price: '100',
      category: 'books',
      description: 'descripción de prueba',
      stock_quantity: 3,
      ...cuerpo,
    }),
  });
  return { status: res.status, body: await res.json() };
}

async function editar(vendedor, id, cuerpo) {
  const res = await fetch(`${baseUrl}/api/products/${id}`, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${vendedor.token}`,
    },
    body: JSON.stringify(cuerpo),
  });
  return { status: res.status, body: await res.json() };
}

// ─── Migración ───────────────────────────────────────────────

test('la migración deja la columna atributos_categoria en products', () => {
  const cols = db.getDb().prepare("PRAGMA table_info('products')").all();
  const col = cols.find(c => c.name === 'atributos_categoria');
  assert.ok(col, 'falta la columna');
  assert.strictEqual(col.type, 'TEXT');
});

test('un producto anterior a la migración se lee con atributos vacíos', () => {
  // Insertado sin tocar la columna: es exactamente lo que hay en la base de
  // producción hoy. Tiene que leerse como {} y no como null/undefined, o
  // cada lector necesitaría su propio chequeo defensivo.
  const id = `viejo_${++contador}`;
  db.getDb().prepare(`
    INSERT INTO products (id, title, price, priceNum, category, description, seller, created_at)
    VALUES (?, 'Viejo', '50', 50, 'books', 'desc', 'v_x', datetime('now'))
  `).run(id);
  assert.deepStrictEqual(db.getProductById(id).atributos, {});
});

test('un JSON corrupto en la columna no tumba la lectura del catálogo', () => {
  // getAllProducts corre al importar data.js: una fila mala dejaría al
  // servidor entero sin arrancar.
  const id = `corrupto_${++contador}`;
  db.getDb().prepare(`
    INSERT INTO products (id, title, price, priceNum, category, description, seller, created_at, atributos_categoria)
    VALUES (?, 'Corrupto', '50', 50, 'books', 'desc', 'v_x', datetime('now'), '{no soy json')
  `).run(id);
  assert.deepStrictEqual(db.getProductById(id).atributos, {});
  assert.doesNotThrow(() => db.getAllProducts());
});

// ─── Crear ───────────────────────────────────────────────────

test('publicar guarda las respuestas y las devuelve parseadas', async () => {
  const vendedor = crearVendedor();
  const { status, body } = await publicar(vendedor, {
    category: 'books',
    atributos: {
      edicion: 'Original',
      estado_libro: 'Buen estado',
      precio_negociable: true,
      lugar_entrega: 'Campus',
    },
  });

  assert.strictEqual(status, 201);
  assert.deepStrictEqual(body.atributos, {
    precio_negociable: true,
    lugar_entrega: 'Campus',
    edicion: 'Original',
    estado_libro: 'Buen estado',
  });
});

test('publicar sin atributos deja un objeto vacío, nunca null', async () => {
  const vendedor = crearVendedor();
  const { status, body } = await publicar(vendedor, {});
  assert.strictEqual(status, 201);
  assert.deepStrictEqual(body.atributos, {});
  assert.deepStrictEqual(body.atributosDestacados, []);
});

test('publicar con un valor fuera del catálogo se rechaza con 400', async () => {
  const vendedor = crearVendedor();
  const { status, body } = await publicar(vendedor, {
    category: 'books',
    atributos: { edicion: 'Pirata' },
  });
  assert.strictEqual(status, 400);
  assert.match(body.error, /Opción inválida/);
});

test('publicar ignora respuestas que no son de esa categoría', async () => {
  const vendedor = crearVendedor();
  const { body } = await publicar(vendedor, {
    category: 'books',
    atributos: { edicion: 'Original', talla: 'M' },
  });
  assert.deepStrictEqual(body.atributos, { edicion: 'Original' });
});

test('las respuestas llegan a SQLite, no solo al array en memoria', async () => {
  const vendedor = crearVendedor();
  const { body } = await publicar(vendedor, {
    category: 'clothes',
    atributos: { talla: 'M', marca: 'Nike' },
  });

  const fila = db.getDb()
    .prepare('SELECT atributos_categoria FROM products WHERE id = ?')
    .get(body.id);
  assert.deepStrictEqual(JSON.parse(fila.atributos_categoria), {
    talla: 'M',
    marca: 'Nike',
  });
});

test('un producto sin respuestas guarda NULL, no la cadena "{}"', async () => {
  const vendedor = crearVendedor();
  const { body } = await publicar(vendedor, {});
  const fila = db.getDb()
    .prepare('SELECT atributos_categoria FROM products WHERE id = ?')
    .get(body.id);
  assert.strictEqual(fila.atributos_categoria, null);
});

test('las respuestas sobreviven a saveData()', async () => {
  // saveData() hace upsert de TODO el catálogo en cada guardado. Si el
  // INSERT de insertProduct no enumera la columna nueva, este es el único
  // test que lo nota — y en producción se traduce en respuestas que
  // desaparecen solas cuando alguien más publica.
  const vendedor = crearVendedor();
  const { body } = await publicar(vendedor, {
    category: 'housing',
    atributos: { incluye_renta: ['Luz', 'Internet'], acepta_mascotas: true },
  });

  saveData();

  assert.deepStrictEqual(db.getProductById(body.id).atributos, {
    incluye_renta: ['Luz', 'Internet'],
    acepta_mascotas: true,
  });
});

// ─── Leer: listado, detalle y búsqueda ───────────────────────

test('atributos y destacados viajan en el listado, la búsqueda y el detalle', async () => {
  const vendedor = crearVendedor();
  const { body: creado } = await publicar(vendedor, {
    title: 'Sudadera Kombucha',
    category: 'clothes',
    atributos: { talla: 'L', estado_ropa: 'Poco uso', marca: 'Nike' },
  });

  const listado = await (await fetch(`${baseUrl}/api/products`)).json();
  const busqueda = await (
    await fetch(`${baseUrl}/api/products?search=Kombucha`)
  ).json();
  const detalle = await (await fetch(`${baseUrl}/api/products/${creado.id}`)).json();

  const enListado = listado.find(p => p.id === creado.id);
  const enBusqueda = busqueda.find(p => p.id === creado.id);

  for (const [nombre, item] of [
    ['listado', enListado],
    ['búsqueda', enBusqueda],
    ['detalle', detalle],
  ]) {
    assert.deepStrictEqual(
      item.atributos,
      { talla: 'L', marca: 'Nike', estado_ropa: 'Poco uso' },
      `los atributos no llegaron igual en ${nombre}`,
    );
    assert.deepStrictEqual(
      item.atributosDestacados.map(d => d.value),
      ['L', 'Poco uso'],
      `los destacados no llegaron igual en ${nombre}`,
    );
  }
});

test('los carruseles del detalle traen atributos como cualquier tarjeta', async () => {
  const vendedor = crearVendedor();
  const { body: uno } = await publicar(vendedor, {
    category: 'books',
    atributos: { estado_libro: 'Nuevo' },
  });
  const { body: dos } = await publicar(vendedor, { category: 'books' });

  const detalle = await (await fetch(`${baseUrl}/api/products/${dos.id}`)).json();
  const enCarrusel = detalle.sellerOtherProducts.find(p => p.id === uno.id);

  assert.ok(enCarrusel, 'el producto del mismo vendedor debería estar en el carrusel');
  assert.deepStrictEqual(enCarrusel.atributos, { estado_libro: 'Nuevo' });
  assert.deepStrictEqual(enCarrusel.atributosDestacados.map(d => d.value), ['Nuevo']);
});

// ─── Filtro de búsqueda ──────────────────────────────────────

test('la búsqueda filtra por atributo', async () => {
  const vendedor = crearVendedor();
  const { body: chica } = await publicar(vendedor, {
    title: 'Playera Zonzo S',
    category: 'clothes',
    atributos: { talla: 'S' },
  });
  const { body: grande } = await publicar(vendedor, {
    title: 'Playera Zonzo XL',
    category: 'clothes',
    atributos: { talla: 'XL' },
  });

  const filtro = encodeURIComponent(JSON.stringify({ talla: 'S' }));
  const res = await (
    await fetch(`${baseUrl}/api/products?search=Zonzo&atributos=${filtro}`)
  ).json();

  const ids = res.map(p => p.id);
  assert.ok(ids.includes(chica.id));
  assert.ok(!ids.includes(grande.id));
});

test('el filtro acepta varios valores para la misma key (OR)', async () => {
  const vendedor = crearVendedor();
  await publicar(vendedor, {
    title: 'Libro Ñandú A',
    category: 'books',
    atributos: { estado_libro: 'Nuevo' },
  });
  await publicar(vendedor, {
    title: 'Libro Ñandú B',
    category: 'books',
    atributos: { estado_libro: 'Como nuevo' },
  });
  await publicar(vendedor, {
    title: 'Libro Ñandú C',
    category: 'books',
    atributos: { estado_libro: 'Con detalles/subrayado' },
  });

  const filtro = encodeURIComponent(
    JSON.stringify({ estado_libro: ['Nuevo', 'Como nuevo'] }),
  );
  const res = await (
    await fetch(`${baseUrl}/api/products?search=Ñandú&atributos=${filtro}`)
  ).json();

  assert.strictEqual(res.length, 2);
});

test('el filtro sobre un multiselect casa si la lista contiene el valor', async () => {
  const vendedor = crearVendedor();
  await publicar(vendedor, {
    title: 'Cuarto Bergamota',
    category: 'housing',
    atributos: { incluye_renta: ['Luz', 'Internet'] },
  });

  const filtro = encodeURIComponent(JSON.stringify({ incluye_renta: 'Internet' }));
  const res = await (
    await fetch(`${baseUrl}/api/products?search=Bergamota&atributos=${filtro}`)
  ).json();
  assert.strictEqual(res.length, 1);
});

test('un producto que nunca respondió la pregunta no pasa el filtro', async () => {
  const vendedor = crearVendedor();
  await publicar(vendedor, { title: 'Libro Trapecio', category: 'books' });

  const filtro = encodeURIComponent(JSON.stringify({ estado_libro: 'Nuevo' }));
  const res = await (
    await fetch(`${baseUrl}/api/products?search=Trapecio&atributos=${filtro}`)
  ).json();
  assert.strictEqual(res.length, 0);
});

test('un filtro con JSON inválido se ignora en vez de vaciar la búsqueda', async () => {
  const vendedor = crearVendedor();
  await publicar(vendedor, { title: 'Libro Malabar', category: 'books' });

  const res = await (
    await fetch(`${baseUrl}/api/products?search=Malabar&atributos=%7Bno-json`)
  ).json();
  assert.strictEqual(res.length, 1);
});

// ─── Editar ──────────────────────────────────────────────────

test('editar reemplaza las respuestas por completo', async () => {
  const vendedor = crearVendedor();
  const { body: creado } = await publicar(vendedor, {
    category: 'books',
    atributos: { edicion: 'Original', estado_libro: 'Nuevo' },
  });

  const { status, body } = await editar(vendedor, creado.id, {
    title: creado.title,
    category: 'books',
    description: creado.description,
    atributos: { estado_libro: 'Buen estado' },
  });

  assert.strictEqual(status, 200);
  assert.deepStrictEqual(body.atributos, { estado_libro: 'Buen estado' });
});

test('editar sin mandar atributos no los toca', async () => {
  const vendedor = crearVendedor();
  const { body: creado } = await publicar(vendedor, {
    category: 'books',
    atributos: { edicion: 'Original' },
  });

  const { body } = await editar(vendedor, creado.id, {
    title: 'Otro título',
    category: 'books',
    description: creado.description,
  });

  assert.deepStrictEqual(body.atributos, { edicion: 'Original' });
});

test('cambiar de categoría descarta las respuestas que ya no aplican', async () => {
  // Sin esto, un producto que pasó de Ropa a Electrónicos se queda con una
  // talla guardada para siempre: invisible en la UI pero viva en la base, y
  // reaparecería si algún día alguien vuelve a poner la categoría original.
  const vendedor = crearVendedor();
  const { body: creado } = await publicar(vendedor, {
    category: 'clothes',
    atributos: { talla: 'M', precio_negociable: true },
  });

  const { body } = await editar(vendedor, creado.id, {
    title: creado.title,
    category: 'electronics',
    description: creado.description,
  });

  assert.deepStrictEqual(body.atributos, { precio_negociable: true });

  const fila = db.getDb()
    .prepare('SELECT atributos_categoria FROM products WHERE id = ?')
    .get(creado.id);
  assert.ok(!String(fila.atributos_categoria).includes('talla'));
});

test('editar con un valor inválido se rechaza sin guardar nada', async () => {
  const vendedor = crearVendedor();
  const { body: creado } = await publicar(vendedor, {
    title: 'Título original',
    category: 'books',
    atributos: { edicion: 'Original' },
  });

  const { status } = await editar(vendedor, creado.id, {
    title: 'Título nuevo',
    category: 'books',
    description: creado.description,
    atributos: { edicion: 'Pirata' },
  });

  assert.strictEqual(status, 400);
  // El 400 sale antes de tocar el producto: el título tampoco cambió.
  assert.strictEqual(products.find(p => p.id === creado.id).title, 'Título original');
});
