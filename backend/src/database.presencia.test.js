const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-presencia-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const db = require('./database');

db.initDatabase();

function crearSeller(id, nombre = 'Alguien') {
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, avatarInitials, major, isBusiness, tipo_cuenta)
     VALUES (?, ?, 'AL', '', 0, 'estudiante')`,
  ).run(id, nombre);
}

test('las columnas de presencia existen en sellers', () => {
  const cols = db.getDb().prepare("PRAGMA table_info('sellers')").all().map(c => c.name);
  assert.ok(cols.includes('last_active'), 'falta la columna last_active');
  assert.ok(cols.includes('show_online_status'), 'falta la columna show_online_status');
});

test('una cuenta existente comparte su estado por defecto y no tiene last_active', () => {
  crearSeller('pres_default');

  const fila = db.getDb().prepare('SELECT * FROM sellers WHERE id = ?').get('pres_default');
  assert.strictEqual(fila.show_online_status, 1);
  assert.strictEqual(fila.last_active, null);
});

test('setUltimaActividad guarda el instante en la fila del usuario', () => {
  crearSeller('pres_guardar');

  db.setUltimaActividad('pres_guardar', '2026-08-17T10:00:00.000Z');

  assert.strictEqual(
    db.getPresencia('pres_guardar').lastActive,
    '2026-08-17T10:00:00.000Z',
  );
});

test('setUltimaActividad sobre un id inexistente no lanza', () => {
  assert.doesNotThrow(() => db.setUltimaActividad('no_existe', '2026-08-17T10:00:00.000Z'));
});

test('setMostrarEstadoEnLinea apaga y vuelve a encender la preferencia', () => {
  crearSeller('pres_toggle');

  db.setMostrarEstadoEnLinea('pres_toggle', false);
  assert.strictEqual(db.getPresencia('pres_toggle').comparteEstado, false);

  db.setMostrarEstadoEnLinea('pres_toggle', true);
  assert.strictEqual(db.getPresencia('pres_toggle').comparteEstado, true);
});

test('getPresencia de un usuario inexistente devuelve un estado que no comparte', () => {
  // Un id desconocido no debe reventar la lista de chats ni "filtrar" un
  // estado inventado: se trata como si tuviera la presencia apagada.
  assert.deepEqual(db.getPresencia('nadie'), {
    lastActive: null,
    comparteEstado: false,
  });
});
