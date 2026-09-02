// Insignias élite: las difíciles de verdad.
//
// A diferencia de las insignias básicas (Novato, Aniversario, Responde
// rápido), estas exigen historial acumulado: decenas de ventas, dinero
// facturado, cientos de calificaciones perfectas. Los tests fijan el umbral
// por los dos lados —justo debajo NO se otorga, justo en el umbral SÍ—
// porque un ">=" escrito como ">" pasaría desapercibido en cualquier prueba
// que solo probara el caso holgado.
//
// Mismo patrón de integración que sellers.test.js: Express real y SQLite
// temporal con el schema real.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-badges-elite-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');
const { sellers, registerSeller } = require('../data');
const sellersRoute = require('./sellers');

db.initDatabase();

let baseUrl;
let servidor;

test.before(async () => {
  const app = express();
  app.use(express.json());
  sellersRoute.register(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

let contador = 0;

function crearVendedor({ email = null } = {}) {
  const id = `seller_elite_${++contador}`;
  registerSeller({
    id,
    name: `Elite ${id}`,
    email,
    avatarInitials: 'EE',
    major: '',
    isBusiness: false,
    verified: true,
    tipo_cuenta: 'estudiante',
  });
  db.refrescarCuentasDueno();
  return id;
}

/** Órdenes pagadas del vendedor: es lo que cuenta como venta confirmada. */
function crearVentas(sellerId, cantidad, monto = 100) {
  const stmt = db.getDb().prepare(
    `INSERT INTO orders (id, buyer_id, vendor_id, amount, status)
     VALUES (?, ?, ?, ?, 'paid')`,
  );
  const comprador = crearVendedor();
  for (let i = 0; i < cantidad; i++) {
    stmt.run(`ord_${sellerId}_${i}`, comprador, sellerId, monto);
  }
}

/**
 * Calificaciones sobre un producto del vendedor. Cada una necesita un
 * usuario distinto: la PK de product_ratings es (product_id, user_id), así
 * que reusar el mismo comprador sobrescribiría la anterior en vez de sumar.
 */
function crearCalificaciones(sellerId, cantidad, estrellas) {
  const productoId = `prod_${sellerId}_${estrellas}`;
  db.getDb()
    .prepare(
      `INSERT INTO products (id, title, price, category, seller, description, images)
       VALUES (?, 'Producto', 100, 'otros', ?, '', '[]')`,
    )
    .run(productoId, sellerId);

  const stmt = db.getDb().prepare(
    'INSERT INTO product_ratings (product_id, user_id, stars) VALUES (?, ?, ?)',
  );
  for (let i = 0; i < cantidad; i++) {
    stmt.run(productoId, `rater_${productoId}_${i}`, estrellas);
  }
  // El perfil lee `sellers.rating`/`reviews`, que es caché de esta tabla...
  db.syncSellerRating(sellerId);
  // ...y la ruta sirve desde la lista en memoria de data.js, que no se entera
  // de un UPDATE hecho por fuera. En producción la recarga la propia ruta que
  // escribe la calificación; aquí hay que hacerla a mano.
  sellers.length = 0;
  sellers.push(...db.getSellers());
}

function crearPreguntas(sellerId, { total, respondidas }) {
  const productoId = `prodq_${sellerId}`;
  db.getDb()
    .prepare(
      `INSERT INTO products (id, title, price, category, seller, description, images)
       VALUES (?, 'Producto', 100, 'otros', ?, '', '[]')`,
    )
    .run(productoId, sellerId);

  const stmt = db.getDb().prepare(
    `INSERT INTO product_questions
       (id, product_id, seller_id, asked_by, question_text, answer_text, status, answered_at)
     VALUES (?, ?, ?, 'alguien', '¿Sigue disponible?', ?, ?, ?)`,
  );
  for (let i = 0; i < total; i++) {
    const contestada = i < respondidas;
    stmt.run(
      `q_${sellerId}_${i}`,
      productoId,
      sellerId,
      contestada ? 'Sí, disponible.' : null,
      contestada ? 'answered' : 'pending',
      contestada ? '2026-01-01 00:00:00' : null,
    );
  }
}

async function perfil(id) {
  const res = await fetch(`${baseUrl}/api/sellers/${id}`);
  return res.json();
}

// ═══ Leyenda del Mercadito: 100 ventas confirmadas ═══════════

test('con 99 ventas todavía no es Leyenda', async () => {
  const id = crearVendedor();
  crearVentas(id, 99);

  assert.strictEqual((await perfil(id)).leyendaMercadito, false);
});

test('la venta número 100 otorga la Leyenda del Mercadito', async () => {
  const id = crearVendedor();
  crearVentas(id, 100);

  assert.strictEqual((await perfil(id)).leyendaMercadito, true);
});

// ═══ Vendedor de oro: $100,000 MXN facturados ════════════════

test('con $99,900 facturados todavía no hay insignia de monto', async () => {
  const id = crearVendedor();
  crearVentas(id, 999, 100);

  assert.strictEqual((await perfil(id)).vendedorDeOro, false);
});

test('al llegar a $100,000 facturados se otorga Vendedor de oro', async () => {
  const id = crearVendedor();
  crearVentas(id, 100, 1000);

  assert.strictEqual((await perfil(id)).vendedorDeOro, true);
});

test('solo cuentan las órdenes pagadas para el monto facturado', async () => {
  const id = crearVendedor();
  crearVentas(id, 100, 1000);
  db.getDb()
    .prepare("UPDATE orders SET status = 'cancelled' WHERE vendor_id = ?")
    .run(id);

  assert.strictEqual((await perfil(id)).vendedorDeOro, false);
});

// ═══ Impecable: 5.0 de promedio con 50 reseñas ═══════════════

test('con 49 reseñas perfectas todavía no hay insignia Impecable', async () => {
  const id = crearVendedor();
  crearCalificaciones(id, 49, 5);

  assert.strictEqual((await perfil(id)).ratingPerfecto, false);
});

test('con 50 reseñas y promedio 5.0 se otorga Impecable', async () => {
  const id = crearVendedor();
  crearCalificaciones(id, 50, 5);

  assert.strictEqual((await perfil(id)).ratingPerfecto, true);
});

test('una sola calificación de 4 estrellas rompe el promedio perfecto', async () => {
  const id = crearVendedor();
  crearCalificaciones(id, 60, 5);
  crearCalificaciones(id, 1, 4);

  const p = await perfil(id);
  assert.strictEqual(p.ratingPerfecto, false);
  // Pero sigue siendo confiable: la insignia de abajo no se pierde.
  assert.strictEqual(p.vendedorConfiable, true);
});

// ═══ Centenario: 100 calificaciones de 5 estrellas ═══════════

test('con 99 cincos todavía no hay Centenario', async () => {
  const id = crearVendedor();
  crearCalificaciones(id, 99, 5);

  assert.strictEqual((await perfil(id)).cienCincoEstrellas, false);
});

test('el quinto ciento de estrellas otorga Centenario', async () => {
  const id = crearVendedor();
  crearCalificaciones(id, 100, 5);

  assert.strictEqual((await perfil(id)).cienCincoEstrellas, true);
});

test('Centenario cuenta solo los cincos, no el total de reseñas', async () => {
  const id = crearVendedor();
  crearCalificaciones(id, 99, 5);
  crearCalificaciones(id, 40, 3);

  assert.strictEqual((await perfil(id)).cienCincoEstrellas, false);
});

// ═══ Siempre responde: 95% de 20 preguntas o más ═════════════

test('con 19 preguntas todas respondidas aún no hay Siempre responde', async () => {
  const id = crearVendedor();
  crearPreguntas(id, { total: 19, respondidas: 19 });

  assert.strictEqual((await perfil(id)).siempreResponde, false);
});

test('20 preguntas con 19 respondidas (95%) otorgan Siempre responde', async () => {
  const id = crearVendedor();
  crearPreguntas(id, { total: 20, respondidas: 19 });

  assert.strictEqual((await perfil(id)).siempreResponde, true);
});

test('20 preguntas con 18 respondidas (90%) no bastan', async () => {
  const id = crearVendedor();
  crearPreguntas(id, { total: 20, respondidas: 18 });

  assert.strictEqual((await perfil(id)).siempreResponde, false);
});

test('un vendedor sin preguntas no recibe la insignia por vacío', async () => {
  const id = crearVendedor();

  assert.strictEqual((await perfil(id)).siempreResponde, false);
});

// ═══ Cuentas del dueño: todas desbloqueadas ══════════════════

test('una cuenta del dueño trae las cinco insignias élite sin métricas reales', async () => {
  const id = crearVendedor({ email: 'cesar8herrera@gmail.com' });

  const p = await perfil(id);
  assert.strictEqual(p.leyendaMercadito, true);
  assert.strictEqual(p.vendedorDeOro, true);
  assert.strictEqual(p.ratingPerfecto, true);
  assert.strictEqual(p.cienCincoEstrellas, true);
  assert.strictEqual(p.siempreResponde, true);
});

// ═══ Concesiones permanentes ═════════════════════════════════
//
// Las tres insignias de acumulado de por vida (Leyenda, Vendedor de oro,
// Centenario) se registran en `insignias_otorgadas` la primera vez que se
// cumplen. Es lo que hace que subir un umbral —como el de Leyenda, que pasó
// de 50 a 100 ventas— no se la quite a quien ya la había ganado.

function otorgadas(sellerId) {
  return db.getInsigniasOtorgadas(sellerId);
}

test('ganar una insignia de por vida la deja registrada', async () => {
  const id = crearVendedor();
  crearVentas(id, 100);

  assert.strictEqual(otorgadas(id).has('leyenda'), false);
  await perfil(id);
  assert.strictEqual(otorgadas(id).has('leyenda'), true);
});

test('quien la ganó con el umbral viejo la conserva si el umbral sube', async () => {
  // 60 ventas: bastaban con el umbral anterior (50), no con el de ahora
  // (100). Con la concesión ya registrada, el perfil la sigue mostrando.
  const id = crearVendedor();
  crearVentas(id, 60);
  assert.strictEqual((await perfil(id)).leyendaMercadito, false);

  db.registrarInsigniaOtorgada(id, 'leyenda');

  assert.strictEqual((await perfil(id)).leyendaMercadito, true);
});

test('las insignias que sí se pueden perder no se registran', async () => {
  // Impecable describe cómo va el vendedor AHORA, no un acumulado: la
  // primera reseña que no sea un cinco tiene que quitarla.
  const id = crearVendedor();
  crearCalificaciones(id, 50, 5);
  assert.strictEqual((await perfil(id)).ratingPerfecto, true);
  assert.strictEqual(otorgadas(id).has('impecable'), false);

  crearCalificaciones(id, 1, 4);

  assert.strictEqual((await perfil(id)).ratingPerfecto, false);
});

test('las cuentas del dueño no ensucian el registro de concesiones', async () => {
  // Las llevan todas por excepción, no por haberlas ganado.
  // Otro correo del dueño: el de arriba ya lo usa el test de las cinco
  // insignias, y `sellers.email` es único.
  const id = crearVendedor({ email: 'cesar4herrera@gmail.com' });

  assert.strictEqual((await perfil(id)).leyendaMercadito, true);
  assert.strictEqual(otorgadas(id).size, 0);
});
