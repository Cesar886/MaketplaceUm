// Tests de trending searches: qué cuenta como búsqueda válida, la ventana de
// 7 días, el orden por frecuencia, y que el endpoint cachea en vez de
// recalcular en cada request.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-search-')),
  'test.db',
);

const express = require('express');
const db = require('../database');

db.initDatabase();

// ─── Servidor de pruebas ─────────────────────────────────────

let baseUrl;
let servidor;

let resetTrendingCache;

test.before(async () => {
  const app = express();
  app.use(express.json());
  const { register, _resetTrendingCacheForTests } = require('./search');
  resetTrendingCache = _resetTrendingCacheForTests;
  register(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

/** Inserta una fila directo en `search_queries`, con created_at controlable. */
function sembrarBusqueda(queryText, diasAtras = 0, deviceId = null) {
  db.getDb()
    .prepare(
      `INSERT INTO search_queries (query_text, query_key, device_id, created_at)
       VALUES (?, ?, ?, datetime('now', '-' || ? || ' days'))`,
    )
    .run(queryText, db.searchQueryKey(queryText), deviceId, diasAtras);
}

// ─── database.js: normalización y guardas ─────────────────────

test('normalizeSearchQuery: lowercase, trim y colapsa espacios', () => {
  assert.strictEqual(db.normalizeSearchQuery('  Laptop   Gamer '), 'laptop gamer');
});

test('recordSearchQuery descarta queries muy cortas o muy largas', () => {
  assert.strictEqual(db.recordSearchQuery('a'), false);
  assert.strictEqual(db.recordSearchQuery(' '), false);
  assert.strictEqual(db.recordSearchQuery('x'.repeat(61)), false);
  assert.strictEqual(db.recordSearchQuery('libros'), true);
});

// ─── database.js: getTrendingSearches ─────────────────────────

test('getTrendingSearches excluye búsquedas fuera de la ventana de días', () => {
  db.getDb().exec('DELETE FROM search_queries');
  sembrarBusqueda('reciente', 1);
  sembrarBusqueda('vieja', 30);

  const rows = db.getTrendingSearches({ days: 7, limit: 10 });
  const terms = rows.map(r => r.queryText);

  assert.ok(terms.includes('reciente'));
  assert.ok(!terms.includes('vieja'));
});

test('getTrendingSearches ordena por frecuencia descendente', () => {
  db.getDb().exec('DELETE FROM search_queries');
  sembrarBusqueda('laptop', 0);
  sembrarBusqueda('laptop', 1);
  sembrarBusqueda('laptop', 2);
  sembrarBusqueda('libro', 0);
  sembrarBusqueda('libro', 1);
  sembrarBusqueda('mochila', 0);

  const rows = db.getTrendingSearches({ days: 7, limit: 10 });

  assert.deepStrictEqual(
    rows.map(r => r.queryText),
    ['laptop', 'libro', 'mochila'],
  );
});

// ─── database.js: purga del historial ─────────────────────────

test('purgeOldSearchQueries borra lo viejo y conserva lo reciente', () => {
  db.getDb().exec('DELETE FROM search_queries');
  sembrarBusqueda('de hace poco', 3);
  sembrarBusqueda('dentro del limite', db.SEARCH_QUERY_RETENTION_DAYS - 1);
  sembrarBusqueda('antiquisima', db.SEARCH_QUERY_RETENTION_DAYS + 5);

  const borradas = db.purgeOldSearchQueries();

  assert.strictEqual(borradas, 1);
  const quedan = db
    .getDb()
    .prepare('SELECT query_text FROM search_queries ORDER BY query_text')
    .all()
    .map(r => r.query_text);
  assert.deepStrictEqual(quedan, ['de hace poco', 'dentro del limite']);
});

test('la purga no toca la ventana que mira el ranking', () => {
  // Guarda contra bajar la retención por debajo de la ventana de trending:
  // dejaría al placeholder sin datos justo después de cada arranque.
  assert.ok(
    db.SEARCH_QUERY_RETENTION_DAYS > 7,
    'la retención no puede ser menor que la ventana de trending',
  );
});

// ─── database.js: clave canónica y agrupación de variantes ────

test('searchQueryKey ignora acentos, puntuación y el plural', () => {
  assert.strictEqual(db.searchQueryKey('Cálculo'), 'calculo');
  assert.strictEqual(db.searchQueryKey('calculos'), 'calculo');
  assert.strictEqual(db.searchQueryKey('¿Cálculo?'), 'calculo');
  assert.strictEqual(db.searchQueryKey('Libros de Cálculo'), 'libro de calculo');
});

test('las variantes del mismo término suman al mismo contador', () => {
  db.getDb().exec('DELETE FROM search_queries');
  sembrarBusqueda('cálculo', 0, 'd1');
  sembrarBusqueda('calculo', 0, 'd2');
  sembrarBusqueda('calculos', 0, 'd3');
  sembrarBusqueda('mochila', 0, 'd4');
  sembrarBusqueda('mochila', 0, 'd5');

  const rows = db.getTrendingSearches({ days: 7, limit: 10 });

  // 3 dispositivos para el grupo de "cálculo" contra 2 de "mochila". Antes
  // de agrupar por clave, cada variante valía 1 y "mochila" ganaba.
  assert.strictEqual(rows.length, 2);
  assert.strictEqual(rows[0].count, 3);
  assert.strictEqual(db.searchQueryKey(rows[0].queryText), 'calculo');
});

test('el término se muestra con la ortografía que más gente escribió', () => {
  db.getDb().exec('DELETE FROM search_queries');
  sembrarBusqueda('cálculo', 0, 'd1');
  sembrarBusqueda('cálculo', 0, 'd2');
  sembrarBusqueda('calculos', 0, 'd3');

  const rows = db.getTrendingSearches({ days: 7, limit: 10 });

  assert.strictEqual(rows[0].queryText, 'cálculo');
});

test('cuenta dispositivos distintos, no repeticiones del mismo', () => {
  db.getDb().exec('DELETE FROM search_queries');
  // Un solo dispositivo insistiendo (simulando días distintos para esquivar
  // la deduplicación por tiempo) contra dos personas distintas.
  sembrarBusqueda('spam', 0, 'mismo');
  sembrarBusqueda('spam', 1, 'mismo');
  sembrarBusqueda('spam', 2, 'mismo');
  sembrarBusqueda('spam', 3, 'mismo');
  sembrarBusqueda('real', 0, 'ana');
  sembrarBusqueda('real', 0, 'beto');

  const rows = db.getTrendingSearches({ days: 7, limit: 10 });

  assert.deepStrictEqual(rows.map(r => r.queryText), ['real', 'spam']);
});

test('recordSearchQuery ignora al mismo dispositivo repitiendo el término', () => {
  db.getDb().exec('DELETE FROM search_queries');

  assert.strictEqual(db.recordSearchQuery('bicicleta', 'dev-1'), true);
  assert.strictEqual(db.recordSearchQuery('Bicicletas', 'dev-1'), false, 'misma clave, mismo device');
  assert.strictEqual(db.recordSearchQuery('bicicleta', 'dev-2'), true, 'otra persona sí cuenta');
  assert.strictEqual(db.recordSearchQuery('bicicleta'), true, 'sin device no se puede deduplicar');

  const n = db.getDb().prepare('SELECT COUNT(*) AS n FROM search_queries').get().n;
  assert.strictEqual(n, 3);
});

// ─── GET /api/search/trending ──────────────────────────────────

test('GET /api/search/trending devuelve los términos de la ventana', async () => {
  resetTrendingCache();
  db.getDb().exec('DELETE FROM search_queries');
  sembrarBusqueda('tutorias', 0);
  sembrarBusqueda('tutorias', 0);
  sembrarBusqueda('calculadora', 0);

  const res = await fetch(`${baseUrl}/api/search/trending`);
  const body = await res.json();

  assert.strictEqual(res.status, 200);
  assert.deepStrictEqual(body.terms, ['tutorias', 'calculadora']);
});

test('GET /api/search/trending cachea: no recalcula hasta que expira', async () => {
  resetTrendingCache();
  db.getDb().exec('DELETE FROM search_queries');
  sembrarBusqueda('cacheado', 0);

  const primera = await (await fetch(`${baseUrl}/api/search/trending`)).json();
  assert.deepStrictEqual(primera.terms, ['cacheado']);

  // Se inserta un término nuevo DESPUÉS de la primera consulta: si el
  // endpoint recalculara en cada request, esta segunda llamada ya lo vería.
  sembrarBusqueda('nuevo', 0);

  const segunda = await (await fetch(`${baseUrl}/api/search/trending`)).json();
  assert.deepStrictEqual(segunda.terms, ['cacheado'], 'debió servir desde caché');
});

test('una búsqueda nueva invalida el caché al instante', async () => {
  resetTrendingCache();
  db.getDb().exec('DELETE FROM search_queries');
  sembrarBusqueda('viejo', 0, 'd1');

  const antes = await (await fetch(`${baseUrl}/api/search/trending`)).json();
  assert.deepStrictEqual(antes.terms, ['viejo']);

  // Este es el bug que se está arreglando: registrar una búsqueda por el
  // endpoint real debe reflejarse en la siguiente lectura, sin esperar a que
  // expire el TTL ni reiniciar el proceso.
  await fetch(`${baseUrl}/api/search/track`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: 'nuevo', deviceId: 'd2' }),
  });

  const despues = await (await fetch(`${baseUrl}/api/search/trending`)).json();
  assert.ok(despues.terms.includes('nuevo'), 'el término recién buscado debió aparecer');
});

test('GET /api/search/trending prohíbe el caché HTTP intermedio', async () => {
  const res = await fetch(`${baseUrl}/api/search/trending`);
  assert.strictEqual(res.headers.get('cache-control'), 'no-store');
});

test('GET /api/search/trending devuelve a lo sumo 10 términos', async () => {
  resetTrendingCache();
  db.getDb().exec('DELETE FROM search_queries');
  for (let i = 0; i < 15; i++) sembrarBusqueda(`termino${i}`, 0, `dev${i}`);

  const body = await (await fetch(`${baseUrl}/api/search/trending`)).json();

  assert.strictEqual(body.terms.length, 10);
});

// ─── Arranque en frío: fallback a categorías del catálogo ──────

test('sin búsquedas registradas, cae a categorías con producto activo', async () => {
  resetTrendingCache();
  db.getDb().exec('DELETE FROM search_queries');

  const raw = db.getDb();
  raw.exec(`DELETE FROM products; DELETE FROM categories;`);
  raw.prepare('INSERT INTO categories (id, name) VALUES (?, ?)').run('c_libros', 'Libros');
  raw.prepare('INSERT INTO categories (id, name) VALUES (?, ?)').run('c_tec', 'Tecnología');
  raw.prepare('INSERT INTO categories (id, name) VALUES (?, ?)').run('c_vacia', 'Sin nada');

  const insertar = (id, categoria) =>
    raw
      .prepare('INSERT INTO products (id, title, price, category) VALUES (?, ?, 100, ?)')
      .run(id, `Producto ${id}`, categoria);

  insertar('p1', 'c_tec');
  insertar('p2', 'c_tec');
  insertar('p3', 'c_libros');

  const res = await fetch(`${baseUrl}/api/search/trending`);
  const body = await res.json();

  // Ordenadas por cuántos productos activos tiene cada una; la categoría
  // sin producto no se sugiere (buscarla dejaría la lista vacía).
  assert.deepStrictEqual(body.terms, ['Tecnología', 'Libros']);
});

test('las búsquedas reales le ganan al fallback de categorías', async () => {
  resetTrendingCache();
  db.getDb().exec('DELETE FROM search_queries');
  sembrarBusqueda('bicicleta', 0);

  const res = await fetch(`${baseUrl}/api/search/trending`);
  const body = await res.json();

  assert.deepStrictEqual(body.terms, ['bicicleta']);
});

// ─── POST /api/search/track ────────────────────────────────────

test('POST /api/search/track responde 400 sin query', async () => {
  const res = await fetch(`${baseUrl}/api/search/track`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  assert.strictEqual(res.status, 400);
});

test('POST /api/search/track registra una búsqueda válida', async () => {
  db.getDb().exec('DELETE FROM search_queries');

  const res = await fetch(`${baseUrl}/api/search/track`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: '  Bicicleta ' }),
  });
  assert.strictEqual(res.status, 204);

  const row = db.getDb().prepare('SELECT query_text FROM search_queries').get();
  assert.strictEqual(row.query_text, 'bicicleta');
});

test('POST /api/search/track ignora queries basura sin devolver error', async () => {
  db.getDb().exec('DELETE FROM search_queries');

  const res = await fetch(`${baseUrl}/api/search/track`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: 'a' }),
  });
  assert.strictEqual(res.status, 204);

  const count = db.getDb().prepare('SELECT COUNT(*) AS n FROM search_queries').get();
  assert.strictEqual(count.n, 0);
});
