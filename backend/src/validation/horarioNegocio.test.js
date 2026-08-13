// Estado de atención de un vendedor, calculado en el SERVIDOR.
//
// Vive aquí y no solo en la app porque de esto depende que un cobro se acepte
// o se rechace, y la hora de un teléfono la cambia quien lo usa.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-horario-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';
process.env.PAYMENTS_ENCRYPTION_KEY = crypto.randomBytes(32).toString('hex');

const db = require('../database');
db.initDatabase();

const { estadoDeAtencion, mensajeCerrado } = require('./horarioNegocio');

let n = 0;
function crearVendedor(horario) {
  const id = `u_hor_${++n}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, verified, businessHours)
     VALUES (?, ?, ?, 'TT', '', 1, ?)`,
  ).run(id, `V ${id}`, `${id}@x.com`, horario ? JSON.stringify(horario) : null);
  return id;
}

// 2026-08-12 es MIÉRCOLES → índice 2 (0=lunes).
const miercoles = (h, m = 0) => new Date(2026, 7, 12, h, m);

test('dentro del horario está abierto', () => {
  const v = crearVendedor({ '2': { open: '09:00', close: '18:00' } });
  assert.strictEqual(estadoDeAtencion(v, miercoles(13)).abierto, true);
});

test('antes de abrir está cerrado y dice a qué hora abre', () => {
  const v = crearVendedor({ '2': { open: '09:00', close: '18:00' } });
  const e = estadoDeAtencion(v, miercoles(7, 30));

  assert.strictEqual(e.abierto, false);
  assert.strictEqual(e.abreA, '09:00');
  assert.strictEqual(e.diaAbre, 2, 'abre hoy mismo');
});

test('después de cerrar apunta al siguiente día con horario', () => {
  const v = crearVendedor({
    '2': { open: '09:00', close: '18:00' },
    '4': { open: '10:00', close: '14:00' },
  });
  const e = estadoDeAtencion(v, miercoles(20));

  assert.strictEqual(e.abierto, false);
  assert.strictEqual(e.diaAbre, 4, 'el viernes es el próximo día con horario');
  assert.strictEqual(e.abreA, '10:00');
});

test('la hora de cierre ya está cerrado', () => {
  // El rango es [open, close): a las 18:00 en punto ya no se atiende.
  const v = crearVendedor({ '2': { open: '09:00', close: '18:00' } });
  assert.strictEqual(estadoDeAtencion(v, miercoles(18)).abierto, false);
});

test('un día sin horario busca el siguiente, dando la vuelta a la semana', () => {
  const v = crearVendedor({ '0': { open: '08:00', close: '12:00' } });
  const e = estadoDeAtencion(v, miercoles(10));

  assert.strictEqual(e.abierto, false);
  assert.strictEqual(e.diaAbre, 0, 'el próximo lunes');
});

test('sin horario configurado se considera abierto, no cerrado', () => {
  // Quien no declara horario no está "cerrado": simplemente no usa esta
  // función. Tratarlo como cerrado le bloquearía las ventas sin motivo — la
  // exigencia de tener horario vive en la verificación, no aquí.
  const v = crearVendedor(null);
  const e = estadoDeAtencion(v, miercoles(3));

  assert.strictEqual(e.abierto, true);
  assert.strictEqual(e.tieneHorario, false);
});

test('un horario corrupto no revienta ni bloquea', () => {
  const id = `u_hor_${++n}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, verified, businessHours)
     VALUES (?, ?, ?, 'TT', '', 1, 'no-es-json')`,
  ).run(id, 'Corrupto', `${id}@x.com`);

  assert.strictEqual(estadoDeAtencion(id, miercoles(10)).abierto, true);
});

test('un vendedor que no existe no bloquea el cobro', () => {
  assert.strictEqual(estadoDeAtencion('u_fantasma', miercoles(10)).abierto, true);
});

test('el mensaje dice cuándo vuelve a abrir', () => {
  const v = crearVendedor({ '4': { open: '10:00', close: '14:00' } });
  const e = estadoDeAtencion(v, miercoles(20));

  const msg = mensajeCerrado('Tacos UM', e);
  assert.match(msg, /Tacos UM/);
  assert.match(msg, /cerrado/i);
  assert.match(msg, /viernes/);
  assert.match(msg, /10:00/);
});

test('sin nombre de vendedor el mensaje sigue leyéndose', () => {
  const v = crearVendedor({ '2': { open: '09:00', close: '18:00' } });
  const msg = mensajeCerrado(null, estadoDeAtencion(v, miercoles(7)));
  assert.match(msg, /Este vendedor/);
});
