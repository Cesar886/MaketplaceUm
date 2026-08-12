// Tests de las dos métricas del perfil: mediana de respuesta y racha de
// publicaciones.
//
// Ambas se eligieron POR resistencia a valores atípicos y por lo que NO
// cuentan, así que eso es justo lo que se afirma aquí:
//  - la mediana ignora la conversación olvidada tres días, que es lo que
//    hacía inútil al promedio (la columna avg_response_minutes ni siquiera
//    llegó a poblarse nunca);
//  - la racha cuenta publicar y NADA más — vender no la mueve.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Debe fijarse antes de requerir database.js: la ruta se resuelve al importar.
const tmpDb = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-metricas-')),
  'test.db'
);
process.env.MERCADITO_DB_PATH = tmpDb;

const db = require('./database');
db.initDatabase();
const raw = db.getDb();

function sembrarVendedor(id) {
  raw.prepare('INSERT OR REPLACE INTO sellers (id, name) VALUES (?, ?)')
    .run(id, `Vendedor ${id}`);
}

function sembrarConversacion(id, sellerId, buyerId = 'comprador') {
  raw.prepare(
    'INSERT OR REPLACE INTO conversations (id, buyer_id, seller_id) VALUES (?, ?, ?)'
  ).run(id, buyerId, sellerId);
}

/** [minutos] son minutos desde una base fija, para controlar los deltas. */
const BASE = '2026-01-01 00:00:00';
function sembrarMensaje(id, conversationId, senderId, minutos) {
  raw.prepare(`
    INSERT OR REPLACE INTO messages (id, conversation_id, sender_id, text, created_at)
    VALUES (?, ?, ?, 'hola', datetime(?, '+' || ? || ' minutes'))
  `).run(id, conversationId, senderId, BASE, minutos);
}

/**
 * Mismo mensaje que [sembrarMensaje] pero con segundos exactos (no solo
 * minutos), para forzar que dos filas caigan en el MISMO segundo — el caso
 * que `created_at` no puede distinguir por sí solo.
 */
function sembrarMensajeConSegundos(id, conversationId, senderId, segundos) {
  raw.prepare(`
    INSERT OR REPLACE INTO messages (id, conversation_id, sender_id, text, created_at)
    VALUES (?, ?, ?, 'hola', datetime(?, '+' || ? || ' seconds'))
  `).run(id, conversationId, senderId, BASE, segundos);
}

/** Publica [dias] días atrás respecto de hoy. */
function sembrarProducto(id, sellerId, diasAtras) {
  raw.prepare(`
    INSERT OR REPLACE INTO products (id, title, price, seller, created_at)
    VALUES (?, ?, '0', ?, datetime('now', '-' || ? || ' days'))
  `).run(id, `Producto ${id}`, sellerId, diasAtras);
}

// ─── Mediana de respuesta ────────────────────────────────────────

test('la mediana ignora la conversación atípica que arruinaba el promedio', () => {
  const v = 'v-mediana';
  sembrarVendedor(v);
  // Cuatro respuestas de 10 min y una olvidada 3 días (4320 min).
  for (let i = 0; i < 4; i++) {
    sembrarConversacion(`c${i}`, v, `comprador${i}`);
    sembrarMensaje(`m${i}a`, `c${i}`, `comprador${i}`, 0);
    sembrarMensaje(`m${i}b`, `c${i}`, v, 10);
  }
  sembrarConversacion('c-olvidada', v, 'comprador-x');
  sembrarMensaje('mxa', 'c-olvidada', 'comprador-x', 0);
  sembrarMensaje('mxb', 'c-olvidada', v, 4320);

  const deltas = db.getResponseDeltasMinutes(v);
  assert.strictEqual(deltas.length, 5);

  const promedio = deltas.reduce((a, b) => a + b, 0) / deltas.length;
  assert.ok(promedio > 800, `el promedio se dispara: ${promedio}`);

  // La mediana se queda en 10: cuatro respuestas rápidas ganan a una lenta.
  assert.strictEqual(db.syncSellerResponseTime(v), 10);
});

test('una ráfaga del comprador cuenta como UNA espera, medida desde el primero', () => {
  const v = 'v-rafaga';
  sembrarVendedor(v);
  sembrarConversacion('c-rafaga', v);
  // El comprador escribe 3 veces (min 0, 5, 8) y el vendedor contesta al 20.
  sembrarMensaje('r1', 'c-rafaga', 'comprador', 0);
  sembrarMensaje('r2', 'c-rafaga', 'comprador', 5);
  sembrarMensaje('r3', 'c-rafaga', 'comprador', 8);
  sembrarMensaje('r4', 'c-rafaga', v, 20);

  const deltas = db.getResponseDeltasMinutes(v);
  assert.deepStrictEqual(deltas, [20], 'debe medirse desde el primer mensaje');
});

test('dos mensajes en el MISMO segundo se ordenan por id, no por orden de inserción', () => {
  // created_at solo tiene precisión de segundo (datetime('now') de SQLite);
  // sin un desempate por `id` (que sí tiene precisión de milisegundo, ver
  // ORDER BY en getResponseDeltasMinutes), SQLite no garantiza el orden de
  // dos filas empatadas en created_at — podría devolverlas en orden de
  // inserción física, que aquí es deliberadamente el CONTRARIO al orden
  // cronológico real, para que un desempate roto se note.
  const v = 'v-empate';
  sembrarVendedor(v);
  sembrarConversacion('c-empate', v);

  // Orden cronológico real: comprador (seg 0) -> vendedor (seg 0, mismo
  // segundo). Los ids codifican ese orden ('e1' < 'e2'), pero se insertan
  // en la tabla al revés (primero la respuesta del vendedor).
  sembrarMensajeConSegundos('e2', 'c-empate', v, 0);
  sembrarMensajeConSegundos('e1', 'c-empate', 'comprador', 0);

  const deltas = db.getResponseDeltasMinutes(v);
  // Si el desempate por id funciona, se lee comprador->vendedor y sí hay
  // una respuesta que medir (aunque el delta sea ~0 al caer en el mismo
  // segundo). Sin el desempate, un orden vendedor-antes-que-comprador no
  // abre ninguna espera, y esto quedaría vacío.
  assert.strictEqual(deltas.length, 1);
});

test('no se calcula mediana sin respuestas suficientes', () => {
  const v = 'v-pocas';
  sembrarVendedor(v);
  sembrarConversacion('c-pocas', v);
  sembrarMensaje('p1', 'c-pocas', 'comprador', 0);
  sembrarMensaje('p2', 'c-pocas', v, 5);

  assert.ok(db.MIN_RESPUESTAS_PARA_MEDIANA > 1);
  assert.strictEqual(db.syncSellerResponseTime(v), null);
});

test('los mensajes del vendedor sin pregunta previa no cuentan como respuesta', () => {
  const v = 'v-monologo';
  sembrarVendedor(v);
  sembrarConversacion('c-monologo', v);
  // El vendedor escribe primero y varias veces seguidas: no hay espera que
  // cerrar, así que no hay ningún delta que medir.
  sembrarMensaje('mo1', 'c-monologo', v, 0);
  sembrarMensaje('mo2', 'c-monologo', v, 30);
  sembrarMensaje('mo3', 'c-monologo', v, 60);

  assert.deepStrictEqual(db.getResponseDeltasMinutes(v), []);
});

test('la mediana par promedia los dos valores centrales', () => {
  const v = 'v-par';
  sembrarVendedor(v);
  // Deltas: 10, 20, 30, 40 -> mediana (20+30)/2 = 25
  const minutos = [10, 20, 30, 40];
  minutos.forEach((delta, i) => {
    sembrarConversacion(`cp${i}`, v, `compradorp${i}`);
    sembrarMensaje(`mp${i}a`, `cp${i}`, `compradorp${i}`, 0);
    sembrarMensaje(`mp${i}b`, `cp${i}`, v, delta);
  });

  assert.strictEqual(db.syncSellerResponseTime(v), 25);
});

test('createMessage refresca la mediana solo cuando responde el vendedor', () => {
  const v = 'v-hook';
  sembrarVendedor(v);
  sembrarConversacion('c-hook', v);
  const leer = () => raw
    .prepare('SELECT median_response_minutes AS m FROM sellers WHERE id = ?')
    .get(v).m;

  // Tres pares comprador->vendedor a través de createMessage (la ruta real).
  for (let i = 0; i < 3; i++) {
    db.createMessage(`h${i}a`, 'c-hook', 'comprador', 'pregunta');
    assert.strictEqual(leer(), null, 'el mensaje del comprador no calcula nada');
    db.createMessage(`h${i}b`, 'c-hook', v, 'respuesta');
  }
  // Las tres respuestas fueron inmediatas, así que la mediana es 0 — lo que
  // importa es que dejó de ser null sin que nadie llamara al sync a mano.
  assert.strictEqual(leer(), 0);
});

// ─── Racha de publicaciones ──────────────────────────────────────

test('la racha cuenta semanas consecutivas con al menos una publicación', () => {
  const v = 'v-racha';
  sembrarVendedor(v);
  sembrarProducto('ra1', v, 1); // esta semana
  sembrarProducto('ra2', v, 8); // semana pasada
  sembrarProducto('ra3', v, 15); // hace dos semanas

  assert.strictEqual(db.computeRachaPublicaciones(v), 3);
});

test('varias publicaciones en la misma semana no inflan la racha', () => {
  const v = 'v-mismasemana';
  sembrarVendedor(v);
  sembrarProducto('ms1', v, 0);
  sembrarProducto('ms2', v, 1);
  sembrarProducto('ms3', v, 2);

  assert.strictEqual(db.computeRachaPublicaciones(v), 1);
});

test('un hueco de una semana rompe la racha', () => {
  const v = 'v-hueco';
  sembrarVendedor(v);
  sembrarProducto('hu1', v, 1); // esta semana
  sembrarProducto('hu2', v, 22); // hace tres semanas: hay hueco en medio

  assert.strictEqual(db.computeRachaPublicaciones(v), 1);
});

test('publicar hace 6 días mantiene viva la ventana actual', () => {
  const v = 'v-gracia';
  sembrarVendedor(v);
  // La ventana 0 son los últimos 7 días completos, no "lo que va de semana":
  // publicar el miércoles pasado sigue contando el martes siguiente.
  sembrarProducto('gr1', v, 6);

  assert.strictEqual(db.computeRachaPublicaciones(v), 1);
});

test('dejar pasar 7 días sin publicar rompe la racha', () => {
  const v = 'v-rota';
  sembrarVendedor(v);
  // Dos publicaciones consecutivas, pero ninguna en los últimos 7 días.
  sembrarProducto('ro1', v, 9);
  sembrarProducto('ro2', v, 16);

  assert.strictEqual(db.computeRachaPublicaciones(v), 0);
});

test('vender NO mueve la racha: solo cuenta publicar', () => {
  const v = 'v-vendido';
  sembrarVendedor(v);
  sembrarProducto('ve1', v, 1);
  sembrarProducto('ve2', v, 8);
  const antes = db.computeRachaPublicaciones(v);

  // Marcar ambas como vendidas no cambia nada: la racha mide constancia
  // publicando, no resultados de venta.
  raw.prepare("UPDATE products SET status = 'sold' WHERE seller = ?").run(v);

  assert.strictEqual(db.computeRachaPublicaciones(v), antes);
  assert.strictEqual(antes, 2);
});

test('un vendedor sin publicaciones tiene racha 0', () => {
  const v = 'v-vacio';
  sembrarVendedor(v);
  assert.strictEqual(db.computeRachaPublicaciones(v), 0);
});
