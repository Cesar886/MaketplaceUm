// Tests del scoring de engagement por categoría, usado para ordenar
// dinámicamente los íconos de categoría en home y búsqueda.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Debe fijarse antes de requerir database.js: la ruta se resuelve al importar.
const tmpDb = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-category-engagement-')),
  'test.db'
);
process.env.MERCADITO_DB_PATH = tmpDb;

const db = require('./database');
db.initDatabase();
const raw = db.getDb();

function sembrarCategoria(id) {
  raw.prepare(
    'INSERT OR IGNORE INTO categories (id, name) VALUES (?, ?)'
  ).run(id, `Categoría ${id}`);
}

function sembrarEvento(categoryId, eventType, daysAgo = 0) {
  raw.prepare(`
    INSERT INTO category_engagement_events (category_id, event_type, created_at)
    VALUES (?, ?, datetime('now', ?))
  `).run(categoryId, eventType, `-${daysAgo} days`);
}

function esperarSetImmediate() {
  return new Promise((resolve) => setImmediate(resolve));
}

test.beforeEach(() => {
  db.invalidateCategoriesRankedCache();
});

test('el score suma los eventos con el peso de su tipo', () => {
  sembrarCategoria('cat_score');
  sembrarEvento('cat_score', 'publish');
  sembrarEvento('cat_score', 'product_view');
  sembrarEvento('cat_score', 'product_view');
  sembrarEvento('cat_score', 'icon_tap');

  const { publish, product_view: view, icon_tap: tap } = db.CATEGORY_ENGAGEMENT_WEIGHTS;
  const expected = publish + view * 2 + tap;

  const ranked = db.getCategoriesRanked();
  const row = ranked.find(c => c.id === 'cat_score');
  assert.strictEqual(row.score, expected);
});

test('categorías sin eventos aparecen con score 0, no se excluyen', () => {
  sembrarCategoria('cat_sin_actividad');

  const ranked = db.getCategoriesRanked();
  const row = ranked.find(c => c.id === 'cat_sin_actividad');
  assert.ok(row, 'la categoría sin eventos debe seguir en la lista');
  assert.strictEqual(row.score, 0);
});

test('eventos fuera de la ventana de tiempo no cuentan para el score', () => {
  sembrarCategoria('cat_vieja');
  sembrarEvento('cat_vieja', 'publish', db.CATEGORY_ENGAGEMENT_WINDOW_DAYS + 5);

  const ranked = db.getCategoriesRanked();
  const row = ranked.find(c => c.id === 'cat_vieja');
  assert.strictEqual(row.score, 0);
});

test('el orden es por score descendente', () => {
  sembrarCategoria('cat_alta');
  sembrarCategoria('cat_baja');
  sembrarEvento('cat_alta', 'publish');
  sembrarEvento('cat_baja', 'icon_tap');

  const ranked = db.getCategoriesRanked();
  const idxAlta = ranked.findIndex(c => c.id === 'cat_alta');
  const idxBaja = ranked.findIndex(c => c.id === 'cat_baja');
  assert.ok(idxAlta < idxBaja);
});

test('trackCategoryEngagement inserta el evento de forma diferida (best-effort)', async () => {
  sembrarCategoria('cat_track');
  db.trackCategoryEngagement('cat_track', 'icon_tap');

  await esperarSetImmediate();

  const count = raw.prepare(
    "SELECT COUNT(*) AS c FROM category_engagement_events WHERE category_id = ? AND event_type = 'icon_tap'"
  ).get('cat_track');
  assert.strictEqual(count.c, 1);
});

test('trackCategoryEngagement no lanza si categoryId o eventType faltan', () => {
  assert.doesNotThrow(() => db.trackCategoryEngagement(null, 'icon_tap'));
  assert.doesNotThrow(() => db.trackCategoryEngagement('cat_track', null));
});
