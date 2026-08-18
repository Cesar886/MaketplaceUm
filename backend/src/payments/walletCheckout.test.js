// Pago con la CUENTA DE MERCADO PAGO del comprador.
//
// Es el segundo carril para cobrar la misma orden: en vez de tokenizar una
// tarjeta en la app, se crea una preferencia en la cuenta del vendedor y se
// manda al comprador a pagar a Mercado Pago.
//
// Lo que estas pruebas fijan, en orden de gravedad:
//
//  1. Que el importe y la comisión salgan del SERVIDOR, no del cliente. Es
//     lo mismo que ya garantiza /checkout, y el riesgo de tener dos rutas de
//     cobro es justo que una de las dos se lo salte.
//  2. Que la comisión viaje como `marketplace_fee`. En /v1/payments el campo
//     se llama `application_fee`; escribir ese nombre aquí no da error, MP
//     lo ignora y la plataforma deja de cobrar sin que nada falle.
//  3. Que pase por las MISMAS guardas que la tarjeta (orden ajena, orden ya
//     pagada, vendedor sin cuenta).
//  4. Que pedir la preferencia NO mueva el estado de la orden: quien decide
//     si se pagó es el webhook.
//
// mpClient.crearPreferencia se sustituye por un doble ANTES de requerir
// routes.js: ninguna de estas pruebas toca la API real de Mercado Pago.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');
const crypto = require('node:crypto');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-wallet-')),
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

// ─── Dobles de prueba ───────────────────────────────────────────
const mpClient = require('./mpClient');
let respuestaPreferencia;
let llamadasPreferencia = [];

mpClient.crearPreferencia = async (args) => {
  llamadasPreferencia.push(args);
  return respuestaPreferencia(args);
};

// El cobro con tarjeta, para poder probar QUE LOS DOS CARRILES NO SE PISEN
// sobre la misma orden.
let llamadasCrearPago = [];
mpClient.crearPago = async (args) => {
  llamadasCrearPago.push(args);
  return { id: `pay_${Math.random()}`, status: 'approved' };
};

// Relectura de la preferencia recién creada. Es diagnóstico: sirve para ver
// qué guardó MP DE VERDAD (y en particular si se quedó el marketplace_fee),
// porque el eco de la creación no lo dice.
let respuestaObtenerPreferencia;
let llamadasObtenerPreferencia = [];

mpClient.obtenerPreferencia = async (id, accessToken) => {
  llamadasObtenerPreferencia.push({ id, accessToken });
  return respuestaObtenerPreferencia({ id, accessToken });
};

// La ruta valida contra MP que la autorización del vendedor siga viva antes
// de crear nada. Aquí siempre está viva; el camino de la revocación tiene su
// propio archivo (connection.test.js).
//
// El doble distingue por credencial porque `GET /users/me` responde dos
// preguntas distintas según con qué token se llame: con el de la PLATAFORMA
// dice quién es la cuenta dueña de la aplicación (lo usa `comision.js`), y
// con el del VENDEDOR dice qué cuenta va a cobrar. Devolver lo mismo a las
// dos haría que el vendedor pareciera el dueño de la app y la comisión
// desaparecería en todas las pruebas.
//
// 123 no coincide con el mp_user_id de ningún vendedor de estas pruebas
// (`mp_u_w_N`), así que la comisión se cobra con normalidad.
const VALIDAR_TOKEN_POR_DEFECTO = async (accessToken) => (
  accessToken === process.env.MP_ACCESS_TOKEN
    ? { id: 123 }
    : { id: 456, nickname: 'VENDEDOR_REAL', email: 'vendedor@ejemplo.com' }
);
let respuestaValidarToken;
mpClient.validarTokenVendedor = async (accessToken) => respuestaValidarToken(accessToken);

const store = require('./store');
const cfg = require('./config');
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

// ─── Helpers ────────────────────────────────────────────────────

let contador = 0;

function crearUsuario({ tipoCuenta = 'estudiante' } = {}) {
  const id = `u_w_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta)
     VALUES (?, ?, ?, 'TT', '', ?, 1, ?)`,
  ).run(id, `Test ${id}`, `${id}@ejemplo.com`, tipoCuenta === 'negocio' ? 1 : 0, tipoCuenta);
  return { id, token: generateToken(id) };
}

function crearProducto(sellerId, precio) {
  const id = `p_w_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO products (id, title, price, priceNum, seller, category)
     VALUES (?, ?, ?, ?, ?, 'otros')`,
  ).run(id, `Producto ${id}`, `$${precio}`, precio, sellerId);
  return id;
}

/**
 * Comprador + vendedor con cuenta conectada + una orden pendiente.
 *
 * El token se guarda con caducidad lejana a propósito: dentro del margen de
 * renovación (7 días) `tokenVigenteDeVendedor` intentaría refrescarlo contra
 * la API real.
 */
function escenario(precio = 100, { conectar = true, publicKey, accessToken = 'vendor-access-token' } = {}) {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  const producto = crearProducto(vendedor.id, precio);

  if (conectar) {
    store.guardarCuentaVendedor(vendedor.id, {
      mpUserId: `mp_${vendedor.id}`,
      accessToken,
      refreshToken: 'vendor-refresh-token',
      expiresIn: 30 * 24 * 60 * 60,
      publicKey,
    });
  }

  const orden = store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: precio, applicationFee: precio * 0.05, currency: 'MXN', origin: 'direct',
    items: [{ productId: producto, quantity: 2, unitPrice: precio / 2, title: 'Cosa' }],
  });

  return { comprador, vendedor, orden, producto };
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

const wallet = (token, orderId) =>
  pedir('POST', '/api/payments/checkout/wallet', { token, body: { order_id: orderId } });


test.beforeEach(() => {
  llamadasPreferencia = [];
  llamadasCrearPago = [];
  llamadasObtenerPreferencia = [];
  respuestaValidarToken = VALIDAR_TOKEN_POR_DEFECTO;
  delete process.env.MP_USE_SANDBOX_INIT_POINT;
  delete process.env.MP_DEBUG_PREFERENCIA;
  respuestaPreferencia = async () => ({
    id: 'pref_123',
    init_point: 'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
  });
  respuestaObtenerPreferencia = async () => ({
    id: 'pref_123',
    marketplace_fee: 10,
    collector_id: 456,
  });
});

// ─── El camino feliz ────────────────────────────────────────────

test('devuelve el init_point para mandar al comprador a Mercado Pago', async () => {
  const { comprador, orden } = escenario(250);

  const res = await wallet(comprador.token, orden.id);
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.datos.orderId, orden.id);
  assert.strictEqual(res.datos.preferenceId, 'pref_123');
  assert.ok(res.datos.initPoint.startsWith('https://'));
});

test('la preferencia se crea con el token DEL VENDEDOR, no con el de la plataforma', async () => {
  const { comprador, orden } = escenario();
  await wallet(comprador.token, orden.id);

  const [llamada] = llamadasPreferencia;
  assert.strictEqual(llamada.accessTokenVendedor, 'vendor-access-token');
  assert.notStrictEqual(llamada.accessTokenVendedor, process.env.MP_ACCESS_TOKEN);
});

// ─── Dinero: importe y comisión ─────────────────────────────────

test('el importe sale de order_items, no del cuerpo de la petición', async () => {
  const { comprador, orden } = escenario(300);

  // Se intenta colar un total propio, como haría un cliente manipulado.
  const res = await pedir('POST', '/api/payments/checkout/wallet', {
    token: comprador.token,
    body: { order_id: orden.id, amount: 1, transaction_amount: 1, marketplace_fee: 0 },
  });
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.datos.amount, 300);

  const { preferencia } = llamadasPreferencia[0];
  const total = preferencia.items.reduce((s, i) => s + i.unit_price * i.quantity, 0);
  assert.strictEqual(total, 300, 'MP tiene que cobrar el total del servidor');
});

test('la comisión viaja como marketplace_fee, que es como se llama en preferencias', async () => {
  const { comprador, orden } = escenario(200);
  await wallet(comprador.token, orden.id);

  const { preferencia } = llamadasPreferencia[0];
  // 5% de 200. Con `application_fee` en su lugar, MP lo ignoraría en
  // silencio y la plataforma no cobraría nada: el fallo no daría error.
  assert.strictEqual(preferencia.marketplace_fee, 10);
  assert.strictEqual(preferencia.application_fee, undefined);
});

test('si el vendedor ES la cuenta de la aplicación, el campo NO se manda', async () => {
  // El error 2059 de MP. Aquí no tumba el cobro (una preferencia se crea
  // igual), pero mandar un marketplace_fee que no aplica es peor que no
  // mandarlo: MP lo ignora en silencio. Se omite para que quede explícito
  // en el código y en el log que ese cobro va sin comisión.
  const { comprador, vendedor, orden } = escenario(200);
  const { _resetCache } = require('./comision');
  const cuenta = store.getCuentaVendedor(vendedor.id);

  mpClient.validarTokenVendedor = async () => ({ id: cuenta.mp_user_id });
  _resetCache();

  try {
    const res = await wallet(comprador.token, orden.id);
    assert.strictEqual(res.status, 200, 'el cobro tiene que salir igual');

    const { preferencia } = llamadasPreferencia[0];
    assert.strictEqual(preferencia.marketplace_fee, undefined,
      'un 0 explícito también lo rechaza MP: el campo debe desaparecer');
  } finally {
    mpClient.validarTokenVendedor = async (t) => respuestaValidarToken(t);
    _resetCache();
  }
});

test('PLATFORM_FEE_ENABLED=false crea la preferencia sin comisión', async () => {
  const { comprador, orden } = escenario(200);
  const { _resetCache } = require('./comision');
  process.env.PLATFORM_FEE_ENABLED = 'false';
  _resetCache();

  try {
    const res = await wallet(comprador.token, orden.id);
    assert.strictEqual(res.status, 200);
    assert.strictEqual(llamadasPreferencia[0].preferencia.marketplace_fee, undefined);
    // El importe que paga el comprador NO cambia: la comisión sale de lo que
    // recibe el vendedor, no de lo que paga quien compra.
    assert.strictEqual(res.datos.amount, 200);
  } finally {
    delete process.env.PLATFORM_FEE_ENABLED;
    _resetCache();
  }
});

test('el mismo external_reference que el cobro con tarjeta, para que el webhook concilie', async () => {
  const { comprador, orden } = escenario();
  await wallet(comprador.token, orden.id);

  const { preferencia } = llamadasPreferencia[0];
  assert.strictEqual(preferencia.external_reference, orden.id);
  assert.ok(preferencia.notification_url.endsWith('/api/payments/webhook'));
});

test('la preferencia caduca: una abandonada no puede pagarse días después', async () => {
  const { comprador, orden } = escenario();
  await wallet(comprador.token, orden.id);

  const { preferencia } = llamadasPreferencia[0];
  assert.strictEqual(preferencia.expires, true);
  const caduca = new Date(preferencia.expiration_date_to).getTime();
  assert.ok(caduca > Date.now(), 'la caducidad tiene que estar en el futuro');
  assert.ok(caduca <= Date.now() + 31 * 60 * 1000, 'y no puede ser dentro de días');
});

// ─── Las guardas, las mismas que /checkout ──────────────────────

test('no se puede pagar la orden de otra persona', async () => {
  const { orden } = escenario();
  const intruso = crearUsuario();

  const res = await wallet(intruso.token, orden.id);
  // 404 y no 403: la orden de otro simplemente no existe para quien pregunta.
  assert.strictEqual(res.status, 404);
  assert.strictEqual(llamadasPreferencia.length, 0);
});

test('una orden ya pagada no genera una segunda preferencia', async () => {
  const { comprador, orden } = escenario();
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: 'pay_1', paymentStatus: 'approved' });

  const res = await wallet(comprador.token, orden.id);
  assert.strictEqual(res.status, 409);
  assert.strictEqual(llamadasPreferencia.length, 0);
});

test('un vendedor sin cuenta conectada no puede cobrar por este camino', async () => {
  const { comprador, orden } = escenario(100, { conectar: false });

  const res = await wallet(comprador.token, orden.id);
  assert.strictEqual(res.status, 409);
  assert.ok(res.datos.error, 'el comprador tiene que saber por qué no puede pagar');
  assert.strictEqual(llamadasPreferencia.length, 0);
});

test('sin order_id no se llama a Mercado Pago', async () => {
  const { comprador } = escenario();
  const res = await pedir('POST', '/api/payments/checkout/wallet',
    { token: comprador.token, body: {} });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(llamadasPreferencia.length, 0);
});

test('sin sesión no se puede pedir una preferencia', async () => {
  const { orden } = escenario();
  const res = await pedir('POST', '/api/payments/checkout/wallet',
    { body: { order_id: orden.id } });
  assert.ok(res.status === 401 || res.status === 403);
  assert.strictEqual(llamadasPreferencia.length, 0);
});

// ─── Crear la preferencia NO es haber cobrado ───────────────────

test('pedir la preferencia deja la orden intacta: quien la mueve es el webhook', async () => {
  const { comprador, orden } = escenario();
  await wallet(comprador.token, orden.id);

  const despues = store.getOrdenPorId(orden.id);
  assert.strictEqual(despues.status, 'pending');
  assert.strictEqual(despues.payment_status, null);
});

test('el inventario no se toca al crear la preferencia', async () => {
  const { comprador, orden, producto } = escenario();
  db.getDb().prepare('UPDATE products SET stock_quantity = 5 WHERE id = ?').run(producto);

  await wallet(comprador.token, orden.id);

  const fila = db.getDb().prepare('SELECT stock_quantity FROM products WHERE id = ?').get(producto);
  assert.strictEqual(fila.stock_quantity, 5, 'todavía no se ha vendido nada');
});

// ─── Errores de MP ──────────────────────────────────────────────

test('una preferencia sin init_point no se devuelve como si sirviera', async () => {
  const { comprador, orden } = escenario();
  respuestaPreferencia = async () => ({ id: 'pref_rota' });

  const res = await wallet(comprador.token, orden.id);
  assert.strictEqual(res.status, 502);
  assert.ok(res.datos.error);
});

test('el error crudo de Mercado Pago nunca llega al cliente', async () => {
  const { comprador, orden } = escenario();
  respuestaPreferencia = async () => {
    throw new mpClient.MpError('Mercado Pago respondió 400', {
      status: 400,
      detalle: { message: 'invalid collector_id', cause: [{ code: 4444 }] },
    });
  };

  const res = await wallet(comprador.token, orden.id);
  const cuerpo = JSON.stringify(res.datos);
  assert.ok(!cuerpo.includes('collector_id'), 'no puede filtrarse el detalle de MP');
  assert.ok(!cuerpo.includes('4444'));
});

// ─── Disponibilidad reportada al checkout ───────────────────────

test('/methods anuncia walletEnabled cuando el vendedor tiene la cuenta conectada', async () => {
  const { comprador, vendedor } = escenario();

  const res = await pedir('GET', `/api/payments/vendors/${vendedor.id}/methods`,
    { token: comprador.token });
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.datos.walletEnabled, true);
  assert.strictEqual(res.datos.walletUnavailableReason, null);
});

test('sin cuenta conectada, walletEnabled es false y viene el motivo', async () => {
  const { comprador, vendedor } = escenario(100, { conectar: false });

  const res = await pedir('GET', `/api/payments/vendors/${vendedor.id}/methods`,
    { token: comprador.token });
  assert.strictEqual(res.datos.walletEnabled, false);
  assert.ok(res.datos.walletUnavailableReason);
});

test('sin public key se puede cobrar por Mercado Pago aunque no por tarjeta', async () => {
  // El OAuth de MP no siempre devuelve public key. Sin ella no hay con qué
  // tokenizar en el dispositivo, pero la preferencia se crea con el access
  // token del vendedor: este camino sí funciona, y apagarlo también sería
  // negarle ventas que su cuenta cobraría hoy mismo.
  const { comprador, vendedor } = escenario(100, { publicKey: null });

  const res = await pedir('GET', `/api/payments/vendors/${vendedor.id}/methods`,
    { token: comprador.token });
  assert.strictEqual(res.datos.cardEnabled, false);
  assert.strictEqual(res.datos.walletEnabled, true);
});

// ─── El puente de vuelta a la app ───────────────────────────────

test('la vuelta desde Mercado Pago lleva al deep link de la app', async () => {
  const res = await fetch(`${baseUrl}/api/payments/wallet/return?orden=ord_1&r=ok`);
  assert.strictEqual(res.status, 200);
  const html = await res.text();
  assert.ok(html.includes('mercaditoum://payments/wallet-return'));
});

test('la vuelta no declara pagada una orden porque lo diga la URL', async () => {
  const { comprador, orden } = escenario();
  await wallet(comprador.token, orden.id);

  // Cualquiera puede escribir esta URL a mano. No puede tener efecto alguno.
  await fetch(`${baseUrl}/api/payments/wallet/return?orden=${orden.id}&r=ok`);

  const despues = store.getOrdenPorId(orden.id);
  assert.strictEqual(despues.status, 'pending');
  assert.strictEqual(despues.payment_status, null);
});

// ─── Cobro duplicado: los dos carriles sobre la misma orden ────
//
// Crear una preferencia no cobra nada y deja la orden en 'pending', así que
// la guarda de "esta orden ya fue procesada" NO la ve. Mientras tanto esa
// preferencia es pagable en Mercado Pago. Sin bloqueo, quien empieza a
// pagar con su cuenta, se sale, paga con tarjeta y luego vuelve a la
// pestaña que dejó abierta, paga DOS VECES de verdad — y el segundo cargo
// ni siquiera queda registrado, porque el webhook se niega a pisar un pago
// ya aprobado.

const checkoutTarjeta = (token, orderId, cardToken) =>
  pedir('POST', '/api/payments/checkout',
    { token, body: { order_id: orderId, card_token: cardToken } });

test('con una preferencia viva, el cobro con tarjeta se RECHAZA', async () => {
  const { comprador, orden } = escenario(500);

  const pref = await wallet(comprador.token, orden.id);
  assert.strictEqual(pref.status, 200);

  const res = await checkoutTarjeta(comprador.token, orden.id, 'tok_dup');

  assert.strictEqual(res.status, 409);
  assert.strictEqual(res.datos.motivo, 'preferencia_en_curso');
  assert.strictEqual(llamadasCrearPago.length, 0,
    'ni siquiera puede llegar a llamarse a MP: el cargo sería real');
  // Quien compra tiene que entender qué hacer y, sobre todo, qué NO hacer.
  assert.ok(/no pagues dos veces/i.test(res.datos.error));
  assert.ok(res.datos.minutosRestantes > 0);
});

test('pedir wallet dos veces devuelve LA MISMA preferencia, no una segunda', async () => {
  const { comprador, orden } = escenario(500);

  const uno = await wallet(comprador.token, orden.id);
  const dos = await wallet(comprador.token, orden.id);

  assert.strictEqual(uno.status, 200);
  assert.strictEqual(dos.status, 200);
  assert.strictEqual(dos.datos.preferenceId, uno.datos.preferenceId);
  assert.strictEqual(dos.datos.initPoint, uno.datos.initPoint);
  assert.strictEqual(llamadasPreferencia.length, 1,
    'dos enlaces vivos son dos cobros posibles de la misma orden');
});

test('el importe no cambia al reutilizar la preferencia', async () => {
  const { comprador, orden } = escenario(500);
  await wallet(comprador.token, orden.id);
  const dos = await wallet(comprador.token, orden.id);
  assert.strictEqual(dos.datos.amount, 500);
});

test('caducada la preferencia, se desbloquea la tarjeta y se crea una nueva', async () => {
  const { comprador, orden } = escenario(500);
  await wallet(comprador.token, orden.id);

  // Se envejece el bloqueo como lo haría el paso del tiempo.
  db.getDb().prepare('UPDATE orders SET mp_preference_expires_at = ? WHERE id = ?')
    .run(new Date(Date.now() - 1000).toISOString(), orden.id);

  const nueva = await wallet(comprador.token, orden.id);
  assert.strictEqual(nueva.status, 200);
  assert.strictEqual(llamadasPreferencia.length, 2,
    'una orden no puede quedar impagable para siempre por una preferencia vencida');

  // Y la tarjeta vuelve a estar disponible… salvo que la nueva preferencia
  // acaba de bloquearla otra vez, que es justo lo correcto.
  const res = await checkoutTarjeta(comprador.token, orden.id, 'tok_x');
  assert.strictEqual(res.status, 409);
  assert.strictEqual(res.datos.motivo, 'preferencia_en_curso');
});

test('una fecha de caducidad ilegible bloquea, no desbloquea', async () => {
  // Ante la duda se bloquea: un cobro bloqueado se reintenta en unos
  // minutos, uno duplicado no se deshace.
  const { comprador, orden } = escenario(500);
  await wallet(comprador.token, orden.id);

  db.getDb().prepare('UPDATE orders SET mp_preference_expires_at = ? WHERE id = ?')
    .run('no-es-una-fecha', orden.id);

  const res = await checkoutTarjeta(comprador.token, orden.id, 'tok_y');
  assert.strictEqual(res.status, 409);
  assert.strictEqual(llamadasCrearPago.length, 0);
});

test('la preferencia queda guardada en la orden, no solo devuelta', async () => {
  // Si no se guardara, existiría en Mercado Pago una preferencia pagable de
  // la que este servidor no sabe nada, y el bloqueo no la vería.
  const { comprador, orden } = escenario(500);
  await wallet(comprador.token, orden.id);

  const guardada = store.getOrdenPorId(orden.id);
  assert.strictEqual(guardada.mp_preference_id, 'pref_123');
  assert.ok(guardada.mp_preference_init_point.startsWith('https://'));
  // El bloqueo dura MÁS que la ventana de pago, nunca menos.
  const expira = new Date(guardada.mp_preference_expires_at).getTime();
  assert.ok(expira > Date.now() + 15 * 60 * 1000,
    'el bloqueo tiene que sobrevivir a la ventana en la que MP acepta el pago');
});

test('la caducidad va a MP con desplazamiento explícito, no con Z', async () => {
  // MP documenta '+00:00' y ha devuelto 400 con la 'Z'. Un 400 aquí no
  // degrada nada: tumba el método de pago entero.
  const { comprador, orden } = escenario(500);
  await wallet(comprador.token, orden.id);

  const { expiration_date_to: fecha } = llamadasPreferencia[0].preferencia;
  assert.ok(/[+-]\d{2}:\d{2}$/.test(fecha), `formato inesperado: ${fecha}`);
});

test('una orden ya pagada no reabre la preferencia guardada', async () => {
  const { comprador, orden } = escenario(500);
  await wallet(comprador.token, orden.id);
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: 'pay_dup', paymentStatus: 'approved' });

  const res = await wallet(comprador.token, orden.id);
  assert.strictEqual(res.status, 409, 'ya se cobró: no puede devolverse un enlace de pago');
});

// ─── El candado y sus fallos ────────────────────────────────────
//
// Comprobar "¿hay preferencia viva?" y crearla son dos pasos con un `await`
// a Mercado Pago en medio. Node atiende otra petición durante esa espera, y
// sin candado las dos crean su propia preferencia: dos enlaces vivos que
// cobran lo mismo.

test('dos peticiones simultáneas crean UNA sola preferencia', async () => {
  const { comprador, orden } = escenario(500);

  // Se retiene la respuesta de MP para que las dos peticiones coincidan
  // dentro de la ventana peligrosa, que es justo el `await` a MP.
  let soltar;
  const enVuelo = new Promise((r) => { soltar = r; });
  respuestaPreferencia = async () => {
    await enVuelo;
    return { id: 'pref_carrera', init_point: 'https://mp.test/carrera' };
  };

  const a = wallet(comprador.token, orden.id);
  const b = wallet(comprador.token, orden.id);
  await new Promise(r => setTimeout(r, 50));
  soltar();

  const [ra, rb] = await Promise.all([a, b]);

  assert.strictEqual(llamadasPreferencia.length, 1,
    'dos enlaces vivos = la misma orden cobrable dos veces');

  // Una gana; la otra tiene que decir "espera", nunca crear la suya.
  const oks = [ra, rb].filter(r => r.status === 200);
  const esperas = [ra, rb].filter(r => r.status === 409);
  assert.strictEqual(oks.length, 1);
  assert.strictEqual(esperas.length, 1);
  assert.strictEqual(esperas[0].datos.motivo, 'preferencia_en_curso');
});

test('durante la reserva, el cobro con tarjeta también queda bloqueado', async () => {
  // La rendija más fina: entre reservar y que la preferencia exista. Si el
  // bloqueo mirara el id en vez de la fecha, aquí entraría un cobro con
  // tarjeta justo mientras nace un enlace de pago para la misma orden.
  const { comprador, orden } = escenario(500);

  let soltar;
  const enVuelo = new Promise((r) => { soltar = r; });
  respuestaPreferencia = async () => {
    await enVuelo;
    return { id: 'pref_rendija', init_point: 'https://mp.test/rendija' };
  };

  const pendiente = wallet(comprador.token, orden.id);
  await new Promise(r => setTimeout(r, 50));

  const tarjeta = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: orden.id, card_token: 'tok_rendija' },
  });

  assert.strictEqual(tarjeta.status, 409);
  assert.strictEqual(llamadasCrearPago.length, 0);

  soltar();
  await pendiente;
});

test('si Mercado Pago RECHAZA la petición, la orden no queda bloqueada', async () => {
  // Un 4xx significa que MP no creó nada. Dejar el candado echado castigaría
  // al comprador 15 minutos por un cobro que nunca existió.
  const { comprador, orden } = escenario(500);
  respuestaPreferencia = async () => {
    throw new mpClient.MpError('Mercado Pago respondió 400', {
      status: 400, detalle: { message: 'invalid' },
    });
  };

  const res = await wallet(comprador.token, orden.id);
  assert.strictEqual(res.status, 502);

  const guardada = store.getOrdenPorId(orden.id);
  assert.strictEqual(guardada.mp_preference_expires_at, null,
    'el candado tiene que soltarse: MP no creó ninguna preferencia');

  // Y el cobro con tarjeta vuelve a estar disponible.
  const tarjeta = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: orden.id, card_token: 'tok_tras_400' },
  });
  assert.strictEqual(tarjeta.status, 200);
});

test('ante un timeout de Mercado Pago el candado NO se suelta', async () => {
  // Aquí no se sabe si la preferencia llegó a existir. Soltar el candado
  // permitiría cobrar con tarjeta una orden que quizá tiene un enlace de
  // pago vivo. Bloquear de más es recuperable; cobrar dos veces no.
  const { comprador, orden } = escenario(500);
  respuestaPreferencia = async () => {
    throw new mpClient.MpError('No se pudo contactar a Mercado Pago', {
      causa: 'timeout',
    });
  };

  const res = await wallet(comprador.token, orden.id);
  assert.strictEqual(res.status, 502);

  const guardada = store.getOrdenPorId(orden.id);
  assert.ok(guardada.mp_preference_expires_at, 'el candado debe seguir echado');

  const tarjeta = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: orden.id, card_token: 'tok_tras_timeout' },
  });
  assert.strictEqual(tarjeta.status, 409);
  assert.strictEqual(llamadasCrearPago.length, 0);
});

test('una preferencia sin init_point pero CON id sigue bloqueando', async () => {
  // Existe en Mercado Pago y puede ser pagable aunque no podamos ofrecerla.
  const { comprador, orden } = escenario(500);
  respuestaPreferencia = async () => ({ id: 'pref_sin_enlace' });

  const res = await wallet(comprador.token, orden.id);
  assert.strictEqual(res.status, 502);

  const guardada = store.getOrdenPorId(orden.id);
  assert.strictEqual(guardada.mp_preference_id, 'pref_sin_enlace');

  const tarjeta = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: orden.id, card_token: 'tok_sin_enlace' },
  });
  assert.strictEqual(tarjeta.status, 409, 'ese enlace puede cobrar: no se abre la tarjeta');
});

test('tocar el botón de más no gasta el cupo de intentos de pago', async () => {
  // El candado ya impide crear más de una preferencia por orden, así que
  // contar los 409 solo consigue que quien tuvo prisa se quede sin poder
  // pagar durante un cuarto de hora.
  const { comprador, orden } = escenario(500);

  const primera = await wallet(comprador.token, orden.id);
  assert.strictEqual(primera.status, 200);

  // Muchas más de las 20 del límite: todas devuelven la preferencia ya
  // creada sin salir a MP.
  for (let i = 0; i < 30; i++) {
    const res = await wallet(comprador.token, orden.id);
    assert.strictEqual(res.status, 200, `la petición ${i + 2} no debería agotar el cupo`);
  }
  assert.strictEqual(llamadasPreferencia.length, 1);
});

test('pero el límite SÍ frena cuando cada intento crea una preferencia', async () => {
  // La contraparte del test anterior: no vale con desactivar el límite. Cada
  // orden nueva sí crea una preferencia en la cuenta del vendedor, y eso es
  // lo que el límite existe para acotar.
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  store.guardarCuentaVendedor(vendedor.id, {
    mpUserId: `mp_${vendedor.id}`,
    accessToken: 'vendor-access-token',
    refreshToken: 'vendor-refresh-token',
    expiresIn: 30 * 24 * 60 * 60,
  });
  const producto = crearProducto(vendedor.id, 50);

  const nuevaOrden = () => store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: 50, applicationFee: 2.5, currency: 'MXN', origin: 'direct',
    items: [{ productId: producto, quantity: 1, unitPrice: 50, title: 'Cosa' }],
  });

  let frenado = false;
  for (let i = 0; i < 25; i++) {
    respuestaPreferencia = async () => ({
      id: `pref_lim_${i}`, init_point: `https://mp.test/${i}`,
    });
    const res = await wallet(comprador.token, nuevaOrden().id);
    if (res.status === 429) { frenado = true; break; }
  }
  assert.ok(frenado, 'crear preferencias sin fin en la cuenta del vendedor sí debe frenarse');
});

// ─── Seguridad del puente de vuelta ─────────────────────────────
//
// Es la única ruta de pagos SIN autenticación: quien llega es un navegador
// que viene de un redirect de Mercado Pago, sin la sesión de la app. Todo lo
// que entra por su query string es texto de un desconocido.

test('el puente no refleja HTML: no hay XSS por la query string', async () => {
  const carga = '"><script>alert(1)</script>';
  const res = await fetch(
    `${baseUrl}/api/payments/wallet/return?orden=${encodeURIComponent(carga)}&r=ok`,
  );
  const html = await res.text();

  assert.ok(!html.includes('<script>alert(1)</script>'), 'script inyectado en la página');
  assert.ok(!html.includes('"><script'), 'se escapó del atributo href');
});

test('el destino del puente es siempre nuestro deep link, no uno ajeno', async () => {
  // Si el destino se pudiera controlar, esta ruta sería un redirector
  // abierto con el dominio del backend detrás.
  const res = await fetch(
    `${baseUrl}/api/payments/wallet/return?orden=https://sitio-malo.test&r=ok`,
  );
  const html = await res.text();

  const destinos = [...html.matchAll(/href="([^"]*)"/g)].map(m => m[1]);
  assert.ok(destinos.length > 0);
  for (const destino of destinos) {
    assert.ok(destino.startsWith('mercaditoum://payments/'),
      `destino inesperado: ${destino}`);
  }
});

test('el puente no consulta ni toca la orden que le nombren', async () => {
  // No tiene sesión: si mirara la orden, cualquiera podría sondear órdenes
  // ajenas por su id. Y desde luego no puede marcarlas como pagadas.
  const { comprador, orden } = escenario(500);
  await wallet(comprador.token, orden.id);

  const res = await fetch(
    `${baseUrl}/api/payments/wallet/return?orden=${encodeURIComponent(orden.id)}&r=ok`,
  );
  const html = await res.text();

  const despues = store.getOrdenPorId(orden.id);
  assert.strictEqual(despues.status, 'pending');
  assert.strictEqual(despues.payment_status, null);
  // Y no filtra nada de la orden: ni importe, ni vendedor, ni comprador.
  assert.ok(!html.includes('500'));
  assert.ok(!html.includes(orden.vendor_id));
});

// ─── Secretos ───────────────────────────────────────────────────

test('ninguna respuesta del pago con cuenta MP filtra credenciales', async () => {
  const { comprador, orden } = escenario(500);
  const ok = await wallet(comprador.token, orden.id);

  respuestaPreferencia = async () => {
    throw new mpClient.MpError('400', {
      status: 400,
      detalle: { access_token: 'vendor-access-token', message: 'roto' },
    });
  };
  const { orden: otra } = escenario(500);
  const err = await wallet(comprador.token, otra.id);

  for (const cuerpo of [JSON.stringify(ok.datos), JSON.stringify(err.datos)]) {
    assert.ok(!cuerpo.includes('vendor-access-token'), 'token del vendedor filtrado');
    assert.ok(!cuerpo.includes(process.env.MP_ACCESS_TOKEN), 'token de la plataforma filtrado');
    assert.ok(!cuerpo.includes('TEST-'), 'credencial filtrada');
  }
});

test('el enlace de pago de una orden no se le da a otra persona', async () => {
  const { comprador, orden } = escenario(500);
  await wallet(comprador.token, orden.id);

  const intruso = crearUsuario();
  const res = await wallet(intruso.token, orden.id);

  assert.strictEqual(res.status, 404);
  assert.ok(!JSON.stringify(res.datos).includes('mercadopago'),
    'ni siquiera se insinúa que exista un enlace de pago');
});

// ─── Diagnóstico del checkout ───────────────────────────────────
//
// Estas pruebas existen por un fallo concreto: la preferencia se crea con
// 200, devolvemos su init_point, y al abrirlo Mercado Pago pinta su pantalla
// genérica de "algo salió mal". Con lo que había en los logs —una línea
// diciendo que la preferencia se creó— era imposible saber si el problema
// era el payload, la credencial o la propia cuenta del vendedor.
//
// Lo que se fija aquí es que ese diagnóstico exista y no se pueda volver en
// contra: que registre el payload y la respuesta, que NUNCA imprima un
// token, y que no sea capaz de tumbar un cobro que va bien.

test('registra el payload exacto que se le mandó a Mercado Pago', async () => {
  const { comprador, orden } = escenario(200);
  // El volcado íntegro vive detrás del interruptor de depuración: es el que
  // hace falta cuando MP acepta la preferencia y su checkout falla igual.
  process.env.MP_DEBUG_PREFERENCIA = 'true';

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(logs.includes(orden.id), 'la orden tiene que poder buscarse en el log');
  assert.ok(logs.includes('marketplace_fee'), 'la comisión enviada no aparece');
  assert.ok(logs.includes('external_reference'), 'el payload no se registró entero');
  assert.ok(logs.includes('expiration_date_to'), 'la caducidad enviada no aparece');
});

test('registra la respuesta de Mercado Pago, no solo que hubo una', async () => {
  const { comprador, orden } = escenario(200);
  respuestaPreferencia = async () => ({
    id: 'pref_abc',
    init_point: 'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_abc',
    sandbox_init_point: 'https://sandbox.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_abc',
    collector_id: 456,
  });

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(logs.includes('pref_abc'), 'el id devuelto por MP no aparece');
  assert.ok(logs.includes('collector_id') || logs.includes('456'),
    'no se puede saber a qué cuenta pertenece la preferencia');
});

test('el diagnóstico no imprime jamás el token del vendedor', async () => {
  const { comprador, orden } = escenario(200);
  // MP hace eco de parte del payload en algunas respuestas, así que el
  // camino de vuelta también tiene que ir redactado.
  respuestaPreferencia = async () => ({
    id: 'pref_123',
    init_point: 'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
    access_token: 'vendor-access-token',
  });

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(!logs.includes('vendor-access-token'), 'token del vendedor en el log');
  assert.ok(!logs.includes(process.env.MP_ACCESS_TOKEN), 'token de la plataforma en el log');
});

test('relee la preferencia en MP y avisa si el marketplace_fee no se guardó', async () => {
  const { comprador, orden } = escenario(200);
  // MP acepta la preferencia y devuelve 200 aunque haya ignorado la
  // comisión. Es el fallo que no da error: el cobro funciona y la
  // plataforma no cobra nada. Solo se ve releyendo lo que quedó guardado.
  respuestaObtenerPreferencia = async () => ({ id: 'pref_123', collector_id: 456 });

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.strictEqual(llamadasObtenerPreferencia.length, 1, 'no se releyó la preferencia');
  assert.strictEqual(llamadasObtenerPreferencia[0].id, 'pref_123');
  assert.ok(/comisión|marketplace_fee/i.test(logs));
  assert.ok(/no.*guard|ignor/i.test(logs), `el aviso no dice qué pasó: ${logs}`);
});

test('si releer la preferencia falla, el cobro sigue funcionando', async () => {
  const { comprador, orden } = escenario(200);
  // El diagnóstico es un extra. Que MP no deje releer la preferencia no
  // puede dejar a nadie sin poder pagar: el enlace ya existe y es válido.
  respuestaObtenerPreferencia = async () => {
    throw new mpClient.MpError('MP no respondió', { status: 500 });
  };

  let res;
  const logs = await capturandoLogs(async () => {
    res = await wallet(comprador.token, orden.id);
  });

  assert.strictEqual(res.status, 200);
  assert.ok(res.datos.initPoint.startsWith('https://'));
  assert.ok(/relee|relectura|comproba/i.test(logs), 'el fallo del diagnóstico no se registró');
});

test('avisa cuando MP devuelve un sandbox_init_point', async () => {
  const { comprador, orden } = escenario(200);
  respuestaPreferencia = async () => ({
    id: 'pref_123',
    init_point: 'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
    sandbox_init_point: 'https://sandbox.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
  });

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(/sandbox/i.test(logs), 'no se avisa de que hay un enlace de sandbox');
});

// ─── Qué checkout se abre: siempre el normal ────────────────────
//
// COMPROBADO A MANO el 2026-08-14, y por eso está escrito aquí: una
// preferencia creada con el token de un vendedor de prueba se abrió en
// www.mercadopago.com.mx sin sesión iniciada, pintó el formulario, aceptó la
// tarjeta de prueba y llegó a "Revisa tu pago". El `init_point` es el bueno
// también en pruebas.
//
// Estas pruebas existen porque se creyó lo contrario durante una noche
// entera. El checkout cargaba "Oh, no, algo anduvo mal" y se dio por hecho
// que era el enlace; en realidad era la cuenta compradora de prueba, a la
// que MP le exigía un código enviado a un buzón inexistente. Mandar al
// comprador a sandbox no arregló nada, porque nunca fue eso.

const CON_LOS_DOS_ENLACES = async () => ({
  id: 'pref_123',
  init_point: 'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
  sandbox_init_point: 'https://sandbox.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
});

test('con credenciales TEST- se sigue mandando al checkout normal', async () => {
  const { comprador, orden } = escenario(200);
  respuestaPreferencia = CON_LOS_DOS_ENLACES;

  const res = await wallet(comprador.token, orden.id);

  assert.strictEqual(res.status, 200);
  assert.strictEqual(
    res.datos.initPoint,
    'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
  );
});

test('un vendedor de prueba tampoco manda a sandbox', async () => {
  const { comprador, orden } = escenario(200, { accessToken: 'APP_USR-1234567890' });
  const original = process.env.MP_ACCESS_TOKEN;
  respuestaValidarToken = async (t) => (
    t === original
      ? { id: 123 }
      : { id: 3612507126, nickname: 'TESTUSER2561821311127742274',
          email: 'test_user_2561821311127742274@testuser.com' }
  );
  respuestaPreferencia = CON_LOS_DOS_ENLACES;

  const res = await wallet(comprador.token, orden.id);

  assert.strictEqual(res.status, 200);
  assert.ok(!res.datos.initPoint.includes('sandbox.'),
    `se devolvió ${res.datos.initPoint}`);
});

test('MP_USE_SANDBOX_INIT_POINT=true sigue sirviendo como salida de emergencia', async () => {
  const { comprador, orden } = escenario(200);
  process.env.MP_USE_SANDBOX_INIT_POINT = 'true';
  respuestaPreferencia = CON_LOS_DOS_ENLACES;

  const res = await wallet(comprador.token, orden.id);

  assert.strictEqual(res.status, 200);
  assert.ok(res.datos.initPoint.startsWith('https://sandbox.'),
    `se devolvió ${res.datos.initPoint}`);
});

test('el log dice en cada preferencia qué enlace se eligió y en qué entorno', async () => {
  const { comprador, orden } = escenario(200);
  respuestaPreferencia = CON_LOS_DOS_ENLACES;

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(/checkout NORMAL/i.test(logs), `el log no dice qué enlace se eligió:\n${logs}`);
  assert.ok(/TEST-/.test(logs), `el log no dice en qué entorno:\n${logs}`);
});

test('un enlace de sandbox no pedido no llega al comprador', async () => {
  // La red de seguridad: si MP devolviera un `init_point` que apunta a
  // sandbox, falla aquí y no en la cara del comprador.
  const { comprador, orden } = escenario(200);
  respuestaPreferencia = async () => ({
    id: 'pref_123',
    init_point: 'https://sandbox.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
  });

  const res = await wallet(comprador.token, orden.id);

  assert.strictEqual(res.status, 502, `se entregó ${res.datos.initPoint}`);
});

test('el interruptor de sandbox no rompe nada si MP no manda uno', async () => {
  const { comprador, orden } = escenario(200);
  // Producción: encender el interruptor por error no puede dejar sin pagar.
  // Si no hay enlace de sandbox, se sigue usando el normal.
  process.env.MP_USE_SANDBOX_INIT_POINT = 'true';

  const res = await wallet(comprador.token, orden.id);

  assert.strictEqual(res.status, 200);
  assert.strictEqual(
    res.datos.initPoint,
    'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
  );
});

// ─── Identificar la cuenta del vendedor, sin mentir ─────────────
//
// Estas pruebas existen porque una etiqueta mal escrita costó un
// diagnóstico entero. El log decía "credencial del vendedor = PRODUCCIÓN
// (APP_USR-)" de una cuenta que era de PRUEBA, y esa línea se leyó —con toda
// razón— como la causa raíz del fallo.
//
// El prefijo `APP_USR-` NO distingue prueba de producción en un token de
// vendedor: los usuarios de prueba que autorizan por OAuth también reciben
// tokens `APP_USR-`. Lo único que lo dice es a quién pertenece la cuenta,
// que es lo que responde `GET /users/me`.

test('no llama PRODUCCIÓN a un token de vendedor APP_USR-', async () => {
  const { comprador, orden } = escenario(200, { accessToken: 'APP_USR-1234567890' });
  respuestaValidarToken = async (t) => (
    t === process.env.MP_ACCESS_TOKEN
      ? { id: 123 }
      : { id: 3612507126, nickname: 'TESTUSER2561821311127742274',
          email: 'test_user_2561821311127742274@testuser.com' }
  );

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(!/vendedor\s*=\s*PRODUCCIÓN/i.test(logs),
    `el log afirma que una cuenta de prueba es de producción:\n${logs}`);
});

test('el log identifica la cuenta del vendedor y dice si es de prueba', async () => {
  const { comprador, orden } = escenario(200, { accessToken: 'APP_USR-1234567890' });
  respuestaValidarToken = async (t) => (
    t === process.env.MP_ACCESS_TOKEN
      ? { id: 123 }
      : { id: 3612507126, nickname: 'TESTUSER2561821311127742274',
          email: 'test_user_2561821311127742274@testuser.com' }
  );

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(logs.includes('3612507126'), 'no se puede saber qué cuenta cobra');
  assert.ok(/prueba/i.test(logs), `no dice que la cuenta es de prueba:\n${logs}`);
});

test('una cuenta de vendedor real no se marca como de prueba', async () => {
  const { comprador, orden } = escenario(200, { accessToken: 'APP_USR-9999999999' });

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(!/vendedor.*de prueba/i.test(logs),
    `una cuenta real se está marcando como de prueba:\n${logs}`);
});

test('registra qué enlace se le devolvió al comprador', async () => {
  // Sin esto no se puede comprobar desde los logs si MP_USE_SANDBOX_INIT_POINT
  // llegó a surtir efecto: es la diferencia entre "lo probamos" y "creemos
  // que lo probamos".
  const { comprador, orden } = escenario(200);
  process.env.MP_USE_SANDBOX_INIT_POINT = 'true';
  respuestaPreferencia = async () => ({
    id: 'pref_123',
    init_point: 'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
    sandbox_init_point: 'https://sandbox.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123',
  });

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(/devuelto|se devolvió/i.test(logs), 'no se registra el enlace entregado');
  assert.ok(logs.includes('https://sandbox.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_123'),
    `el log no dice qué enlace se entregó:\n${logs}`);
});

// ─── payer.email con cuentas de prueba ──────────────────────────

test('con un vendedor de prueba no se manda payer.email', async () => {
  // Mercado Pago rechaza pagos de prueba cuyo `payer.email` no corresponde a
  // la cuenta con la que se entra al checkout. Nosotros mandábamos el correo
  // de la cuenta de Marketplace, que nunca es el del usuario de prueba
  // comprador: omitirlo deja que MP use el de la sesión.
  const { comprador, orden } = escenario(200, { accessToken: 'APP_USR-1234567890' });
  respuestaValidarToken = async (t) => (
    t === process.env.MP_ACCESS_TOKEN
      ? { id: 123 }
      : { id: 3612507126, nickname: 'TESTUSER2561821311127742274',
          email: 'test_user_2561821311127742274@testuser.com' }
  );

  const res = await wallet(comprador.token, orden.id);

  assert.strictEqual(res.status, 200);
  const { preferencia } = llamadasPreferencia[0];
  assert.strictEqual(preferencia.payer, undefined,
    'con vendedor de prueba, el payer lo pone la sesión de MP');
});

test('con un vendedor real sí se manda payer.email', async () => {
  // La otra mitad: en producción el correo del comprador es el correcto y
  // quitarlo empeoraría el checkout (MP lo pediría a mano).
  const { comprador, orden } = escenario(200);

  await wallet(comprador.token, orden.id);

  const { preferencia } = llamadasPreferencia[0];
  assert.ok(preferencia.payer?.email, 'en producción el payer.email debe ir');
});

// ─── Volumen de los logs ────────────────────────────────────────
//
// El diagnóstico completo vuelca el payload y la respuesta entera de MP —y
// la respuesta de MP son ~2 KB por pago, dos veces (creación y relectura)—.
// Eso es lo correcto mientras se persigue un fallo y es puro ruido el resto
// del tiempo: un log que nadie puede leer no se lee cuando hace falta.
//
// Por defecto queda lo que sirve para entender un pago de un vistazo; el
// volcado entero se enciende con MP_DEBUG_PREFERENCIA.

test('por defecto no vuelca la respuesta entera de MP', async () => {
  const { comprador, orden } = escenario(200);

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(!logs.includes('payload ->'), 'vuelca el payload entero sin pedirlo');
  assert.ok(!/respuesta de Mercado Pago:/.test(logs), 'vuelca la respuesta entera sin pedirlo');
  assert.ok(!/preferencia releída de MP:/.test(logs), 'vuelca la relectura entera sin pedirlo');
});

test('por defecto sigue registrando lo imprescindible', async () => {
  // Recortar no puede significar quedarse sin diagnóstico: quién cobra, qué
  // enlace se entregó y el id de la preferencia tienen que estar siempre.
  const { comprador, orden } = escenario(200);

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(logs.includes(orden.id), 'la orden no es buscable en el log');
  assert.ok(/cuenta del vendedor/.test(logs), 'no se sabe qué cuenta cobra');
  assert.ok(/enlace devuelto/.test(logs), 'no se sabe qué enlace se entregó');
  assert.ok(logs.includes('pref_123'), 'no aparece el id de la preferencia');
  assert.ok(/marketplace_fee|comisión/i.test(logs), 'no se sabe si fue con comisión');
});

test('los avisos siguen saliendo aunque el log esté recortado', async () => {
  // Un aviso que solo aparece en modo depuración es un aviso que nadie ve.
  const { comprador, orden } = escenario(200);
  respuestaObtenerPreferencia = async () => ({ id: 'pref_123', collector_id: 456 });

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(/no.*guard|ignor/i.test(logs), `el aviso de comisión desapareció:\n${logs}`);
});

test('MP_DEBUG_PREFERENCIA=true vuelve a volcarlo todo', async () => {
  const { comprador, orden } = escenario(200);
  process.env.MP_DEBUG_PREFERENCIA = 'true';

  const logs = await capturandoLogs(() => wallet(comprador.token, orden.id));

  assert.ok(logs.includes('payload ->'), 'el modo depuración no vuelca el payload');
  assert.ok(/respuesta de Mercado Pago:/.test(logs), 'no vuelca la respuesta');
  assert.ok(logs.includes('external_reference'), 'el volcado está incompleto');
});

test('una preferencia guardada con un enlace de sandbox no se reentrega', async () => {
  // El camino de reutilización devuelve el enlace GUARDADO sin volver a
  // pasar por elegirInitPoint. Sin comprobarlo aquí, un enlace escrito por
  // una versión anterior del código —o por un MP_USE_SANDBOX_INIT_POINT que
  // ya se quitó— se seguiría entregando hasta que caducara. Pasó de verdad.
  const { comprador, orden } = escenario(200);
  store.guardarPreferenciaDeOrden(orden.id, {
    preferenceId: 'pref_vieja',
    initPoint: 'https://sandbox.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_vieja',
    expiraEn: new Date(Date.now() + 10 * 60 * 1000),
  });

  const res = await wallet(comprador.token, orden.id);

  assert.strictEqual(res.status, 502, `se entregó ${res.datos.initPoint}`);
  assert.ok(!String(res.datos.initPoint || '').includes('sandbox'),
    'el enlace de sandbox llegó al comprador');
});

test('el enlace guardado que sí sirve se sigue reutilizando', async () => {
  // La comprobación anterior no puede romper el caso normal: reutilizar la
  // misma preferencia es lo que evita dos enlaces vivos sobre una orden.
  const { comprador, orden } = escenario(200);
  const bueno = 'https://www.mercadopago.com.mx/checkout/v1/redirect?pref_id=pref_buena';
  store.guardarPreferenciaDeOrden(orden.id, {
    preferenceId: 'pref_buena',
    initPoint: bueno,
    expiraEn: new Date(Date.now() + 10 * 60 * 1000),
  });

  const res = await wallet(comprador.token, orden.id);

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.datos.initPoint, bueno);
  assert.strictEqual(llamadasPreferencia.length, 0, 'no debió crear una preferencia nueva');
});
