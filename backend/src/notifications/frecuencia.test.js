// Tests del frequency capping y la reducción adaptativa del retargeting.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const tmpDb = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-frecuencia-')),
  'test.db'
);
process.env.MERCADITO_DB_PATH = tmpDb;

const db = require('../database');
db.initDatabase();
const raw = db.getDb();

const frecuencia = require('./frecuencia');

/**
 * Escribe una fila en notification_log con antigüedad y apertura a medida.
 * Se inserta con SQL directo en vez de con registrarEnvio() porque las
 * reglas que se prueban dependen de fechas pasadas, y registrarEnvio()
 * siempre escribe 'now'.
 */
function sembrarEnvio({ subjectId, categoria, horasAtras, abierta = false }) {
  raw.prepare(`
    INSERT INTO notification_log (subject_id, type, category_id, product_ids, sent_at, opened_at)
    VALUES (?, ?, ?, '[]', datetime('now', ?), ?)
  `).run(
    subjectId,
    frecuencia.TIPO_RETARGETING,
    categoria,
    `-${horasAtras} hours`,
    abierta ? new Date().toISOString() : null
  );
}

test.beforeEach(() => {
  raw.prepare('DELETE FROM notification_log').run();
  raw.prepare('DELETE FROM user_notification_preferences').run();
});

// ─── Preferencias ──────────────────────────────────────────────────

test('sin fila de preferencias el sujeto está habilitado (opt-out)', () => {
  assert.strictEqual(frecuencia.estaHabilitado('nuevo'), true);
});

test('desactivar y volver a activar deja una sola fila', () => {
  frecuencia.setHabilitado('u1', frecuencia.TIPO_RETARGETING, false);
  assert.strictEqual(frecuencia.estaHabilitado('u1'), false);

  frecuencia.setHabilitado('u1', frecuencia.TIPO_RETARGETING, true);
  assert.strictEqual(frecuencia.estaHabilitado('u1'), true);

  const { c } = raw.prepare('SELECT COUNT(*) AS c FROM user_notification_preferences').get();
  assert.strictEqual(c, 1);
});

test('un sujeto con el tipo desactivado no recibe nada', () => {
  frecuencia.setHabilitado('u1', frecuencia.TIPO_RETARGETING, false);
  assert.deepStrictEqual(
    frecuencia.puedeEnviar('u1', 'libros'),
    { permitido: false, motivo: 'preferencia_desactivada' }
  );
});

// ─── Capping ───────────────────────────────────────────────────────

test('sin historial se puede enviar', () => {
  assert.strictEqual(frecuencia.puedeEnviar('u1', 'libros').permitido, true);
});

test('no se repite la misma categoría dentro del intervalo mínimo', () => {
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 2 });
  const veredicto = frecuencia.puedeEnviar('u1', 'libros');

  assert.strictEqual(veredicto.permitido, false);
  assert.strictEqual(veredicto.motivo, 'intervalo_categoria');
});

test('pasado el intervalo la misma categoría vuelve a estar disponible', () => {
  sembrarEnvio({
    subjectId: 'u1', categoria: 'libros',
    horasAtras: frecuencia.MIN_HORAS_MISMA_CATEGORIA + 1,
    abierta: true,
  });
  assert.strictEqual(frecuencia.puedeEnviar('u1', 'libros').permitido, true);
});

test('el intervalo es por categoría: otra categoría no queda bloqueada', () => {
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 2 });
  assert.strictEqual(frecuencia.puedeEnviar('u1', 'ropa').permitido, true);
});

test('el tope semanal corta aunque cada categoría sea distinta', () => {
  // Abiertas y repartidas en días distintos: lo único que las frena es el tope.
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 30, abierta: true });
  sembrarEnvio({ subjectId: 'u1', categoria: 'ropa', horasAtras: 60, abierta: true });
  sembrarEnvio({ subjectId: 'u1', categoria: 'comida', horasAtras: 90, abierta: true });

  const veredicto = frecuencia.puedeEnviar('u1', 'electronics');
  assert.strictEqual(frecuencia.MAX_POR_SEMANA, 3);
  assert.strictEqual(veredicto.permitido, false);
  assert.strictEqual(veredicto.motivo, 'tope_semanal');
});

test('lo enviado hace más de una semana ya no cuenta para el tope', () => {
  for (const categoria of ['libros', 'ropa', 'comida']) {
    sembrarEnvio({ subjectId: 'u1', categoria, horasAtras: 24 * 8, abierta: true });
  }
  assert.strictEqual(frecuencia.puedeEnviar('u1', 'electronics').permitido, true);
});

// ─── Reducción adaptativa ──────────────────────────────────────────

test('tres avisos seguidos sin abrir pausan esa categoría', () => {
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 24 * 2 });
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 24 * 3 });
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 24 * 4 });

  assert.strictEqual(frecuencia.ignoradasSeguidas('u1', 'libros'), 3);
  const veredicto = frecuencia.puedeEnviar('u1', 'libros');
  assert.strictEqual(veredicto.permitido, false);
  assert.strictEqual(veredicto.motivo, 'categoria_pausada');
});

test('la pausa se levanta pasados 14 días desde el último aviso', () => {
  const base = 24 * (frecuencia.DIAS_PAUSA_CATEGORIA + 1);
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: base });
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: base + 24 });
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: base + 48 });

  assert.strictEqual(frecuencia.puedeEnviar('u1', 'libros').permitido, true);
});

test('una apertura reciente corta la racha y evita la pausa', () => {
  // Fuera de la semana para que lo que decida sea la racha y no el tope
  // semanal, pero dentro de los 14 días de la pausa.
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 24 * 8, abierta: true });
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 24 * 9 });
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 24 * 10 });

  assert.strictEqual(frecuencia.ignoradasSeguidas('u1', 'libros'), 0);
  assert.strictEqual(frecuencia.puedeEnviar('u1', 'libros').permitido, true);
});

test('un aviso dentro del periodo de gracia no cuenta como ignorado', () => {
  // Tres sin abrir, pero el más reciente es de hace 2h: el usuario aún no ha
  // tenido ocasión de verlo. Sin la gracia, esto se leería como desinterés.
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 2 });
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 24 * 3 });
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 24 * 4 });

  assert.strictEqual(frecuencia.ignoradasSeguidas('u1', 'libros'), 2);
});

test('ignorar el tipo en general duplica el intervalo mínimo', () => {
  // Tres avisos seguidos sin abrir, pero en categorías distintas: ninguna
  // categoría suma 3, así que no hay pausa; lo que hay es un sujeto que
  // ignora este tipo de aviso en general.
  //
  // El más reciente es el de 'libros', a 30h: dentro del intervalo duplicado
  // (48h) y fuera del normal (24h). Los otros dos van a más de 7 días para
  // que el tope semanal, que se evalúa antes, no sea lo que corte.
  sembrarEnvio({ subjectId: 'u1', categoria: 'libros', horasAtras: 30 });
  sembrarEnvio({ subjectId: 'u1', categoria: 'ropa', horasAtras: 24 * 8 });
  sembrarEnvio({ subjectId: 'u1', categoria: 'comida', horasAtras: 24 * 9 });

  const veredicto = frecuencia.puedeEnviar('u1', 'libros');
  assert.strictEqual(
    veredicto.intervaloHoras,
    frecuencia.MIN_HORAS_MISMA_CATEGORIA * frecuencia.MULTIPLICADOR_INTERVALO
  );
  assert.strictEqual(veredicto.permitido, false);
  assert.strictEqual(veredicto.motivo, 'intervalo_categoria');
});

// ─── Registro de envío y apertura ──────────────────────────────────

test('registrarEnvio deja la fila que el capping luego lee', () => {
  frecuencia.registrarEnvio({
    subjectId: 'u1', categoryId: 'libros', productIds: ['p1', 'p2'], notificationId: 'notif_1',
  });

  const fila = raw.prepare('SELECT * FROM notification_log').get();
  assert.strictEqual(fila.subject_id, 'u1');
  assert.strictEqual(fila.type, frecuencia.TIPO_RETARGETING);
  assert.deepStrictEqual(JSON.parse(fila.product_ids), ['p1', 'p2']);
  assert.strictEqual(fila.opened_at, null);
  assert.strictEqual(frecuencia.puedeEnviar('u1', 'libros').permitido, false);
});

test('registrarApertura marca por notificación in-app', () => {
  frecuencia.registrarEnvio({
    subjectId: 'u1', categoryId: 'libros', productIds: ['p1'], notificationId: 'notif_1',
  });

  assert.strictEqual(
    frecuencia.registrarApertura({ subjectId: 'u1', notificationId: 'notif_1' }), 1
  );
  assert.ok(raw.prepare('SELECT opened_at FROM notification_log').get().opened_at);
});

test('registrarApertura cae al último aviso de la categoría si no hay id', () => {
  // Es el camino del sujeto anónimo: recibe el push pero no tiene
  // notificación in-app a la que referirse.
  frecuencia.registrarEnvio({ subjectId: 'anon_x', categoryId: 'libros', productIds: ['p1'] });

  assert.strictEqual(
    frecuencia.registrarApertura({ subjectId: 'anon_x', categoryId: 'libros' }), 1
  );
});

test('abrir dos veces no vuelve a contar', () => {
  frecuencia.registrarEnvio({
    subjectId: 'u1', categoryId: 'libros', productIds: ['p1'], notificationId: 'notif_1',
  });

  frecuencia.registrarApertura({ subjectId: 'u1', notificationId: 'notif_1' });
  assert.strictEqual(
    frecuencia.registrarApertura({ subjectId: 'u1', notificationId: 'notif_1' }), 0
  );
});

test('nadie puede marcar como abierta la notificación de otro', () => {
  frecuencia.registrarEnvio({
    subjectId: 'u1', categoryId: 'libros', productIds: ['p1'], notificationId: 'notif_1',
  });

  assert.strictEqual(
    frecuencia.registrarApertura({ subjectId: 'intruso', notificationId: 'notif_1' }), 0
  );
  assert.strictEqual(raw.prepare('SELECT opened_at FROM notification_log').get().opened_at, null);
});
