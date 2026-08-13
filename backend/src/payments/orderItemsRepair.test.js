// Reparación de `order_items` con la clave foránea colgando.
//
// Este test parte de una base que YA está rota, que es el estado en el que
// quedó producción: `orders` con el schema actual (así que la migración que
// causó el daño ya no vuelve a correr) y `order_items` referenciando
// "orders_legacy", una tabla que no existe.
//
// Va en un archivo aparte de migrations.test.js a propósito: allí el fixture
// arranca con el schema viejo, y como la migración de `orders` ya no corrompe
// nada, el camino de reparación nunca se ejecutaría. Sin esto, la única
// migración que le sirve al despliegue de hoy quedaría sin probar.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');
const Database = require('better-sqlite3');

const DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-orderitems-')),
  'rota.db',
);

// ─── Fixture: la base tal y como quedó en producción ────────────
{
  const rota = new Database(DB_PATH);
  rota.pragma('foreign_keys = OFF');

  rota.exec(`
    CREATE TABLE sellers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT,
      avatarInitials TEXT,
      major TEXT,
      isBusiness INTEGER DEFAULT 0,
      rating REAL DEFAULT 0,
      reviews INTEGER DEFAULT 0,
      verified INTEGER DEFAULT 0
    );

    -- La tabla orders YA tiene el schema bueno: la migración que rompió
    -- order_items no volverá a correr, así que nada arreglaría la FK sola.
    CREATE TABLE orders (
      id TEXT PRIMARY KEY,
      buyer_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      amount REAL NOT NULL,
      application_fee REAL NOT NULL DEFAULT 0,
      currency TEXT NOT NULL DEFAULT 'MXN',
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending','paid','cancelled','requires_other_method')),
      payment_status TEXT
        CHECK(payment_status IS NULL OR payment_status IN
          ('pending','in_process','approved','authorized','in_mediation',
           'rejected','refunded','cancelled','charged_back')),
      payment_method TEXT
        CHECK(payment_method IS NULL OR payment_method IN
          ('efectivo','paypal','cripto','tarjeta')),
      mp_payment_id TEXT UNIQUE,
      origin TEXT NOT NULL DEFAULT 'direct' CHECK(origin IN ('direct','cart')),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    -- El daño: la FK quedó apuntando a la tabla temporal ya borrada.
    CREATE TABLE order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL REFERENCES "orders_legacy"(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      unit_price REAL NOT NULL,
      title_snapshot TEXT
    );
  `);

  rota.prepare(
    `INSERT INTO sellers (id, name, email, verified) VALUES (?, ?, ?, 1)`,
  ).run('comprador', 'Comprador', 'c@x.com');
  rota.prepare(
    `INSERT INTO sellers (id, name, email, verified) VALUES (?, ?, ?, 1)`,
  ).run('vendedor', 'Vendedor', 'v@x.com');

  rota.prepare(
    `INSERT INTO orders (id, buyer_id, vendor_id, amount, application_fee, status)
     VALUES (?, ?, ?, ?, ?, 'paid')`,
  ).run('ord_historica', 'comprador', 'vendedor', 300, 15);

  // Ventas reales que la reparación NO puede perder.
  rota.prepare(
    `INSERT INTO order_items (order_id, product_id, quantity, unit_price, title_snapshot)
     VALUES (?, ?, ?, ?, ?)`,
  ).run('ord_historica', 'p_viejo', 3, 100, 'Producto histórico');

  rota.close();
}

process.env.MERCADITO_DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'secreto-de-prueba';
process.env.PAYMENTS_ENCRYPTION_KEY = crypto.randomBytes(32).toString('hex');

const db = require('../database');
db.initDatabase();

const sqlDe = (tabla) => db.getDb().prepare(
  `SELECT sql FROM sqlite_master WHERE type='table' AND name=?`,
).get(tabla)?.sql || '';

test('la FK rota se repara y vuelve a apuntar a orders', () => {
  const definicion = sqlDe('order_items');
  assert.ok(
    !definicion.includes('orders_legacy'),
    `sigue apuntando a la tabla fantasma: ${definicion}`,
  );
  assert.match(definicion, /REFERENCES\s+"?orders"?\s*\(/i);
});

test('crear una orden con items deja de dar 500', () => {
  // Exactamente lo que hace store.crearOrden, que es donde reventaba.
  const store = require('./store');
  const orden = store.crearOrden({
    id: 'ord_nueva',
    buyerId: 'comprador',
    vendorId: 'vendedor',
    amount: 100,
    applicationFee: 5,
    currency: 'MXN',
    origin: 'direct',
    items: [{ productId: 'p_1', quantity: 1, unitPrice: 100, title: 'Taco' }],
  });

  assert.ok(orden, 'la orden tiene que crearse');
  assert.strictEqual(orden.items.length, 1);
  assert.strictEqual(orden.items[0].unit_price, 100);
});

test('no se pierde ninguna venta al reconstruir la tabla', () => {
  const items = db.getDb()
    .prepare('SELECT * FROM order_items WHERE order_id = ?').all('ord_historica');
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].title_snapshot, 'Producto histórico');
  assert.strictEqual(items[0].quantity, 3);
  assert.strictEqual(items[0].unit_price, 100);
});

test('el ON DELETE CASCADE sigue vivo tras la reparación', () => {
  db.getDb().pragma('foreign_keys = ON');
  db.getDb().prepare('DELETE FROM orders WHERE id = ?').run('ord_historica');

  const items = db.getDb()
    .prepare('SELECT * FROM order_items WHERE order_id = ?').all('ord_historica');
  assert.strictEqual(items.length, 0,
    'reconstruir la tabla sin conservar el CASCADE dejaría items huérfanos');
});

test('reparar es idempotente: correrlo de nuevo no toca nada', () => {
  const antes = sqlDe('order_items');
  db.initDatabase();
  assert.strictEqual(sqlDe('order_items'), antes);
});
