// Pagos con Mercado Pago: cifrado en reposo, comisión, firma del webhook,
// idempotencia y —lo más importante— las comprobaciones de pertenencia.
//
// Ninguno de estos tests llama a la API real de Mercado Pago. Se prueban los
// caminos que deben cortar ANTES de llegar a MP, que son justo los que
// protegen dinero ajeno: una tarjeta de otro usuario, una orden de otro
// comprador, un vendedor sin cuenta conectada.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');
const crypto = require('node:crypto');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-payments-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

// Credenciales FALSAS, solo para que los endpoints no respondan 503. No
// tienen ningún valor real y nunca salen de este proceso.
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

const { cifrar, descifrar } = require('./crypto');
const { calcularComision, redondear2 } = require('./fees');
const { validarFirma } = require('./webhook');
const store = require('./store');
const { register } = require('./routes');

// ─── Servidor de pruebas ─────────────────────────────────────

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

// ─── Helpers ─────────────────────────────────────────────────

let contador = 0;

function crearUsuario({ tipoCuenta = 'estudiante', verificado = true } = {}) {
  const id = `u_pay_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta)
     VALUES (?, ?, ?, 'TT', '', ?, ?, ?)`,
  ).run(id, `Test ${id}`, `${id}@ejemplo.com`, tipoCuenta === 'negocio' ? 1 : 0,
        verificado ? 1 : 0, tipoCuenta);
  return { id, token: generateToken(id) };
}

function crearProducto(sellerId, precio) {
  const id = `p_pay_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO products (id, title, price, priceNum, seller, category)
     VALUES (?, ?, ?, ?, ?, 'otros')`,
  ).run(id, `Producto ${id}`, `$${precio}`, precio, sellerId);
  return id;
}

async function pedir(metodo, ruta, { token, body } = {}) {
  const res = await fetch(`${baseUrl}${ruta}`, {
    method: metodo,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const texto = await res.text();
  let datos = null;
  try { datos = texto ? JSON.parse(texto) : null; } catch { datos = texto; }
  return { status: res.status, datos };
}

// ─── Cifrado en reposo ───────────────────────────────────────

test('el token cifrado no contiene el valor original en claro', () => {
  const token = 'APP_USR-1234567890-token-secreto-del-vendedor';
  const cifrado = cifrar(token);
  assert.ok(!cifrado.includes(token));
  assert.ok(!cifrado.includes('secreto'));
  assert.strictEqual(descifrar(cifrado), token);
});

test('cifrar el mismo valor dos veces da resultados distintos (IV aleatorio)', () => {
  assert.notStrictEqual(cifrar('mismo-token'), cifrar('mismo-token'));
});

test('descifrar detecta manipulación en vez de devolver basura', () => {
  const cifrado = cifrar('token-original');
  const partes = cifrado.split('.');
  // Se altera un byte del ciphertext.
  const alterado = partes[3].replace(/^../, partes[3].startsWith('aa') ? 'bb' : 'aa');
  assert.throws(() => descifrar([partes[0], partes[1], partes[2], alterado].join('.')));
});

test('descifrar acepta null sin lanzar (refresh_token opcional)', () => {
  assert.strictEqual(descifrar(null), null);
});

// ─── Comisión ────────────────────────────────────────────────

test('la comisión sale del porcentaje configurado, no de un valor fijo', () => {
  assert.strictEqual(calcularComision(100), 5);   // 5% de 100
  assert.strictEqual(calcularComision(250.5), 12.53);
});

test('redondear2 no arrastra el error binario del punto flotante', () => {
  assert.strictEqual(redondear2(1.005), 1.01);
  assert.strictEqual(redondear2(0.1 + 0.2), 0.3);
});

test('rechaza montos no positivos', () => {
  assert.throws(() => calcularComision(0));
  assert.throws(() => calcularComision(-10));
});

// ─── Firma del webhook ───────────────────────────────────────

function firmar({ dataId, requestId, ts, secreto = 'TEST-webhook-secret' }) {
  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  return crypto.createHmac('sha256', secreto).update(manifest).digest('hex');
}

function peticionFalsa({ dataId, requestId, ts, v1 }) {
  return {
    headers: { 'x-signature': `ts=${ts},v1=${v1}`, 'x-request-id': requestId },
    query: { 'data.id': dataId },
  };
}

test('acepta una firma válida y reciente', () => {
  const ts = Math.floor(Date.now() / 1000);
  const req = peticionFalsa({
    dataId: '123456', requestId: 'req-1', ts,
    v1: firmar({ dataId: '123456', requestId: 'req-1', ts }),
  });
  assert.strictEqual(validarFirma(req).valida, true);
});

test('rechaza una firma que no corresponde al contenido', () => {
  const ts = Math.floor(Date.now() / 1000);
  const req = peticionFalsa({
    dataId: '123456', requestId: 'req-1', ts,
    // Firmado para OTRO pago: es exactamente el ataque de "marcar como
    // pagada la orden que yo quiera".
    v1: firmar({ dataId: '999999', requestId: 'req-1', ts }),
  });
  assert.strictEqual(validarFirma(req).valida, false);
});

test('rechaza una firma válida pero vieja (replay)', () => {
  const ts = Math.floor(Date.now() / 1000) - 3600;
  const req = peticionFalsa({
    dataId: '123456', requestId: 'req-1', ts,
    v1: firmar({ dataId: '123456', requestId: 'req-1', ts }),
  });
  assert.strictEqual(validarFirma(req).valida, false);
});

test('rechaza cuando falta la cabecera de firma', () => {
  assert.strictEqual(validarFirma({ headers: {}, query: {} }).valida, false);
});

// ─── Idempotencia del webhook ────────────────────────────────

test('el mismo evento solo se registra una vez', () => {
  const eventId = `evt_${crypto.randomUUID()}`;
  assert.strictEqual(store.registrarEventoWebhook({ eventId, topic: 'payment', resourceId: '1' }), true);
  assert.strictEqual(store.registrarEventoWebhook({ eventId, topic: 'payment', resourceId: '1' }), false);
});

test('un estado final no retrocede por una notificación tardía', () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(vendedor.id, 100);
  const orden = store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: 100, applicationFee: 5, currency: 'MXN', origin: 'direct',
    items: [{ productId: producto, quantity: 1, unitPrice: 100, title: 'X' }],
  });

  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: '111', paymentStatus: 'approved' });
  // MP no garantiza el orden de entrega: este 'pending' llega tarde.
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: '111', paymentStatus: 'pending' });

  assert.strictEqual(store.getOrdenPorId(orden.id).payment_status, 'approved');
});

test('un reembolso posterior sí puede cambiar un pago aprobado', () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(vendedor.id, 50);
  const orden = store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: 50, applicationFee: 2.5, currency: 'MXN', origin: 'direct',
    items: [{ productId: producto, quantity: 1, unitPrice: 50, title: 'X' }],
  });
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: '222', paymentStatus: 'approved' });
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: '222', paymentStatus: 'refunded' });
  assert.strictEqual(store.getOrdenPorId(orden.id).payment_status, 'refunded');
});

// ─── Pertenencia de recursos ─────────────────────────────────

test('no se puede borrar la tarjeta de otro usuario', async () => {
  const duenio = crearUsuario();
  const intruso = crearUsuario();
  store.guardarTarjeta(duenio.id, {
    mpCardId: 'card_del_duenio', lastFour: '4242',
    paymentMethod: 'visa', expMonth: 12, expYear: 2030,
  });

  const res = await pedir('DELETE', '/api/payments/cards/card_del_duenio', { token: intruso.token });
  assert.strictEqual(res.status, 404);
  // Y sigue existiendo.
  assert.ok(store.getTarjeta(duenio.id, 'card_del_duenio'));
});

test('listar tarjetas solo devuelve las propias, sin datos sensibles', async () => {
  const a = crearUsuario();
  const b = crearUsuario();
  store.guardarTarjeta(a.id, { mpCardId: 'card_a', lastFour: '1111', paymentMethod: 'visa' });
  store.guardarTarjeta(b.id, { mpCardId: 'card_b', lastFour: '2222', paymentMethod: 'master' });

  const res = await pedir('GET', '/api/payments/cards', { token: a.token });
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.datos.length, 1);
  assert.strictEqual(res.datos[0].id, 'card_a');

  const claves = Object.keys(res.datos[0]).join(',');
  for (const prohibida of ['number', 'cvv', 'security', 'token']) {
    assert.ok(!claves.toLowerCase().includes(prohibida), `expone ${prohibida}`);
  }
});

test('no se puede pagar la orden de otro comprador', async () => {
  const comprador = crearUsuario();
  const intruso = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(vendedor.id, 200);

  const creadas = await pedir('POST', '/api/orders', {
    token: comprador.token, body: { productId: producto, quantity: 1 },
  });
  assert.strictEqual(creadas.status, 201);

  const res = await pedir('POST', '/api/payments/checkout', {
    token: intruso.token,
    body: { order_id: creadas.datos[0].id, card_token: 'tok_falso' },
  });
  assert.strictEqual(res.status, 404);
});

// ─── Creación de órdenes ─────────────────────────────────────

test('el total se calcula del precio en la base de datos, no del cliente', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(vendedor.id, 300);

  const res = await pedir('POST', '/api/orders', {
    token: comprador.token,
    // El cliente intenta colar su propio precio y su propia comisión.
    body: { productId: producto, quantity: 2, amount: 1, application_fee: 0 },
  });
  assert.strictEqual(res.status, 201);
  assert.strictEqual(res.datos[0].amount, 600);
  assert.strictEqual(res.datos[0].applicationFee, 30); // 5% de 600
});

test('un carrito con dos vendedores produce dos órdenes', async () => {
  const comprador = crearUsuario();
  const v1 = crearUsuario({ tipoCuenta: 'negocio' });
  const v2 = crearUsuario({ tipoCuenta: 'negocio' });
  const p1 = crearProducto(v1.id, 100);
  const p2 = crearProducto(v2.id, 40);

  db.upsertCartItem(comprador.id, { id: `c_${++contador}`, productId: p1, quantity: 1 });
  db.upsertCartItem(comprador.id, { id: `c_${++contador}`, productId: p2, quantity: 3 });

  const res = await pedir('POST', '/api/orders', {
    token: comprador.token, body: { fromCart: true },
  });
  assert.strictEqual(res.status, 201);
  assert.strictEqual(res.datos.length, 2);

  const totales = res.datos.map(o => o.amount).sort((a, b) => a - b);
  assert.deepStrictEqual(totales, [100, 120]);
  assert.ok(res.datos.every(o => o.origin === 'cart'));
});

test('no se puede crear una orden de un producto propio', async () => {
  const usuario = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(usuario.id, 100);
  const res = await pedir('POST', '/api/orders', {
    token: usuario.token, body: { productId: producto, quantity: 1 },
  });
  assert.strictEqual(res.status, 400);
});

// ─── Guardas del checkout ────────────────────────────────────

test('el checkout falla con mensaje claro si el vendedor no conectó Mercado Pago', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(vendedor.id, 150);

  const creadas = await pedir('POST', '/api/orders', {
    token: comprador.token, body: { productId: producto, quantity: 1 },
  });
  const res = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: creadas.datos[0].id, card_token: 'tok_falso' },
  });

  assert.strictEqual(res.status, 409);
  assert.match(res.datos.error, /no puede recibir pagos/i);
  // El mensaje nombra al vendedor y no filtra nada técnico.
  assert.ok(!/mercadopago\.com|access_token|undefined/i.test(res.datos.error));
});

test('una cuenta no verificada no puede conectar Mercado Pago', async () => {
  const usuario = crearUsuario({ tipoCuenta: 'estudiante', verificado: false });
  const res = await pedir('GET', '/api/payments/oauth/connect', { token: usuario.token });
  assert.strictEqual(res.status, 403);
});

test('una cuenta verificada de negocio recibe una URL de autorización de MP', async () => {
  const usuario = crearUsuario({ tipoCuenta: 'negocio', verificado: true });
  const res = await pedir('GET', '/api/payments/oauth/connect', { token: usuario.token });
  assert.strictEqual(res.status, 200);
  assert.match(res.datos.url, /^https:\/\/auth\.mercadopago\.com\.mx\/authorization\?/);
  // El secret NUNCA puede viajar en la URL de autorización.
  assert.ok(!res.datos.url.includes(process.env.MP_CLIENT_SECRET));
});

test('todos los endpoints de pagos exigen autenticación', async () => {
  for (const [metodo, ruta] of [
    ['GET', '/api/payments/cards'],
    ['POST', '/api/payments/cards'],
    ['DELETE', '/api/payments/cards/x'],
    ['POST', '/api/payments/checkout'],
    ['GET', '/api/payments/oauth/connect'],
    ['POST', '/api/orders'],
    ['GET', '/api/orders'],
  ]) {
    const res = await pedir(metodo, ruta);
    assert.strictEqual(res.status, 401, `${metodo} ${ruta} no exige token`);
  }
});

// ─── El state del OAuth ──────────────────────────────────────

test('un state solo se puede usar una vez', () => {
  const usuario = crearUsuario({ tipoCuenta: 'negocio' });
  const state = store.crearOAuthState(usuario.id);
  assert.strictEqual(store.consumirOAuthState(state), usuario.id);
  assert.strictEqual(store.consumirOAuthState(state), null);
});

test('un state inventado no vale', () => {
  assert.strictEqual(store.consumirOAuthState('state-inventado'), null);
});
