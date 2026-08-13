// Migraciones del modelo de pagos hacia "Customer por vendedor".
//
// Se construye a mano una base con el schema VIEJO y datos dentro, y luego se
// deja que initDatabase() corra las migraciones reales encima. Es la única
// forma de probar que un despliegue existente sobrevive: un test que arranca
// de una base vacía valida el CREATE TABLE, no la migración.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');
const Database = require('better-sqlite3');

const DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-migraciones-')),
  'legacy.db',
);

// ─── Fixture: la base tal y como está HOY en producción ─────────
{
  const legacy = new Database(DB_PATH);
  legacy.pragma('foreign_keys = OFF');

  // `sellers` con la forma real (la de .schema en producción), para que las
  // migraciones condicionales de esa tabla no tengan nada que hacer y no
  // interfieran con lo que se está probando aquí.
  legacy.exec(`
    CREATE TABLE sellers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT,
      phone TEXT,
      avatarInitials TEXT,
      major TEXT,
      isBusiness INTEGER DEFAULT 0,
      logoUrl TEXT,
      rating REAL DEFAULT 0,
      reviews INTEGER DEFAULT 0,
      verified INTEGER DEFAULT 0,
      businessDescription TEXT, businessCategory TEXT, password_hash TEXT,
      failed_login_attempts INTEGER DEFAULT 0, locked_until TEXT,
      businessHours TEXT, location_lat REAL, location_lng REAL,
      paymentMethods TEXT, tipo_cuenta TEXT, carrera TEXT,
      tipo_verificacion TEXT, colorAcento TEXT, producto_fijado_id TEXT,
      median_response_minutes INTEGER
    );

    CREATE TABLE vendor_payment_accounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      seller_id TEXT NOT NULL UNIQUE REFERENCES sellers(id) ON DELETE CASCADE,
      mp_user_id TEXT NOT NULL,
      mp_access_token_enc TEXT NOT NULL,
      mp_refresh_token_enc TEXT,
      mp_token_expires_at TEXT,
      mp_public_key TEXT,
      connected_at TEXT NOT NULL DEFAULT (datetime('now')),
      revoked_at TEXT
    );

    CREATE TABLE buyer_mp_customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      seller_id TEXT NOT NULL UNIQUE REFERENCES sellers(id) ON DELETE CASCADE,
      mp_customer_id TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE saved_cards (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      mp_card_id TEXT NOT NULL,
      last_four_digits TEXT,
      payment_method TEXT,
      expiration_month INTEGER,
      expiration_year INTEGER,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(seller_id, mp_card_id)
    );
    CREATE INDEX idx_saved_cards_seller ON saved_cards(seller_id);

    CREATE TABLE orders (
      id TEXT PRIMARY KEY,
      buyer_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      amount REAL NOT NULL,
      application_fee REAL NOT NULL DEFAULT 0,
      currency TEXT NOT NULL DEFAULT 'MXN',
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending','paid','cancelled')),
      payment_status TEXT
        CHECK(payment_status IS NULL OR payment_status IN
          ('pending','in_process','approved','rejected','refunded','cancelled','charged_back')),
      mp_payment_id TEXT UNIQUE,
      origin TEXT NOT NULL DEFAULT 'direct' CHECK(origin IN ('direct','cart')),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      unit_price REAL NOT NULL,
      title_snapshot TEXT
    );
  `);

  const seller = legacy.prepare(
    `INSERT INTO sellers (id, name, email, tipo_cuenta, paymentMethods, verified)
     VALUES (?, ?, ?, ?, ?, 1)`,
  );
  // Cada uno cubre un caso distinto de la purga de 'transferencia'.
  seller.run('v_mixto', 'Mixto', 'mixto@x.com', 'negocio',
    JSON.stringify(['efectivo', 'transferencia', 'paypal']));
  seller.run('v_solo_transf', 'Solo transferencia', 'solo@x.com', 'negocio',
    JSON.stringify(['transferencia']));
  seller.run('v_sin_transf', 'Sin transferencia', 'sin@x.com', 'estudiante',
    JSON.stringify(['efectivo']));
  seller.run('v_nulo', 'Sin métodos', 'nulo@x.com', 'estudiante', null);
  seller.run('comprador', 'Comprador', 'c@x.com', 'estudiante', JSON.stringify(['efectivo']));

  legacy.prepare(
    `INSERT INTO vendor_payment_accounts
       (seller_id, mp_user_id, mp_access_token_enc, connected_at, revoked_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run('v_mixto', 'mp_1', 'enc-token', '2026-01-01T00:00:00Z', null);
  legacy.prepare(
    `INSERT INTO vendor_payment_accounts
       (seller_id, mp_user_id, mp_access_token_enc, connected_at, revoked_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run('v_solo_transf', 'mp_2', 'enc-token-2', '2026-01-02T00:00:00Z', '2026-02-01T00:00:00Z');

  // Customer y tarjeta creados bajo la PLATAFORMA: inservibles en el modelo
  // nuevo, se descartan.
  legacy.prepare(
    'INSERT INTO buyer_mp_customers (seller_id, mp_customer_id) VALUES (?, ?)',
  ).run('comprador', 'cus_plataforma_1');
  legacy.prepare(
    `INSERT INTO saved_cards (seller_id, mp_card_id, last_four_digits, payment_method)
     VALUES (?, ?, ?, ?)`,
  ).run('comprador', 'card_plataforma_1', '4242', 'visa');

  legacy.prepare(
    `INSERT INTO orders (id, buyer_id, vendor_id, amount, application_fee, status, payment_status, mp_payment_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run('ord_legacy', 'comprador', 'v_mixto', 250.5, 12.53, 'paid', 'approved', 'pay_legacy');
  legacy.prepare(
    `INSERT INTO order_items (order_id, product_id, quantity, unit_price, title_snapshot)
     VALUES (?, ?, ?, ?, ?)`,
  ).run('ord_legacy', 'p_1', 1, 250.5, 'Producto histórico');

  legacy.close();
}

// Las migraciones corren aquí, al requerir e inicializar sobre esa base.
process.env.MERCADITO_DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'secreto-de-prueba';
process.env.PAYMENTS_ENCRYPTION_KEY = crypto.randomBytes(32).toString('hex');

const db = require('../database');
db.initDatabase();

const sql = (tabla) => db.getDb().prepare(
  `SELECT sql FROM sqlite_master WHERE type='table' AND name=?`,
).get(tabla)?.sql || '';

const columnas = (tabla) => db.getDb()
  .prepare(`PRAGMA table_info('${tabla}')`).all().map(c => c.name);

// ─── M1: vendor_payment_accounts ────────────────────────────────

test('M1 · vendor_payment_accounts gana provider y motivo de desconexión', () => {
  const cols = columnas('vendor_payment_accounts');
  assert.ok(cols.includes('provider'), 'falta provider');
  assert.ok(cols.includes('disconnect_reason'), 'falta disconnect_reason');
  assert.ok(cols.includes('disconnected_by'), 'falta disconnected_by');
});

test('M1 · las cuentas existentes quedan como mercadopago sin perder su estado', () => {
  const filas = db.getDb()
    .prepare('SELECT * FROM vendor_payment_accounts ORDER BY seller_id').all();
  assert.strictEqual(filas.length, 2, 'no se debió perder ninguna cuenta conectada');

  const mixto = filas.find(f => f.seller_id === 'v_mixto');
  assert.strictEqual(mixto.provider, 'mercadopago');
  assert.strictEqual(mixto.mp_user_id, 'mp_1');
  assert.strictEqual(mixto.mp_access_token_enc, 'enc-token');
  assert.strictEqual(mixto.revoked_at, null, 'seguía conectado');

  // revoked_at es la fuente de verdad del estado y no se toca.
  const revocado = filas.find(f => f.seller_id === 'v_solo_transf');
  assert.strictEqual(revocado.revoked_at, '2026-02-01T00:00:00Z');
});

test('M1 · un vendedor puede tener una cuenta por proveedor, no solo una en total', () => {
  const definicion = sql('vendor_payment_accounts');
  assert.ok(
    !/seller_id\s+TEXT\s+NOT NULL\s+UNIQUE/i.test(definicion),
    'el UNIQUE de una sola columna impediría añadir otro proveedor a futuro',
  );

  // La prueba real: insertar el mismo vendedor con otro provider debe poder.
  db.getDb().prepare(
    `INSERT INTO vendor_payment_accounts (seller_id, provider, mp_user_id, mp_access_token_enc)
     VALUES (?, ?, ?, ?)`,
  ).run('v_mixto', 'otro_proveedor', 'ext_1', 'enc-x');

  assert.throws(
    () => db.getDb().prepare(
      `INSERT INTO vendor_payment_accounts (seller_id, provider, mp_user_id, mp_access_token_enc)
       VALUES (?, ?, ?, ?)`,
    ).run('v_mixto', 'mercadopago', 'mp_dup', 'enc-y'),
    /UNIQUE/,
    'pero dos cuentas del MISMO proveedor para el mismo vendedor siguen prohibidas',
  );

  db.getDb().prepare(
    `DELETE FROM vendor_payment_accounts WHERE provider = 'otro_proveedor'`,
  ).run();
});

// ─── M2: orders ─────────────────────────────────────────────────

test('M2 · orders gana payment_method y conserva el histórico', () => {
  assert.ok(columnas('orders').includes('payment_method'), 'falta payment_method');

  const orden = db.getDb().prepare('SELECT * FROM orders WHERE id = ?').get('ord_legacy');
  assert.ok(orden, 'la orden histórica no puede desaparecer en la migración');
  assert.strictEqual(orden.amount, 250.5);
  assert.strictEqual(orden.payment_status, 'approved');
  assert.strictEqual(orden.mp_payment_id, 'pay_legacy');

  const items = db.getDb().prepare('SELECT * FROM order_items WHERE order_id = ?').all('ord_legacy');
  assert.strictEqual(items.length, 1, 'los items no pueden perderse por el rebuild');
  assert.strictEqual(items[0].title_snapshot, 'Producto histórico');
});

test('M2 · orders acepta el estado requires_other_method', () => {
  db.getDb().prepare(
    `INSERT INTO orders (id, buyer_id, vendor_id, amount, status, payment_method)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).run('ord_otro_metodo', 'comprador', 'v_mixto', 10, 'requires_other_method', 'tarjeta');

  assert.strictEqual(
    db.getDb().prepare('SELECT status FROM orders WHERE id = ?').get('ord_otro_metodo').status,
    'requires_other_method',
  );
});

test('M2 · orders sigue aceptando authorized e in_mediation', () => {
  for (const estado of ['authorized', 'in_mediation']) {
    db.getDb().prepare(
      `INSERT INTO orders (id, buyer_id, vendor_id, amount, payment_status)
       VALUES (?, ?, ?, ?, ?)`,
    ).run(`ord_${estado}`, 'comprador', 'v_mixto', 10, estado);
  }
  assert.ok(true);
});

test('M2 · un payment_method inventado se rechaza en el esquema', () => {
  assert.throws(
    () => db.getDb().prepare(
      `INSERT INTO orders (id, buyer_id, vendor_id, amount, payment_method)
       VALUES (?, ?, ?, ?, ?)`,
    ).run('ord_malo', 'comprador', 'v_mixto', 10, 'trueque'),
    /CHECK/,
  );
});

// ─── M3 y M4: Customer y tarjetas por vendedor ──────────────────

test('M3 · buyer_mp_customers pasa a ser por (comprador, vendedor)', () => {
  assert.ok(columnas('buyer_mp_customers').includes('vendor_id'), 'falta vendor_id');

  // El Customer viejo se creó bajo la plataforma: en el modelo nuevo no sirve
  // para cobrar con el token de ningún vendedor, así que se descarta.
  assert.strictEqual(
    db.getDb().prepare('SELECT COUNT(*) n FROM buyer_mp_customers').get().n, 0,
    'los Customers de plataforma son inservibles y deben quedar descartados',
  );

  const ins = db.getDb().prepare(
    'INSERT INTO buyer_mp_customers (seller_id, vendor_id, mp_customer_id) VALUES (?, ?, ?)',
  );
  ins.run('comprador', 'v_mixto', 'cus_a');
  ins.run('comprador', 'v_sin_transf', 'cus_b'); // mismo comprador, otro vendedor: válido

  assert.throws(
    () => ins.run('comprador', 'v_mixto', 'cus_dup'),
    /UNIQUE/,
    'un comprador no puede tener dos Customers con el mismo vendedor',
  );
});

test('M4 · saved_cards pasa a ser por (comprador, vendedor)', () => {
  assert.ok(columnas('saved_cards').includes('vendor_id'), 'falta vendor_id');

  assert.strictEqual(
    db.getDb().prepare('SELECT COUNT(*) n FROM saved_cards').get().n, 0,
    'las tarjetas guardadas bajo la plataforma no son cobrables y deben descartarse',
  );

  const ins = db.getDb().prepare(
    `INSERT INTO saved_cards (seller_id, vendor_id, mp_card_id, last_four_digits)
     VALUES (?, ?, ?, ?)`,
  );
  // La MISMA tarjeta física registrada con dos vendedores da dos card_id
  // distintos en MP; y aunque coincidieran, son filas legítimas distintas.
  ins.run('comprador', 'v_mixto', 'card_x', '4242');
  ins.run('comprador', 'v_sin_transf', 'card_x', '4242');

  assert.throws(
    () => ins.run('comprador', 'v_mixto', 'card_x', '4242'),
    /UNIQUE/,
    'la misma tarjeta con el mismo vendedor no puede duplicarse',
  );
});

// ─── M5: purga de 'transferencia' ───────────────────────────────

const metodos = (id) => JSON.parse(
  db.getDb().prepare('SELECT paymentMethods FROM sellers WHERE id = ?').get(id).paymentMethods,
);

test('M5 · transferencia desaparece de quien tenía otros métodos', () => {
  assert.deepStrictEqual(metodos('v_mixto'), ['efectivo', 'paypal']);
});

test('M5 · quien SOLO tenía transferencia no se queda sin ningún método', () => {
  // El sistema exige al menos un método; dejarlo en [] rompería su perfil y
  // le bloquearía guardar cualquier cambio hasta que lo notara.
  assert.deepStrictEqual(metodos('v_solo_transf'), ['efectivo']);
});

test('M5 · a quien no tenía transferencia no se le toca nada', () => {
  assert.deepStrictEqual(metodos('v_sin_transf'), ['efectivo']);
  assert.strictEqual(
    db.getDb().prepare('SELECT paymentMethods FROM sellers WHERE id = ?').get('v_nulo').paymentMethods,
    null,
    'null significa "hereda del perfil" y no debe convertirse en un array',
  );
});

// ─── M6: order_items sobrevive a la recreación de `orders` ───────
//
// Regresión de un 500 en producción al crear cualquier orden:
//
//   SqliteError: no such table: main.orders_legacy
//     at Object.crearOrden (src/payments/store.js)
//
// La migración de `orders` la recrea con ALTER TABLE ... RENAME TO
// orders_legacy. En SQLite moderno ese RENAME no solo renombra la tabla:
// reescribe las claves foráneas que apuntan a ella DESDE OTRAS TABLAS. Así
// que `order_items.order_id` pasaba a referenciar "orders_legacy", y al
// terminar la migración esa tabla ya no existe — dejando la FK colgando y
// cualquier INSERT en order_items muerto.
//
// No lo cazó ningún test porque una base nueva crea `orders` ya con el
// schema bueno: la migración no corre y el daño no ocurre. Solo se rompen
// los despliegues que venían de la versión anterior, que son justamente los
// que importan.

test('M6 · order_items no queda apuntando a una tabla que ya no existe', () => {
  const definicion = sql('order_items');
  assert.ok(
    !definicion.includes('orders_legacy'),
    `la FK quedó colgando tras la migración de orders: ${definicion}`,
  );
  assert.match(definicion, /REFERENCES\s+"?orders"?\s*\(/i);
});

test('M6 · se puede crear una orden con sus items después de migrar', () => {
  // La prueba de verdad: es exactamente lo que hace store.crearOrden, que es
  // donde reventaba en producción.
  db.getDb().prepare(
    `INSERT INTO orders (id, buyer_id, vendor_id, amount, application_fee,
       currency, status, payment_status, payment_method, origin, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 'MXN', 'pending', NULL, NULL, 'direct', ?, ?)`,
  ).run('ord_nueva', 'comprador', 'v_mixto', 100, 5,
    new Date().toISOString(), new Date().toISOString());

  db.getDb().prepare(
    `INSERT INTO order_items (order_id, product_id, quantity, unit_price, title_snapshot)
     VALUES (?, ?, ?, ?, ?)`,
  ).run('ord_nueva', 'p_2', 2, 50, 'Producto nuevo');

  const items = db.getDb()
    .prepare('SELECT * FROM order_items WHERE order_id = ?').all('ord_nueva');
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].unit_price, 50);
});

test('M6 · la orden histórica y su item siguen ahí', () => {
  const orden = db.getDb().prepare('SELECT * FROM orders WHERE id = ?').get('ord_legacy');
  assert.ok(orden, 'no se debió perder ninguna orden al recrear la tabla');
  assert.strictEqual(orden.amount, 250.5);
  assert.strictEqual(orden.mp_payment_id, 'pay_legacy');
  // Las órdenes históricas se crearon antes de que el método se registrara.
  assert.strictEqual(orden.payment_method, null);

  const items = db.getDb()
    .prepare('SELECT * FROM order_items WHERE order_id = ?').all('ord_legacy');
  assert.strictEqual(items.length, 1);
  assert.strictEqual(items[0].title_snapshot, 'Producto histórico');
});

test('M6 · la FK sigue haciendo su trabajo: borrar la orden borra sus items', () => {
  db.getDb().pragma('foreign_keys = ON');
  db.getDb().prepare('DELETE FROM orders WHERE id = ?').run('ord_nueva');

  const items = db.getDb()
    .prepare('SELECT * FROM order_items WHERE order_id = ?').all('ord_nueva');
  assert.strictEqual(items.length, 0,
    'reparar la FK sin conservar el ON DELETE CASCADE dejaría items huérfanos');
});
