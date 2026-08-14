// Procesamiento del webhook de Mercado Pago: reintentos de una entrega que
// falló a medias, reconciliación por external_reference y los efectos que
// una aprobación tardía tiene que producir igual que una síncrona.
//
// mpClient.obtenerPago se sustituye por un doble de prueba ANTES de requerir
// webhook.js/routes.js, así se controla exactamente cuándo falla y cuándo
// tiene éxito sin llamar a la API real de Mercado Pago.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');
const crypto = require('node:crypto');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-webhook-retry-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';
process.env.MP_PUBLIC_KEY = 'TEST-public-key';
process.env.MP_ACCESS_TOKEN = 'TEST-access-token';
process.env.MP_CLIENT_ID = 'TEST-client-id';
process.env.MP_CLIENT_SECRET = 'TEST-client-secret';
process.env.MP_WEBHOOK_SECRET = 'TEST-webhook-secret';
process.env.PAYMENTS_ENCRYPTION_KEY = crypto.randomBytes(32).toString('hex');
process.env.PLATFORM_FEE_PERCENT = '5';
process.env.APP_PUBLIC_URL = 'https://ejemplo.test';

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');

db.initDatabase();

// ─── Doble de prueba de mpClient.obtenerPago ────────────────────
const mpClient = require('./mpClient');
let respuestaObtenerPago; // función controlada por cada test
mpClient.obtenerPago = async (paymentId, accessToken) => respuestaObtenerPago(paymentId, accessToken);

const store = require('./store');
const { capturandoLogs } = require('./testUtils');
const { register } = require('./routes');

let baseUrl;
let servidor;

test.before(async () => {
  const app = express();
  app.use(express.json());
  register(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

let contador = 0;
function crearUsuario({ tipoCuenta = 'estudiante' } = {}) {
  const id = `u_wh_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta)
     VALUES (?, ?, ?, 'TT', '', ?, 1, ?)`,
  ).run(id, `Test ${id}`, `${id}@ejemplo.com`, tipoCuenta === 'negocio' ? 1 : 0, tipoCuenta);
  return { id, token: generateToken(id) };
}

function crearProducto(sellerId, precio) {
  const id = `p_wh_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO products (id, title, price, priceNum, seller, category)
     VALUES (?, ?, ?, ?, ?, 'otros')`,
  ).run(id, `Producto ${id}`, `$${precio}`, precio, sellerId);
  return id;
}

function firmar({ dataId, requestId, ts, secreto = 'TEST-webhook-secret' }) {
  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  return crypto.createHmac('sha256', secreto).update(manifest).digest('hex');
}

async function enviarWebhook({ paymentId, requestId, eventId }) {
  const ts = Math.floor(Date.now() / 1000);
  const v1 = firmar({ dataId: paymentId, requestId, ts });
  const res = await fetch(
    `${baseUrl}/api/payments/webhook?data.id=${paymentId}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-signature': `ts=${ts},v1=${v1}`,
        'x-request-id': requestId,
      },
      body: JSON.stringify({ type: 'payment', data: { id: paymentId }, id: eventId }),
    },
  );
  return res.status;
}

// Espera activa a que procesarEvento (disparado sin await tras el 200)
// termine, sondeando el estado de la orden.
async function esperar(fn, { intentos = 40, esperaMs = 10 } = {}) {
  for (let i = 0; i < intentos; i++) {
    if (fn()) return true;
    await new Promise(r => setTimeout(r, esperaMs));
  }
  return false;
}

test('un reintento de MP con el mismo event_id se reprocesa si el intento anterior falló', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(vendedor.id, 100);
  const orden = store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: 100, applicationFee: 5, currency: 'MXN', origin: 'direct',
    items: [{ productId: producto, quantity: 1, unitPrice: 100, title: 'X' }],
  });
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: 'pay_retry_1' }); // simula checkout previo

  const eventId = `evt_${crypto.randomUUID()}`;

  // Primer intento: obtenerPago revienta (timeout, 5xx de MP, lo que sea).
  respuestaObtenerPago = async () => { throw new Error('MP no respondió'); };
  const status1 = await enviarWebhook({ paymentId: 'pay_retry_1', requestId: 'req-a', eventId });
  assert.strictEqual(status1, 200); // MP siempre ve 200: el trabajo real es async.

  // Se le da tiempo al procesamiento asíncrono fallido para terminar.
  await new Promise(r => setTimeout(r, 50));
  assert.strictEqual(
    store.getOrdenPorId(orden.id).payment_status, null,
    'el primer intento debió fallar sin actualizar la orden',
  );

  // MP reintenta la MISMA entrega (mismo event_id) porque nunca vio éxito.
  respuestaObtenerPago = async () => ({ id: 'pay_retry_1', status: 'approved', external_reference: orden.id });
  const status2 = await enviarWebhook({ paymentId: 'pay_retry_1', requestId: 'req-a', eventId });
  assert.strictEqual(status2, 200);

  const seActualizo = await esperar(
    () => store.getOrdenPorId(orden.id).payment_status === 'approved',
  );
  assert.ok(seActualizo, 'el reintento debió reprocesar el evento y actualizar la orden a approved');
});

test('la reconciliación por external_reference usa el token del vendedor, no el de la plataforma', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(vendedor.id, 70);
  const orden = store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: 70, applicationFee: 3.5, currency: 'MXN', origin: 'direct',
    items: [{ productId: producto, quantity: 1, unitPrice: 70, title: 'X' }],
  });
  // NO se guarda mp_payment_id todavía: es justo el caso que obliga a
  // localizar la orden por external_reference en vez de por mp_payment_id.

  const tokenVendedor = 'vendor-access-token-xyz';
  store.guardarCuentaVendedor(vendedor.id, {
    mpUserId: 'mp_user_1', accessToken: tokenVendedor, refreshToken: 'r', expiresIn: 3600,
  });

  const paymentId = 'pay_extref_1';
  const eventId = `evt_${crypto.randomUUID()}`;

  // El primer intento (token de la orden aún desconocido) se resuelve con el
  // fallback de plataforma y devuelve datos; ahí se descubre external_reference.
  // Pero la versión AUTORITATIVA — la que debe quedar guardada — es la que
  // se consulta con el token del vendedor, que es quien de verdad puede leer
  // ese pago. Si el código nunca busca ese token para este camino, la orden
  // se queda con el estado (parcial/no autoritativo) de la consulta de
  // plataforma en vez del de la consulta con el token del vendedor.
  respuestaObtenerPago = async (id, accessToken) => {
    if (accessToken === tokenVendedor) {
      return { id: paymentId, status: 'approved', external_reference: orden.id };
    }
    return { id: paymentId, status: 'pending', external_reference: orden.id };
  };

  const status = await enviarWebhook({ paymentId, requestId: 'req-extref', eventId });
  assert.strictEqual(status, 200);

  const seActualizo = await esperar(
    () => store.getOrdenPorId(orden.id).payment_status === 'approved',
  );
  assert.ok(
    seActualizo,
    `la orden debió quedar 'approved' (consulta con token de vendedor), quedó '${store.getOrdenPorId(orden.id).payment_status}'`,
  );
});

test('una aprobación que llega por webhook vacía el carrito igual que una síncrona', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(vendedor.id, 120);

  // El comprador tenía el producto en el carrito y pagó desde ahí.
  db.upsertCartItem(comprador.id, { productId: producto, quantity: 1 });
  assert.strictEqual(db.getCartItems(comprador.id).length, 1);

  const orden = store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: 120, applicationFee: 6, currency: 'MXN', origin: 'cart',
    items: [{ productId: producto, quantity: 1, unitPrice: 120, title: 'X' }],
  });

  // MP no aprobó en el momento: dejó el pago en revisión, así que el checkout
  // no pudo vaciar nada. La aprobación llega después, y esta notificación es
  // el ÚNICO aviso que habrá.
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: 'pay_carrito', paymentStatus: 'in_process' });

  const eventId = `evt_${crypto.randomUUID()}`;
  respuestaObtenerPago = async () => ({
    id: 'pay_carrito', status: 'approved', external_reference: orden.id,
  });

  const status = await enviarWebhook({ paymentId: 'pay_carrito', requestId: 'req-cart', eventId });
  assert.strictEqual(status, 200);

  const aprobada = await esperar(
    () => store.getOrdenPorId(orden.id).payment_status === 'approved',
  );
  assert.ok(aprobada, 'la orden debió quedar aprobada');

  // Si no se vacía, el comprador vuelve a encontrar en su carrito algo que ya
  // pagó — listo para pagarlo por segunda vez.
  const vaciado = await esperar(() => db.getCartItems(comprador.id).length === 0);
  assert.ok(vaciado,
    'los productos de una orden de carrito ya pagada no pueden seguir en el carrito');
});

test('una orden que no venía del carrito no toca el carrito del comprador', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const productoComprado = crearProducto(vendedor.id, 50);
  const otroProducto = crearProducto(vendedor.id, 90);

  // Compra directa de un producto, mientras el carrito tiene otras cosas
  // pendientes que no se están pagando aquí.
  db.upsertCartItem(comprador.id, { productId: otroProducto, quantity: 2 });

  const orden = store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: 50, applicationFee: 2.5, currency: 'MXN', origin: 'direct',
    items: [{ productId: productoComprado, quantity: 1, unitPrice: 50, title: 'X' }],
  });
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: 'pay_directo', paymentStatus: 'in_process' });

  respuestaObtenerPago = async () => ({
    id: 'pay_directo', status: 'approved', external_reference: orden.id,
  });
  await enviarWebhook({
    paymentId: 'pay_directo', requestId: 'req-directo', eventId: `evt_${crypto.randomUUID()}`,
  });

  await esperar(() => store.getOrdenPorId(orden.id).payment_status === 'approved');
  await new Promise(r => setTimeout(r, 30));

  assert.strictEqual(db.getCartItems(comprador.id).length, 1,
    'una compra directa no puede llevarse por delante el carrito');
});

// ─── Los finales mudos del webhook ──────────────────────────────
//
// procesarEvento tiene varias salidas por `return` en las que no pasaba
// nada y no se escribía nada. Desde el log, "MP nunca nos avisó", "nos
// avisó y no pudimos leer el pago" y "lo leímos y la orden no cambió" se
// veían exactamente igual: silencio. Son tres problemas distintos —red,
// credenciales y estado— y perseguir el equivocado cuesta horas.
//
// Estas pruebas fijan que cada final deja su línea. No comprueban el texto
// exacto, sino que el dato que hace falta para actuar esté ahí.


test('un pago que MP no devuelve deja constancia en el log', async () => {
  const paymentId = 'pay_ilegible';
  respuestaObtenerPago = async () => null;

  const logs = await capturandoLogs(async () => {
    await enviarWebhook({
      paymentId, requestId: 'req-ilegible', eventId: `evt_${crypto.randomUUID()}`,
    });
    // procesarEvento corre sin await, tras el 200.
    await new Promise(r => setTimeout(r, 80));
  });

  assert.ok(logs.includes(paymentId),
    `no se registró que el pago ${paymentId} no se pudo leer:\n${logs}`);
});

test('un pago sin orden asociada registra el external_reference que traía', async () => {
  // Sin este dato el aviso es inaccionable: dice que algo falló, no qué
  // buscar. Con el external_reference se puede ir a la BD a mirar.
  const paymentId = 'pay_huerfano';
  respuestaObtenerPago = async () => ({
    id: paymentId, status: 'approved', external_reference: 'ord_que_no_existe',
  });

  const logs = await capturandoLogs(async () => {
    await enviarWebhook({
      paymentId, requestId: 'req-huerfano', eventId: `evt_${crypto.randomUUID()}`,
    });
    await new Promise(r => setTimeout(r, 80));
  });

  assert.ok(logs.includes('ord_que_no_existe'),
    `el aviso no dice qué orden se buscó:\n${logs}`);
});
