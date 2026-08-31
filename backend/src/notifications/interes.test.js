// Tests del scoring de interés por categoría (retargeting conductual).

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Debe fijarse antes de requerir database.js: la ruta se resuelve al importar.
const tmpDb = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-interes-')),
  'test.db'
);
process.env.MERCADITO_DB_PATH = tmpDb;

const db = require('../database');
db.initDatabase();
const raw = db.getDb();

const interes = require('./interes');

function sembrarCategoria(id) {
  raw.prepare('INSERT OR IGNORE INTO categories (id, name) VALUES (?, ?)').run(id, `Cat ${id}`);
}

function sembrarEvento({ deviceId, userId = null, categoria, tipo, diasAtras = 0, productId = null }) {
  raw.prepare(`
    INSERT INTO interacciones_dispositivo (device_id, user_id, product_id, category, tipo, created_at)
    VALUES (?, ?, ?, ?, ?, datetime('now', ?))
  `).run(deviceId, userId, productId, categoria, tipo, `-${diasAtras} days`);
}

test.beforeEach(() => {
  raw.prepare('DELETE FROM interacciones_dispositivo').run();
  raw.prepare('DELETE FROM user_category_interest').run();
  raw.prepare('DELETE FROM category_interests').run();
});

test('cada tipo de evento suma su peso', () => {
  sembrarCategoria('libros');
  sembrarEvento({ deviceId: 'd1', userId: 'u1', categoria: 'libros', tipo: 'categoria' });
  sembrarEvento({ deviceId: 'd1', userId: 'u1', categoria: 'libros', tipo: 'vista' });
  sembrarEvento({ deviceId: 'd1', userId: 'u1', categoria: 'libros', tipo: 'favorito' });
  sembrarEvento({ deviceId: 'd1', userId: 'u1', categoria: 'libros', tipo: 'contacto' });

  const [fila] = interes.calcularInteres();
  const { categoria, vista, favorito, contacto } = interes.PESOS_INTERES;

  assert.strictEqual(fila.subjectId, 'u1');
  assert.strictEqual(fila.categoryId, 'libros');
  assert.strictEqual(fila.score, categoria + vista + favorito + contacto);
});

test('un evento de hace N días aporta peso * 0.8^N', () => {
  sembrarCategoria('ropa');
  sembrarEvento({ deviceId: 'd1', userId: 'u1', categoria: 'ropa', tipo: 'contacto', diasAtras: 3 });

  const [fila] = interes.calcularInteres();
  const esperado = interes.PESOS_INTERES.contacto * Math.pow(interes.FACTOR_DECAIMIENTO, 3);

  assert.strictEqual(fila.score, Math.round(esperado * 100) / 100);
});

test('los eventos fuera de la ventana de 7 días no aportan nada', () => {
  sembrarCategoria('comida');
  sembrarEvento({
    deviceId: 'd1', userId: 'u1', categoria: 'comida', tipo: 'contacto',
    diasAtras: interes.VENTANA_INTERES_DIAS + 1,
  });

  assert.deepStrictEqual(interes.calcularInteres(), []);
});

test('un dispositivo sin sesión puntúa bajo su id anónimo', () => {
  sembrarCategoria('libros');
  sembrarEvento({ deviceId: 'anon_abc', userId: null, categoria: 'libros', tipo: 'favorito' });

  const [fila] = interes.calcularInteres();
  assert.strictEqual(fila.subjectId, 'anon_abc');
});

test('decay_status distingue lo de hoy de lo que ya viene decayendo', () => {
  sembrarCategoria('libros');
  sembrarCategoria('ropa');
  sembrarEvento({ deviceId: 'd1', userId: 'u1', categoria: 'libros', tipo: 'vista', diasAtras: 0 });
  sembrarEvento({ deviceId: 'd1', userId: 'u1', categoria: 'ropa', tipo: 'vista', diasAtras: 3 });

  const porCategoria = Object.fromEntries(
    interes.calcularInteres().map(f => [f.categoryId, f.decayStatus])
  );

  assert.strictEqual(porCategoria.libros, 'fresh');
  assert.strictEqual(porCategoria.ropa, 'decaying');
});

test('refrescarInteres reescribe el snapshot y no acumula filas viejas', () => {
  sembrarCategoria('libros');
  sembrarEvento({ deviceId: 'd1', userId: 'u1', categoria: 'libros', tipo: 'contacto' });

  assert.strictEqual(interes.refrescarInteres(), 1);
  assert.strictEqual(interes.refrescarInteres(), 1, 'dos pasadas no pueden duplicar la fila');

  // Sin eventos vigentes, el snapshot queda vacío: así es como se purga a
  // quien lleva 7 días sin aparecer.
  raw.prepare('DELETE FROM interacciones_dispositivo').run();
  assert.strictEqual(interes.refrescarInteres(), 0);
  const { c } = raw.prepare('SELECT COUNT(*) AS c FROM user_category_interest').get();
  assert.strictEqual(c, 0);
});

test('solo es elegible quien pasa el umbral', () => {
  sembrarCategoria('libros');
  // 1 vista = 3 puntos, por debajo del umbral de 5.
  sembrarEvento({ deviceId: 'd1', userId: 'flojo', categoria: 'libros', tipo: 'vista' });
  sembrarEvento({ deviceId: 'd2', userId: 'interesado', categoria: 'libros', tipo: 'contacto' });
  interes.refrescarInteres();

  const ids = interes.getSujetosElegibles('libros').map(s => s.subjectId);
  assert.deepStrictEqual(ids, ['interesado']);
});

test('no es elegible quien pasa el umbral pero no toca la categoría hace 48h', () => {
  sembrarCategoria('libros');
  // Suficientes puntos aun con decaimiento, pero la última interacción es
  // de hace 3 días: fuera de la ventana de frescura.
  for (let i = 0; i < 5; i++) {
    sembrarEvento({ deviceId: 'd1', userId: 'u1', categoria: 'libros', tipo: 'contacto', diasAtras: 3 });
  }
  interes.refrescarInteres();

  const snapshot = raw.prepare('SELECT interest_score FROM user_category_interest').get();
  assert.ok(snapshot.interest_score >= interes.UMBRAL_INTERES, 'el score debe superar el umbral');
  assert.deepStrictEqual(interes.getSujetosElegibles('libros'), []);
});

test('seguir la categoría a mano hace elegible sin score alguno', () => {
  sembrarCategoria('libros');
  raw.prepare('INSERT INTO category_interests (user_id, category_id) VALUES (?, ?)')
    .run('seguidor', 'libros');
  interes.refrescarInteres();

  const elegibles = interes.getSujetosElegibles('libros');
  assert.strictEqual(elegibles.length, 1);
  assert.strictEqual(elegibles[0].subjectId, 'seguidor');
  assert.strictEqual(elegibles[0].motivo, 'category_follow');
});

test('quien sigue la categoría Y además la navegó sale una sola vez, como interest_match', () => {
  sembrarCategoria('libros');
  raw.prepare('INSERT INTO category_interests (user_id, category_id) VALUES (?, ?)')
    .run('u1', 'libros');
  sembrarEvento({ deviceId: 'd1', userId: 'u1', categoria: 'libros', tipo: 'contacto' });
  interes.refrescarInteres();

  const elegibles = interes.getSujetosElegibles('libros');
  assert.strictEqual(elegibles.length, 1);
  assert.strictEqual(elegibles[0].motivo, 'interest_match');
});
