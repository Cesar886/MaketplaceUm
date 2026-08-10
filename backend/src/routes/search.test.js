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
function sembrarBusqueda(queryText, diasAtras = 0) {
  db.getDb()
    .prepare(
      `INSERT INTO search_queries (query_text, created_at)
       VALUES (?, datetime('now', '-' || ? || ' days'))`,
    )
    .run(queryText, diasAtras);
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
