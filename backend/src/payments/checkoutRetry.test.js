// Reintento de checkout después de un rechazo.
//
// Cuando MP rechaza una tarjeta, la app le dice al comprador "Intenta con
// otra". Estos tests fijan que eso sea realmente posible, y —lo más
// importante— que abrirlo no habilite un segundo cargo sobre un pago que
// todavía está vivo en MP.
//
// mpClient.crearPago se sustituye por un doble ANTES de requerir routes.js:
// ninguna de estas pruebas toca la API real de Mercado Pago.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');
const crypto = require('node:crypto');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-checkout-retry-')),
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

// ─── Doble de prueba de mpClient.crearPago ──────────────────────
const mpClient = require('./mpClient');
let respuestaCrearPago;      // función controlada por cada test
let llamadasCrearPago = [];  // lo que el código realmente le mandó a MP

mpClient.crearPago = async (args) => {
  llamadasCrearPago.push(args);
  return respuestaCrearPago(args);
};

// El checkout valida contra MP que la autorización del vendedor siga viva
// antes de cobrar. Aquí siempre está viva: lo que se prueba en este archivo
// son los reintentos, y el camino de la revocación tiene su propio archivo
// (connection.test.js). Sin este doble, la llamada saldría de verdad a
// api.mercadopago.com y el token de prueba recibiría un 401 legítimo.
mpClient.validarTokenVendedor = async () => ({ id: 123 });

const store = require('./store');
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

// ─── Helpers ────────────────────────────────────────────────────

let contador = 0;

function crearUsuario({ tipoCuenta = 'estudiante' } = {}) {
  const id = `u_cr_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta)
     VALUES (?, ?, ?, 'TT', '', ?, 1, ?)`,
  ).run(id, `Test ${id}`, `${id}@ejemplo.com`, tipoCuenta === 'negocio' ? 1 : 0, tipoCuenta);
  return { id, token: generateToken(id) };
}

function crearProducto(sellerId, precio) {
  const id = `p_cr_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO products (id, title, price, priceNum, seller, category)
     VALUES (?, ?, ?, ?, ?, 'otros')`,
  ).run(id, `Producto ${id}`, `$${precio}`, precio, sellerId);
  return id;
}

/**
 * Comprador + vendedor con cuenta de MP conectada + una orden pendiente.
 * El token se guarda con caducidad lejana a propósito: dentro del margen de
 * renovación (7 días) `tokenVigenteDeVendedor` intentaría refrescarlo contra
 * la API real.
 */
function escenario(precio = 100) {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(vendedor.id, precio);

  store.guardarCuentaVendedor(vendedor.id, {
    mpUserId: `mp_${vendedor.id}`,
    accessToken: 'vendor-access-token',
    refreshToken: 'vendor-refresh-token',
    expiresIn: 30 * 24 * 60 * 60,
  });

  const orden = store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: precio, applicationFee: precio * 0.05, currency: 'MXN', origin: 'direct',
    items: [{ productId: producto, quantity: 1, unitPrice: precio, title: 'X' }],
  });

  return { comprador, vendedor, orden };
}

async function checkout({ token, orderId, cardToken }) {
  const res = await fetch(`${baseUrl}/api/payments/checkout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ order_id: orderId, card_token: cardToken }),
  });
  const texto = await res.text();
  let datos = null;
  try { datos = texto ? JSON.parse(texto) : null; } catch { datos = texto; }
  return { status: res.status, datos };
}

test.beforeEach(() => { llamadasCrearPago = []; });

// ─── application_fee: el error 2059 de Mercado Pago ─────────────
//
// "You cannot use application_fee with this payment" tumba el cobro ENTERO,
// y llega como un 400 que sin tratamiento se traduce a "intenta con otra
// tarjeta" — mandando a quien compra a quemar intentos del límite
// antifraude con tarjetas que están perfectas.

test('en un cobro normal la comisión viaja como application_fee', async () => {
  const { comprador, orden } = escenario(200);
  respuestaCrearPago = async () => ({ id: 'pay_fee_normal', status: 'approved' });

  await checkout({ token: comprador.token, orderId: orden.id, cardToken: 'tok_A' });

  assert.strictEqual(llamadasCrearPago[0].pago.application_fee, 10); // 5% de 200
});

test('si el vendedor ES la cuenta de la aplicación, se cobra SIN application_fee', async () => {
  // El escenario que produce el 2059 en la vida real: quien crea la
  // aplicación en el panel de MP conecta su propia cuenta como vendedor.
  const { comprador, vendedor, orden } = escenario(200);
  const { _resetCache } = require('./comision');
  const cuenta = store.getCuentaVendedor(vendedor.id);

  mpClient.validarTokenVendedor = async () => ({ id: cuenta.mp_user_id });
  _resetCache();
  // Un id distinto por prueba: `orders.mp_payment_id` es UNIQUE, y repetirlo
  // hace fallar el INSERT con un 502 que no tiene nada que ver con lo que
  // se está probando.
  respuestaCrearPago = async () => ({ id: 'pay_fee_propio', status: 'approved' });

  try {
    const res = await checkout({
      token: comprador.token, orderId: orden.id, cardToken: 'tok_B',
    });
    assert.strictEqual(res.status, 200, 'el cobro tiene que salir adelante');

    // `undefined`, no 0: MP también rechaza un application_fee de 0
    // explícito. El campo tiene que desaparecer del cuerpo.
    assert.strictEqual(llamadasCrearPago[0].pago.application_fee, undefined);
  } finally {
    mpClient.validarTokenVendedor = async () => ({ id: 123 });
    _resetCache();
  }
});

test('PLATFORM_FEE_ENABLED=false cobra sin comisión y sin cambiar el importe', async () => {
  const { comprador, orden } = escenario(200);
  const { _resetCache } = require('./comision');
  process.env.PLATFORM_FEE_ENABLED = 'false';
  _resetCache();
  respuestaCrearPago = async () => ({ id: 'pay_fee_apagada', status: 'approved' });

  try {
    await checkout({ token: comprador.token, orderId: orden.id, cardToken: 'tok_C' });
    const { pago } = llamadasCrearPago[0];
    assert.strictEqual(pago.application_fee, undefined);
    // Lo que paga quien compra no cambia: la comisión sale de lo que recibe
    // el vendedor, no de lo que paga el comprador.
    assert.strictEqual(pago.transaction_amount, 200);
  } finally {
    delete process.env.PLATFORM_FEE_ENABLED;
    _resetCache();
  }
});

test('un 2059 no se le presenta al comprador como un problema de su tarjeta', async () => {
  const { comprador, orden } = escenario(200);
  respuestaCrearPago = async () => {
    throw new mpClient.MpError('Mercado Pago respondió 400 en POST /v1/payments', {
      status: 400,
      detalle: {
        message: 'You cannot use application_fee with this payment.',
        error: 'bad_request',
        cause: [{ code: 2059, description: 'You cannot use application_fee with this payment.' }],
      },
    });
  };

  const res = await checkout({
    token: comprador.token, orderId: orden.id, cardToken: 'tok_D',
  });

  assert.strictEqual(res.status, 409, 'no es un 400 de tarjeta rechazada');
  assert.ok(!/intenta con otra/i.test(res.datos.error),
    'no puede mandar a probar otra tarjeta: la tarjeta no tiene nada malo');
  // Y el detalle de MP sigue sin salir del servidor.
  assert.ok(!JSON.stringify(res.datos).includes('application_fee'));
});

test('un rechazo de tarjeta de verdad SÍ manda a probar otra', async () => {
  // La contraparte del test anterior: la rama nueva del 2059 no puede
  // haberse tragado los rechazos normales.
  const { comprador, orden } = escenario(200);
  respuestaCrearPago = async () => {
    throw new mpClient.MpError('Mercado Pago respondió 400', {
      status: 400,
      detalle: { cause: [{ code: 3034, description: 'Invalid card number' }] },
    });
  };

  const res = await checkout({
    token: comprador.token, orderId: orden.id, cardToken: 'tok_E',
  });

  assert.strictEqual(res.status, 400);
  assert.ok(/intenta con otra/i.test(res.datos.error));
});

// ─── El bug: un rechazo deja la orden inservible ────────────────

test('tras un rechazo, el comprador puede reintentar con otra tarjeta', async () => {
  const { comprador, orden } = escenario();

  // Intento 1: MP rechaza la tarjeta (fondos insuficientes, CVV malo, etc.).
  respuestaCrearPago = async () => ({
    id: 'pay_rechazado', status: 'rejected', status_detail: 'cc_rejected_insufficient_amount',
  });
  const rechazo = await checkout({
    token: comprador.token, orderId: orden.id, cardToken: 'card_token_A',
  });
  assert.strictEqual(rechazo.status, 200, 'un rechazo de MP es una respuesta válida del checkout');
  assert.strictEqual(rechazo.datos.status, 'rejected');

  // Intento 2: otra tarjeta, que sí pasa. Es exactamente lo que el mensaje de
  // error del intento anterior le pide al comprador que haga.
  respuestaCrearPago = async () => ({
    id: 'pay_aprobado', status: 'approved', status_detail: 'accredited',
  });
  const reintento = await checkout({
    token: comprador.token, orderId: orden.id, cardToken: 'card_token_B',
  });

  assert.strictEqual(
    reintento.status, 200,
    `el reintento con otra tarjeta debió aceptarse, respondió ${reintento.status}: ${JSON.stringify(reintento.datos)}`,
  );
  assert.strictEqual(reintento.datos.status, 'approved');

  const guardada = store.getOrdenPorId(orden.id);
  assert.strictEqual(guardada.payment_status, 'approved',
    'el pago aprobado del reintento debió quedar registrado');
  assert.strictEqual(guardada.status, 'paid');
  assert.strictEqual(guardada.mp_payment_id, 'pay_aprobado',
    'la orden debe apuntar al pago que de verdad cobró, no al rechazado');
});

test('el reintento con otra tarjeta usa una clave de idempotencia distinta', async () => {
  const { comprador, orden } = escenario();

  respuestaCrearPago = async () => ({ id: 'pay_r', status: 'rejected', status_detail: 'cc_rejected_other_reason' });
  await checkout({ token: comprador.token, orderId: orden.id, cardToken: 'card_token_A' });

  respuestaCrearPago = async () => ({ id: 'pay_ok', status: 'approved', status_detail: 'accredited' });
  await checkout({ token: comprador.token, orderId: orden.id, cardToken: 'card_token_B' });

  assert.strictEqual(llamadasCrearPago.length, 2, 'ambos intentos debieron llegar a MP');
  // Con la misma clave, MP responde con el pago cacheado del primer intento:
  // el comprador vería otra vez el rechazo de la tarjeta que ya descartó.
  assert.notStrictEqual(
    llamadasCrearPago[0].idempotencyKey,
    llamadasCrearPago[1].idempotencyKey,
    'dos tarjetas distintas no pueden compartir clave de idempotencia',
  );
});

test('reenviar el mismo intento (mismo card_token) conserva la clave de idempotencia', async () => {
  const { comprador, orden } = escenario();

  // Un timeout de red del lado de la app hace que reenvíe la MISMA petición.
  // Aquí la clave sí tiene que repetirse: es lo único que impide un segundo
  // cargo real por un reintento de transporte.
  respuestaCrearPago = async () => ({ id: 'pay_r2', status: 'rejected', status_detail: 'cc_rejected_other_reason' });
  await checkout({ token: comprador.token, orderId: orden.id, cardToken: 'card_token_MISMO' });
  await checkout({ token: comprador.token, orderId: orden.id, cardToken: 'card_token_MISMO' });

  assert.strictEqual(llamadasCrearPago.length, 2);
  assert.strictEqual(
    llamadasCrearPago[0].idempotencyKey,
    llamadasCrearPago[1].idempotencyKey,
    'el mismo intento reenviado debe deduplicarse en MP',
  );
});

// ─── El hueco que el fix NO puede abrir ─────────────────────────

test('no se puede lanzar un segundo cobro sobre un pago todavía en vuelo', async () => {
  const { comprador, orden } = escenario();

  // MP deja el pago 'in_process' (revisión antifraude): el dinero puede
  // acabar cobrándose. `status` de la orden sigue en 'pending', así que el
  // guard viejo por `status` no ve nada raro — pero cobrar otra vez aquí es
  // un doble cargo real.
  respuestaCrearPago = async () => ({ id: 'pay_en_vuelo', status: 'in_process', status_detail: 'pending_review_manual' });
  const primero = await checkout({
    token: comprador.token, orderId: orden.id, cardToken: 'card_token_A',
  });
  assert.strictEqual(primero.status, 200);
  assert.strictEqual(store.getOrdenPorId(orden.id).payment_status, 'in_process');

  respuestaCrearPago = async () => ({ id: 'pay_duplicado', status: 'approved', status_detail: 'accredited' });
  const segundo = await checkout({
    token: comprador.token, orderId: orden.id, cardToken: 'card_token_B',
  });

  assert.strictEqual(segundo.status, 409,
    'con un pago en vuelo el checkout debe bloquearse, no cobrar de nuevo');
  assert.strictEqual(llamadasCrearPago.length, 1,
    'el segundo intento no debió llegar a MP');
  assert.strictEqual(store.getOrdenPorId(orden.id).mp_payment_id, 'pay_en_vuelo');
});

test('una orden ya aprobada no admite otro cobro', async () => {
  const { comprador, orden } = escenario();

  respuestaCrearPago = async () => ({ id: 'pay_ok_1', status: 'approved', status_detail: 'accredited' });
  await checkout({ token: comprador.token, orderId: orden.id, cardToken: 'card_token_A' });

  const segundo = await checkout({
    token: comprador.token, orderId: orden.id, cardToken: 'card_token_B',
  });
  assert.strictEqual(segundo.status, 409);
  assert.strictEqual(llamadasCrearPago.length, 1, 'no se debió intentar cobrar dos veces');
});

// ─── Límite de intentos (card testing) ──────────────────────────

test('un mismo comprador no puede encadenar intentos de cobro sin límite', async () => {
  const { comprador, orden } = escenario();

  // Poder reintentar tras un rechazo es correcto para el comprador, pero es
  // también el mecanismo del "card testing": probar tarjetas robadas una tras
  // otra contra un endpoint que dice si el cargo pasó. Sin tope, la cuenta
  // gratuita de cualquiera es un validador de tarjetas.
  respuestaCrearPago = async () => ({
    id: `pay_${Math.random()}`, status: 'rejected', status_detail: 'cc_rejected_other_reason',
  });

  const codigos = [];
  for (let i = 0; i < 15; i++) {
    const res = await checkout({
      token: comprador.token, orderId: orden.id, cardToken: `card_token_${i}`,
    });
    codigos.push(res.status);
  }

  assert.ok(codigos.includes(429),
    `en algún momento debió cortarse con 429; se obtuvo ${JSON.stringify(codigos)}`);
  assert.ok(llamadasCrearPago.length < 15,
    `los intentos bloqueados no debieron llegar a MP; llegaron ${llamadasCrearPago.length}`);
});

test('el límite de intentos es por comprador, no global', async () => {
  const a = escenario();
  const b = escenario();

  respuestaCrearPago = async () => ({
    id: `pay_${Math.random()}`, status: 'rejected', status_detail: 'cc_rejected_other_reason',
  });

  // `a` agota su cupo...
  for (let i = 0; i < 15; i++) {
    await checkout({ token: a.comprador.token, orderId: a.orden.id, cardToken: `ct_a_${i}` });
  }

  // ...y `b`, que no ha hecho nada, sigue pudiendo pagar. Un límite por IP
  // haría justo lo contrario: en la red del campus (una sola IP de salida)
  // el primero en pasarse dejaría a todos los demás sin poder comprar.
  const res = await checkout({
    token: b.comprador.token, orderId: b.orden.id, cardToken: 'ct_b_1',
  });
  assert.notStrictEqual(res.status, 429,
    'el cupo agotado de un comprador no puede bloquear a otro');
});

// ─── Transición de estado a nivel de store ──────────────────────

test('un pago nuevo que aprueba supersede a un intento anterior cancelado', () => {
  const { orden } = escenario(40);

  // Intento 1 cancelado. 'cancelled' es un estado final para ESE pago...
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: 'pay_viejo', paymentStatus: 'cancelled' });

  // ...pero no puede congelar la orden entera: este es OTRO pago, y sí cobró.
  const actualizado = store.actualizarPagoDeOrden(orden.id, {
    mpPaymentId: 'pay_nuevo', paymentStatus: 'approved',
  });

  assert.strictEqual(actualizado, true,
    'el estado final del pago viejo no puede descartar el cobro de un pago nuevo');
  const guardada = store.getOrdenPorId(orden.id);
  assert.strictEqual(guardada.payment_status, 'approved');
  assert.strictEqual(guardada.mp_payment_id, 'pay_nuevo');
});

test('la notificación tardía de un intento rechazado no pisa el cobro que sí funcionó', () => {
  const { orden } = escenario(45);

  // Secuencia real: la tarjeta A se rechaza, el comprador reintenta con la B
  // y esa sí cobra. El webhook del intento A llega DESPUÉS (MP no garantiza
  // el orden). Permitir que un pago distinto sustituya al guardado no puede
  // significar que un intento muerto tumbe una orden ya pagada.
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: 'pay_A', paymentStatus: 'rejected' });
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: 'pay_B', paymentStatus: 'approved' });

  const pisado = store.actualizarPagoDeOrden(orden.id, {
    mpPaymentId: 'pay_A', paymentStatus: 'rejected',
  });

  assert.strictEqual(pisado, false, 'el intento muerto no puede sustituir al pago aprobado');
  const guardada = store.getOrdenPorId(orden.id);
  assert.strictEqual(guardada.payment_status, 'approved');
  assert.strictEqual(guardada.mp_payment_id, 'pay_B');
  assert.strictEqual(guardada.status, 'paid');
});

test('una notificación tardía del MISMO pago sigue sin hacer retroceder el estado', () => {
  const { orden } = escenario(30);

  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: 'pay_unico', paymentStatus: 'approved' });
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: 'pay_unico', paymentStatus: 'pending' });

  assert.strictEqual(store.getOrdenPorId(orden.id).payment_status, 'approved');
});
