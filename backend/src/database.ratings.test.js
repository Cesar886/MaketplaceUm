// Tests del agregado de calificaciones por vendedor.
//
// El bug que motivó estos tests: `sellers.rating`/`sellers.reviews` es un
// caché denormalizado que se recalculaba solo en memoria al calificar y nunca
// se escribía a SQLite. Como TODA lectura (GET /api/sellers/:id, sellerObj de
// attachRelations, el scoring del feed) sale de esa columna, el perfil mostraba
// para siempre el valor semilla. Por eso lo que se afirma aquí es la
// PERSISTENCIA del agregado, no solo que la query sepa sumar.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Debe fijarse antes de requerir database.js: la ruta se resuelve al importar.
const tmpDb = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-ratings-')),
  'test.db'
);
process.env.MERCADITO_DB_PATH = tmpDb;

const db = require('./database');
db.initDatabase();
const raw = db.getDb();

/** Vendedor mínimo, con el caché ya "sucio" como lo deja la semilla. */
function sembrarVendedor(id, rating = 0, reviews = 0) {
  raw.prepare(
    'INSERT OR REPLACE INTO sellers (id, name, rating, reviews) VALUES (?, ?, ?, ?)'
  ).run(id, `Vendedor ${id}`, rating, reviews);
}

function sembrarProducto(id, sellerId) {
  raw.prepare(
    "INSERT OR REPLACE INTO products (id, title, price, seller) VALUES (?, ?, '0', ?)"
  ).run(id, `Producto ${id}`, sellerId);
}

test('el promedio del vendedor suma las calificaciones de TODOS sus productos', () => {
  sembrarVendedor('s_multi');
  sembrarProducto('p_a', 's_multi');
  sembrarProducto('p_b', 's_multi');
  sembrarProducto('p_c', 's_multi');

  // 5 y 3 en p_a, 4 en p_b, ninguna en p_c → promedio 4 sobre 3 calificaciones.
  db.upsertProductRating('p_a', 'u_1', 5);
  db.upsertProductRating('p_a', 'u_2', 3);
  db.upsertProductRating('p_b', 'u_3', 4);

  const stats = db.getSellerRatingStats('s_multi');
  assert.strictEqual(stats.rating, 4);
  assert.strictEqual(stats.reviews, 3);
});

test('calificar persiste el agregado en la tabla sellers, no solo en memoria', () => {
  sembrarVendedor('s_persist');
  sembrarProducto('p_d', 's_persist');
  sembrarProducto('p_e', 's_persist');

  db.upsertProductRating('p_d', 'u_1', 5);
  db.syncSellerRating('s_persist');

  db.upsertProductRating('p_e', 'u_2', 4);
  db.syncSellerRating('s_persist');

  // Se lee de SQLite, no del array en memoria: esto es lo que sobrevive a un
  // reinicio y lo que ve GET /api/sellers/:id.
  const fila = raw.prepare('SELECT rating, reviews FROM sellers WHERE id = ?').get('s_persist');
  assert.strictEqual(fila.rating, 4.5);
  assert.strictEqual(fila.reviews, 2);
});

test('syncSellerRating devuelve el agregado ya persistido', () => {
  sembrarVendedor('s_ret');
  sembrarProducto('p_f', 's_ret');
  db.upsertProductRating('p_f', 'u_1', 3);

  assert.deepStrictEqual(db.syncSellerRating('s_ret'), { rating: 3, reviews: 1 });
});

test('el recálculo global corrige un caché inflado sin calificaciones reales', () => {
  // Exactamente el caso de la base actual: 4.9 (52) en sellers y cero filas
  // en product_ratings. El número "pegado" que reportó el usuario.
  sembrarVendedor('s_stale', 4.9, 52);
  sembrarProducto('p_g', 's_stale');

  db.recomputeAllSellerRatings();

  const fila = raw.prepare('SELECT rating, reviews FROM sellers WHERE id = ?').get('s_stale');
  assert.strictEqual(fila.rating, 0);
  assert.strictEqual(fila.reviews, 0);
});

test('el recálculo global arregla a un vendedor cuyo caché quedó atrasado', () => {
  sembrarVendedor('s_atras', 1, 1);
  sembrarProducto('p_h', 's_atras');
  sembrarProducto('p_i', 's_atras');
  db.upsertProductRating('p_h', 'u_1', 5);
  db.upsertProductRating('p_i', 'u_2', 4);
  db.upsertProductRating('p_i', 'u_3', 5);

  db.recomputeAllSellerRatings();

  const fila = raw.prepare('SELECT rating, reviews FROM sellers WHERE id = ?').get('s_atras');
  assert.strictEqual(fila.rating, 4.7);
  assert.strictEqual(fila.reviews, 3);
});

test('recalificar el mismo producto reemplaza el voto, no lo duplica', () => {
  sembrarVendedor('s_revote');
  sembrarProducto('p_j', 's_revote');
  db.upsertProductRating('p_j', 'u_1', 1);
  db.upsertProductRating('p_j', 'u_1', 5);

  assert.deepStrictEqual(db.syncSellerRating('s_revote'), { rating: 5, reviews: 1 });
});

test.after(() => {
  fs.rmSync(path.dirname(tmpDb), { recursive: true, force: true });
});
