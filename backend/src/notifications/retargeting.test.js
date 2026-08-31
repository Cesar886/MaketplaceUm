// Tests del job de retargeting: de la cola de productos publicados al envío.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const tmpDb = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-retargeting-')),
  'test.db'
);
process.env.MERCADITO_DB_PATH = tmpDb;

const db = require('../database');
db.initDatabase();
const raw = db.getDb();

const retargeting = require('./retargeting');
const frecuencia = require('./frecuencia');
const interes = require('./interes');

function sembrarCategoria(id, nombre) {
  raw.prepare('INSERT OR IGNORE INTO categories (id, name) VALUES (?, ?)').run(id, nombre);
}

function sembrarProducto({ id, categoria, vendedor, titulo = `Producto ${id}`, precio = 100 }) {
  raw.prepare(`
    INSERT OR REPLACE INTO products (id, title, price, priceNum, category, seller, created_at)
    VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
  `).run(id, titulo, String(precio), precio, categoria, vendedor);
}

/** Deja a `subjectId` por encima del umbral de interés en `categoria`. */
function sembrarInteres(subjectId, categoria) {
  raw.prepare(`
    INSERT INTO interacciones_dispositivo (device_id, user_id, product_id, category, tipo, created_at)
    VALUES (?, ?, NULL, ?, 'contacto', datetime('now'))
  `).run(subjectId, subjectId.startsWith('anon_') ? null : subjectId, categoria);
}

/** Registra un token FCM para el sujeto, que es su único canal si es anónimo. */
function sembrarToken(subjectId) {
  raw.prepare(`
    INSERT OR IGNORE INTO push_tokens (user_id, player_id, platform, created_at)
    VALUES (?, ?, 'android', datetime('now'))
  `).run(subjectId, `token_${subjectId}`);
}

test.beforeEach(() => {
  for (const tabla of [
    'interacciones_dispositivo', 'user_category_interest', 'notification_log',
    'user_notification_preferences', 'interest_notification_queue',
    'category_interests', 'notifications', 'products', 'push_tokens',
  ]) {
    raw.prepare(`DELETE FROM ${tabla}`).run();
  }
  sembrarCategoria('libros', 'Libros');
  sembrarCategoria('ropa', 'Ropa');
});

test('un producto nuevo alcanza a quien mostró interés en su categoría', async () => {
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  sembrarInteres('interesado', 'libros');
  retargeting.encolarProducto('p1');

  const resumen = await retargeting.ejecutarJobRetargeting();

  assert.strictEqual(resumen.lote, 1);
  assert.strictEqual(resumen.enviados, 1);

  const log = raw.prepare('SELECT * FROM notification_log').get();
  assert.strictEqual(log.subject_id, 'interesado');
  assert.strictEqual(log.category_id, 'libros');
  assert.deepStrictEqual(JSON.parse(log.product_ids), ['p1']);
});

test('quien no mostró interés no recibe nada', async () => {
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  sembrarInteres('interesado', 'ropa');
  retargeting.encolarProducto('p1');

  const resumen = await retargeting.ejecutarJobRetargeting();
  assert.strictEqual(resumen.enviados, 0);
});

test('el vendedor no recibe aviso de su propia publicación', async () => {
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  sembrarInteres('vendedor', 'libros');
  retargeting.encolarProducto('p1');

  const resumen = await retargeting.ejecutarJobRetargeting();
  assert.strictEqual(resumen.enviados, 0);
  assert.strictEqual(resumen.omitidos.es_el_vendedor, 1);
});

test('varias publicaciones de la misma categoría van en un solo aviso', async () => {
  for (const id of ['p1', 'p2', 'p3']) {
    sembrarProducto({ id, categoria: 'libros', vendedor: 'vendedor' });
    retargeting.encolarProducto(id);
  }
  sembrarInteres('interesado', 'libros');

  const resumen = await retargeting.ejecutarJobRetargeting();

  assert.strictEqual(resumen.enviados, 1, 'tres productos no pueden ser tres pushes');
  const log = raw.prepare('SELECT * FROM notification_log').get();
  assert.deepStrictEqual(JSON.parse(log.product_ids).sort(), ['p1', 'p2', 'p3']);
});

test('un sujeto interesado en dos categorías recibe un único aviso por pasada', async () => {
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  sembrarProducto({ id: 'p2', categoria: 'ropa', vendedor: 'vendedor' });
  retargeting.encolarProducto('p1');
  retargeting.encolarProducto('p2');
  sembrarInteres('interesado', 'libros');
  sembrarInteres('interesado', 'ropa');

  const resumen = await retargeting.ejecutarJobRetargeting();

  assert.strictEqual(resumen.enviados, 1);
  assert.strictEqual(resumen.omitidos.ya_avisado_en_esta_pasada, 1);
});

test('la segunda pasada no vuelve a anunciar lo ya procesado', async () => {
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  sembrarInteres('interesado', 'libros');
  retargeting.encolarProducto('p1');

  await retargeting.ejecutarJobRetargeting();
  const segunda = await retargeting.ejecutarJobRetargeting();

  assert.strictEqual(segunda.lote, 0);
  assert.strictEqual(segunda.enviados, 0);
  const { c } = raw.prepare('SELECT COUNT(*) AS c FROM notification_log').get();
  assert.strictEqual(c, 1);
});

test('el capping frena el segundo aviso de la misma categoría', async () => {
  sembrarInteres('interesado', 'libros');

  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  retargeting.encolarProducto('p1');
  await retargeting.ejecutarJobRetargeting();

  sembrarProducto({ id: 'p2', categoria: 'libros', vendedor: 'vendedor' });
  retargeting.encolarProducto('p2');
  const segunda = await retargeting.ejecutarJobRetargeting();

  assert.strictEqual(segunda.lote, 1, 'el producto sí entra al lote');
  assert.strictEqual(segunda.enviados, 0, 'pero no se envía');
  assert.strictEqual(segunda.omitidos.intervalo_categoria, 1);
});

test('un sujeto con el tipo desactivado queda fuera', async () => {
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  sembrarInteres('interesado', 'libros');
  frecuencia.setHabilitado('interesado', frecuencia.TIPO_RETARGETING, false);
  retargeting.encolarProducto('p1');

  const resumen = await retargeting.ejecutarJobRetargeting();
  assert.strictEqual(resumen.enviados, 0);
  assert.strictEqual(resumen.omitidos.preferencia_desactivada, 1);
});

test('una cuenta recibe además notificación in-app; un anónimo solo el push', async () => {
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  sembrarInteres('cuenta', 'libros');
  sembrarInteres('anon_abc', 'libros');
  sembrarToken('anon_abc');
  retargeting.encolarProducto('p1');

  const resumen = await retargeting.ejecutarJobRetargeting();
  assert.strictEqual(resumen.enviados, 2);

  const inApp = raw.prepare('SELECT user_id FROM notifications').all();
  assert.deepStrictEqual(inApp.map(f => f.user_id), ['cuenta']);

  const anon = raw.prepare(
    'SELECT notification_id FROM notification_log WHERE subject_id = ?'
  ).get('anon_abc');
  assert.strictEqual(anon.notification_id, null);
});

test('el producto encolado dos veces se anuncia una sola vez', async () => {
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  retargeting.encolarProducto('p1');
  retargeting.encolarProducto('p1');

  const { c } = raw.prepare('SELECT COUNT(*) AS c FROM interest_notification_queue').get();
  assert.strictEqual(c, 1);
});

test('una fila en cola cuyo producto ya no existe se descarta, no se reintenta', async () => {
  retargeting.encolarProducto('fantasma');

  const primera = await retargeting.ejecutarJobRetargeting();
  assert.strictEqual(primera.lote, 0, 'el JOIN la descarta');

  const segunda = await retargeting.ejecutarJobRetargeting();
  assert.strictEqual(segunda.lote, 0);
  const pendientes = raw.prepare(
    'SELECT COUNT(*) AS c FROM interest_notification_queue WHERE processed_at IS NULL'
  ).get();
  assert.strictEqual(pendientes.c, 0, 'no puede quedarse dando vueltas en la cola');
});

test('el mensaje cambia según por qué le toca al sujeto', () => {
  const productos = [{ productId: 'p1', title: 'Cálculo I', priceNum: 250 }];

  const match = retargeting.redactarMensaje({
    motivo: 'interest_match', nombreCategoria: 'Libros', productos,
  });
  const follow = retargeting.redactarMensaje({
    motivo: 'category_follow', nombreCategoria: 'Libros', productos,
  });

  assert.match(match.titulo, /viste/);
  assert.doesNotMatch(follow.titulo, /viste/);
  assert.strictEqual(match.cuerpo, 'Cálculo I — $250');
});

test('con varias publicaciones el cuerpo las resume en vez de listar una', () => {
  const { cuerpo } = retargeting.redactarMensaje({
    motivo: 'interest_match',
    nombreCategoria: 'Libros',
    productos: [{ title: 'a', priceNum: 1 }, { title: 'b', priceNum: 2 }],
  });
  assert.match(cuerpo, /^2 publicaciones/);
});

test('el job aplica el decaimiento antes de decidir a quién avisar', async () => {
  // Interés de hace 3 días: supera el umbral pero no la ventana de frescura
  // de 48h, así que refrescarInteres + getSujetosElegibles lo dejan fuera.
  raw.prepare(`
    INSERT INTO interacciones_dispositivo (device_id, user_id, product_id, category, tipo, created_at)
    VALUES ('d1', 'viejo', NULL, 'libros', 'contacto', datetime('now', '-3 days'))
  `).run();
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  retargeting.encolarProducto('p1');

  const resumen = await retargeting.ejecutarJobRetargeting();

  assert.strictEqual(resumen.enviados, 0);
  const snapshot = raw.prepare('SELECT decay_status FROM user_category_interest').get();
  assert.strictEqual(snapshot.decay_status, 'decaying', 'el snapshot sí se refrescó');
});

test('un anónimo sin token FCM no consume cupo ni ensucia el open rate', async () => {
  // Un sujeto anónimo no recibe notificación in-app (esa se lee desde la
  // campana, que exige sesión), así que sin token no tiene ningún canal por
  // el que enterarse. Registrar el envío igualmente le gastaría uno de sus
  // tres avisos semanales y, a los tres, la reducción adaptativa pausaría la
  // categoría por no abrir algo que nunca llegó a existir.
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  sembrarInteres('anon_sin_token', 'libros');
  retargeting.encolarProducto('p1');

  const resumen = await retargeting.ejecutarJobRetargeting();

  assert.strictEqual(resumen.enviados, 0);
  assert.strictEqual(resumen.omitidos.sin_canal_de_entrega, 1);
  const { c } = raw.prepare('SELECT COUNT(*) AS c FROM notification_log').get();
  assert.strictEqual(c, 0, 'no debe quedar una fila "enviada" que nadie podrá abrir');
});

test('una cuenta sin token FCM sí recibe el aviso: le queda la campana', async () => {
  sembrarProducto({ id: 'p1', categoria: 'libros', vendedor: 'vendedor' });
  sembrarInteres('cuenta_sin_token', 'libros');
  retargeting.encolarProducto('p1');

  const resumen = await retargeting.ejecutarJobRetargeting();

  assert.strictEqual(resumen.enviados, 1);
  const inApp = raw.prepare('SELECT user_id FROM notifications').all();
  assert.deepStrictEqual(inApp.map(f => f.user_id), ['cuenta_sin_token']);
});

test('con el lote lleno y huérfanos en cola, nada se anuncia dos veces', () => {
  // El huérfano (producto borrado) ocupa sitio en la cola pero no en el
  // resultado. Si el marcado de procesadas usa un LIMIT distinto al de la
  // lectura, los dos conjuntos se desalinean y las últimas filas del lote se
  // devuelven ya anunciadas en la pasada siguiente.
  for (const id of ['p2', 'p3', 'p4']) {
    sembrarProducto({ id, categoria: 'libros', vendedor: 'vendedor' });
  }
  const encolarEn = (productId, segundos) => raw.prepare(`
    INSERT INTO interest_notification_queue (product_id, created_at)
    VALUES (?, datetime('now', '-' || ? || ' seconds'))
  `).run(productId, segundos);

  encolarEn('p_huerfano', 40);
  encolarEn('p2', 30);
  encolarEn('p3', 20);
  encolarEn('p4', 10);

  const lote1 = retargeting.tomarLotePendiente(3);
  const lote2 = retargeting.tomarLotePendiente(3);

  assert.deepStrictEqual(lote1.map(f => f.productId), ['p2', 'p3']);
  assert.deepStrictEqual(lote2.map(f => f.productId), ['p4']);
  const pendientes = raw.prepare(
    'SELECT COUNT(*) AS c FROM interest_notification_queue WHERE processed_at IS NULL'
  ).get();
  assert.strictEqual(pendientes.c, 0, 'la cola queda vacía tras dos pasadas');
});
