// Ciclo de vida de la conexión de pagos de un vendedor: desconexión y sus
// consecuencias.
//
// Un vendedor puede perder la conexión de tres formas: la corta él desde la
// app, la revoca desde el panel de Mercado Pago (y nos enteramos por
// webhook), o nos enteramos tarde al intentar cobrar. Las tres tienen que
// dejar el sistema en el mismo estado coherente — si no, queda una opción de
// "tarjeta" que el comprador puede elegir y que no cobra nada.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');
const crypto = require('node:crypto');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-connection-')),
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

// ─── Dobles de prueba de mpClient ───────────────────────────────
const mpClient = require('./mpClient');
let respuestaValidarToken = async () => ({ id: 123 });
let respuestaCrearPago = async () => ({ id: 'pay_1', status: 'approved' });
let llamadasCrearPago = [];

mpClient.validarTokenVendedor = async (t) => respuestaValidarToken(t);
mpClient.crearPago = async (args) => { llamadasCrearPago.push(args); return respuestaCrearPago(args); };

const store = require('./store');
const conexion = require('./connection');
const { tarjetaDisponible } = require('./methods');
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

test.beforeEach(() => {
  llamadasCrearPago = [];
  respuestaValidarToken = async () => ({ id: 123 });
});

let contador = 0;

function crearUsuario({ tipoCuenta = 'estudiante', metodos = ['efectivo'] } = {}) {
  const id = `u_cx_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified,
       tipo_cuenta, paymentMethods)
     VALUES (?, ?, ?, 'TT', '', ?, 1, ?, ?)`,
  ).run(id, `Test ${id}`, `${id}@ejemplo.com`, tipoCuenta === 'negocio' ? 1 : 0, tipoCuenta,
    metodos === null ? null : JSON.stringify(metodos));
  return { id, token: generateToken(id) };
}

function crearProducto(sellerId, precio) {
  const id = `p_cx_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO products (id, title, price, priceNum, seller, category)
     VALUES (?, ?, ?, ?, ?, 'otros')`,
  ).run(id, `Producto ${id}`, `$${precio}`, precio, sellerId);
  return id;
}

function conectar(sellerId) {
  store.guardarCuentaVendedor(sellerId, {
    mpUserId: `mp_${sellerId}`,
    accessToken: 'vendor-access-token',
    refreshToken: 'vendor-refresh-token',
    expiresIn: 30 * 24 * 60 * 60,
    publicKey: 'APP_USR-pk',
  });
}

const metodosDe = (id) => JSON.parse(
  db.getDb().prepare('SELECT paymentMethods FROM sellers WHERE id = ?').get(id).paymentMethods,
);

const notificacionesDe = (id) => db.getDb()
  .prepare('SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at').all(id);

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

// ─── Consecuencias de una desconexión ───────────────────────────

test('desconectar retira tarjeta de los métodos aceptados del vendedor', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  conectar(vendedor.id);

  conexion.desconectar(vendedor.id, { motivo: 'revocado en MP', por: 'webhook' });

  assert.deepStrictEqual(metodosDe(vendedor.id), ['efectivo'],
    'dejar tarjeta puesta la ofrecería en el checkout sin nada detrás');
  assert.strictEqual(tarjetaDisponible(vendedor.id), false);
});

test('un vendedor que solo aceptaba tarjeta no se queda sin métodos', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  conectar(vendedor.id);

  conexion.desconectar(vendedor.id, { motivo: 'x', por: 'webhook' });

  // El perfil exige al menos un método; vaciarlo le bloquearía guardar
  // cualquier cambio hasta que se diera cuenta.
  assert.deepStrictEqual(metodosDe(vendedor.id), ['efectivo']);
});

test('desconectar borra las tarjetas guardadas con ese vendedor', () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  conectar(vendedor.id);
  store.guardarCustomerId(comprador.id, vendedor.id, 'cus_1');
  store.guardarTarjeta(comprador.id, vendedor.id, { mpCardId: 'card_1', lastFour: '4242' });

  conexion.desconectar(vendedor.id, { motivo: 'x', por: 'webhook' });

  // Esos Customers viven dentro de una cuenta que ya no podemos usar: la
  // tarjeta es incobrable y ofrecerla solo produce pagos fallidos.
  assert.deepStrictEqual(store.listarTarjetas(comprador.id, vendedor.id), []);
});

test('desconectar avisa al vendedor para que reconecte', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  conectar(vendedor.id);

  conexion.desconectar(vendedor.id, { motivo: 'revocado', por: 'webhook' });

  const avisos = notificacionesDe(vendedor.id);
  assert.strictEqual(avisos.length, 1, 'el vendedor tiene que enterarse de que dejó de cobrar');
  assert.match(avisos[0].type, /pago|payment|mercado/i);
});

test('desconectar dos veces no vuelve a notificar', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  conectar(vendedor.id);

  assert.strictEqual(conexion.desconectar(vendedor.id, { motivo: 'a', por: 'webhook' }), true);
  assert.strictEqual(conexion.desconectar(vendedor.id, { motivo: 'b', por: 'token_check' }), false);

  // MP reenvía el webhook de revocación varias veces: sin esto el vendedor
  // recibiría una ristra de avisos idénticos.
  assert.strictEqual(notificacionesDe(vendedor.id).length, 1);
});

test('reconectar deja la cuenta limpia de la desconexión anterior', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo'] });
  conectar(vendedor.id);
  conexion.desconectar(vendedor.id, { motivo: 'revocado', por: 'webhook' });

  conectar(vendedor.id); // vuelve a autorizar

  assert.strictEqual(tarjetaDisponible(vendedor.id), true);
  const cuenta = store.getCuentaVendedorIncluyendoRevocada(vendedor.id);
  assert.strictEqual(cuenta.revoked_at, null);
  assert.strictEqual(cuenta.disconnect_reason, null,
    'un vendedor que ya volvió no debe seguir viendo el aviso de reconectar');
});

// ─── Validación bajo demanda del token ──────────────────────────

test('validar detecta un token revocado y desconecta la cuenta', async () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  conectar(vendedor.id);

  // El vendedor quitó la autorización desde su panel de MP y el webhook
  // nunca llegó: esta es la red de seguridad.
  respuestaValidarToken = async () => {
    throw new mpClient.MpError('revocado', { status: 401 });
  };

  const res = await pedir('POST', '/api/payments/account/validate', { token: vendedor.token });
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.datos.connected, false);
  assert.strictEqual(tarjetaDisponible(vendedor.id), false);
});

test('validar no desconecta por una caída pasajera de Mercado Pago', async () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  conectar(vendedor.id);

  // Un 500 de MP o una red caída no significan que el vendedor revocó nada.
  // Desconectarlo aquí sería tirarle el negocio por un hipo de la API.
  respuestaValidarToken = async () => {
    throw new mpClient.MpError('MP caído', { status: 500 });
  };

  const res = await pedir('POST', '/api/payments/account/validate', { token: vendedor.token });
  assert.strictEqual(tarjetaDisponible(vendedor.id), true,
    'un fallo transitorio no puede desconectar a nadie');
  assert.strictEqual(res.datos.connected, true);
});

// ─── Webhook de revocación ──────────────────────────────────────

function firmar({ dataId, requestId, ts }) {
  return crypto.createHmac('sha256', 'TEST-webhook-secret')
    .update(`id:${dataId};request-id:${requestId};ts:${ts};`).digest('hex');
}

async function enviarWebhook({ tipo, accion, mpUserId, requestId }) {
  const ts = Math.floor(Date.now() / 1000);
  const v1 = firmar({ dataId: mpUserId, requestId, ts });
  const res = await fetch(`${baseUrl}/api/payments/webhook?data.id=${mpUserId}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-signature': `ts=${ts},v1=${v1}`,
      'x-request-id': requestId,
    },
    body: JSON.stringify({
      type: tipo, action: accion, data: { id: mpUserId },
      id: `evt_${crypto.randomUUID()}`, user_id: mpUserId,
    }),
  });
  return res.status;
}

async function esperar(fn, { intentos = 40, esperaMs = 10 } = {}) {
  for (let i = 0; i < intentos; i++) {
    if (fn()) return true;
    await new Promise(r => setTimeout(r, esperaMs));
  }
  return false;
}

test('el webhook de revocación desconecta al vendedor', async () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  conectar(vendedor.id);
  const mpUserId = `mp_${vendedor.id}`;

  const status = await enviarWebhook({
    tipo: 'application', accion: 'application.deauthorized',
    mpUserId, requestId: 'req-deauth',
  });
  assert.strictEqual(status, 200);

  const desconectado = await esperar(() => !tarjetaDisponible(vendedor.id));
  assert.ok(desconectado, 'la revocación notificada por MP debe reflejarse en la app');
  assert.strictEqual(notificacionesDe(vendedor.id).length, 1);
});

test('un webhook de revocación de un mp_user_id desconocido no rompe nada', async () => {
  const status = await enviarWebhook({
    tipo: 'application', accion: 'application.deauthorized',
    mpUserId: 'mp_desconocido_999', requestId: 'req-deauth-x',
  });
  assert.strictEqual(status, 200);
});

// ─── Revocación descubierta en el momento de cobrar ─────────────

test('si el token murió entre crear la orden y cobrar, la orden no queda ambigua', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  conectar(vendedor.id);
  const producto = crearProducto(vendedor.id, 150);

  const orden = store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: 150, applicationFee: 7.5, currency: 'MXN', origin: 'direct',
    paymentMethod: 'tarjeta',
    items: [{ productId: producto, quantity: 1, unitPrice: 150, title: 'X' }],
  });

  // Entre la creación de la orden y el cobro, el vendedor revocó.
  respuestaValidarToken = async () => {
    throw new mpClient.MpError('revocado', { status: 401 });
  };

  const res = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: orden.id, card_token: 'ct_1' },
  });

  assert.strictEqual(res.status, 409);
  assert.strictEqual(llamadasCrearPago.length, 0,
    'no se debió intentar cobrar con un token muerto');

  const guardada = store.getOrdenPorId(orden.id);
  assert.strictEqual(guardada.status, 'requires_other_method',
    'la orden tiene que quedar en un estado que diga qué hacer, no en pending');

  // Ambas partes se enteran: el comprador para elegir otro método, el
  // vendedor para reconectar.
  assert.ok(notificacionesDe(comprador.id).length >= 1, 'falta avisar al comprador');
  assert.ok(notificacionesDe(vendedor.id).length >= 1, 'falta avisar al vendedor');
});

// ─── Precisión del webhook: no desconectar de más ───────────────

test('un evento application que NO es una revocación no desconecta a nadie', async () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  conectar(vendedor.id);
  const mpUserId = `mp_${vendedor.id}`;

  // MP manda eventos del topic 'application' que no son desautorizaciones.
  // Tratarlos como tales le tira el cobro a un vendedor que no hizo nada —
  // y equivocarse en esa dirección es mucho peor que quedarse corto, porque
  // la validación de token antes de cobrar ya cubre lo que se nos escape.
  await enviarWebhook({
    tipo: 'application', accion: 'application.authorized',
    mpUserId, requestId: 'req-auth',
  });
  await new Promise(r => setTimeout(r, 60));
  assert.strictEqual(tarjetaDisponible(vendedor.id), true);

  await enviarWebhook({
    tipo: 'application', accion: '',
    mpUserId, requestId: 'req-sin-accion',
  });
  await new Promise(r => setTimeout(r, 60));
  assert.strictEqual(tarjetaDisponible(vendedor.id), true,
    'un evento sin acción reconocible no es prueba de revocación');
});

// ─── No repetir avisos al comprador ─────────────────────────────

test('reintentar el checkout con el vendedor caído no repite los avisos', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  conectar(vendedor.id);
  const producto = crearProducto(vendedor.id, 90);

  const orden = store.crearOrden({
    id: `ord_${crypto.randomUUID()}`,
    buyerId: comprador.id, vendorId: vendedor.id,
    amount: 90, applicationFee: 4.5, currency: 'MXN', origin: 'direct',
    paymentMethod: 'tarjeta',
    items: [{ productId: producto, quantity: 1, unitPrice: 90, title: 'X' }],
  });

  respuestaValidarToken = async () => {
    throw new mpClient.MpError('revocado', { status: 401 });
  };

  for (let i = 0; i < 3; i++) {
    await pedir('POST', '/api/payments/checkout', {
      token: comprador.token,
      body: { order_id: orden.id, card_token: 'ct_$i' },
    });
  }

  // Tres toques del botón no son tres problemas distintos: es el mismo.
  assert.strictEqual(notificacionesDe(comprador.id).length, 1,
    'el comprador no debe recibir un aviso por cada toque del botón');
});

// ─── Quién puede conectar una cuenta de cobros ──────────────────
//
// Conectar Mercado Pago es requisito para verificarse. Si además hiciera
// falta estar verificado para conectar, la regla se muerde la cola y nadie
// completa ninguna de las dos. Lo que se exige es haber demostrado la
// identidad con el OTP.

function crearSinVerificar(tipoCuenta) {
  const id = `u_nv_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified,
       tipo_cuenta, paymentMethods)
     VALUES (?, ?, ?, 'TT', '', ?, 0, ?, '["efectivo"]')`,
  ).run(id, `Test ${id}`, `${id}@ejemplo.com`, tipoCuenta === 'negocio' ? 1 : 0, tipoCuenta);
  return { id, token: generateToken(id) };
}

function confirmarIdentidad(usuarioId, tipoCuenta) {
  db.getDb().prepare(
    `INSERT INTO verificaciones (usuario_id, tipo_cuenta, estado, creado_en,
       identidad_confirmada_en)
     VALUES (?, ?, 'pendiente', ?, ?)`,
  ).run(usuarioId, tipoCuenta, new Date().toISOString(), new Date().toISOString());
}

test('sin identidad probada no se puede conectar una cuenta de cobros', async () => {
  const usuario = crearSinVerificar('estudiante');

  const res = await pedir('GET', '/api/payments/oauth/connect', { token: usuario.token });

  assert.strictEqual(res.status, 403,
    'el OTP es lo que impide que cualquier cuenta recién creada vincule una cuenta de MP');
});

test('con la identidad probada se puede conectar aunque falte la verificación', async () => {
  const usuario = crearSinVerificar('estudiante');
  confirmarIdentidad(usuario.id, 'estudiante');

  const res = await pedir('GET', '/api/payments/oauth/connect', { token: usuario.token });

  // Si esto fuera 403, conectar exigiría estar verificado y verificarse
  // exigiría conectar: nadie saldría nunca de ahí.
  assert.strictEqual(res.status, 200, JSON.stringify(res.datos));
  assert.ok(res.datos.url, 'tiene que devolver la URL de autorización de MP');
});

test('una cuenta particular también puede conectar Mercado Pago', async () => {
  const usuario = crearSinVerificar('particular');
  confirmarIdentidad(usuario.id, 'particular');

  const res = await pedir('GET', '/api/payments/oauth/connect', { token: usuario.token });

  // 'particular' estaba fuera de la lista de tipos permitidos, lo que con la
  // regla nueva lo condenaba a no poder verificarse nunca.
  assert.strictEqual(res.status, 200, JSON.stringify(res.datos));
});

test('quien ya está verificado sigue pudiendo conectar', async () => {
  const usuario = crearUsuario({ tipoCuenta: 'negocio' });

  const res = await pedir('GET', '/api/payments/oauth/connect', { token: usuario.token });

  assert.strictEqual(res.status, 200, JSON.stringify(res.datos));
});

// ─── Guardas antes de mover dinero: horario y existencias ───────
//
// Las dos van en el servidor y no solo en la app: la hora de un teléfono la
// cambia quien lo usa, y el stock pudo agotarse entre que se pintó la
// pantalla y se tocó el botón.

function crearProductoConStock(sellerId, stock) {
  const id = `p_gu_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO products (id, title, price, priceNum, seller, category, stock_quantity)
     VALUES (?, ?, '90', 90, ?, 'otros', ?)`,
  ).run(id, `Producto ${id}`, sellerId, stock);
  return id;
}

function ordenDe(compradorId, vendedorId, productoId, cantidad = 1) {
  return store.crearOrden({
    id: `ord_gu_${crypto.randomUUID()}`,
    buyerId: compradorId, vendorId: vendedorId,
    amount: 90 * cantidad, applicationFee: 4.5, currency: 'MXN', origin: 'direct',
    paymentMethod: 'tarjeta',
    items: [{ productId: productoId, quantity: cantidad, unitPrice: 90, title: 'X' }],
  });
}

/** Deja al vendedor cerrado ahora mismo, sea cual sea la hora del test. */
function cerrarAhora(vendedorId) {
  const ayer = (new Date().getDay() + 6) % 7 === 0 ? 6 : (new Date().getDay() + 6) % 7 - 1;
  db.getDb().prepare('UPDATE sellers SET businessHours = ? WHERE id = ?')
    .run(JSON.stringify({ [String(ayer)]: { open: '09:00', close: '10:00' } }), vendedorId);
}

test('no se puede pagar a un vendedor cerrado', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  conectar(vendedor.id);
  cerrarAhora(vendedor.id);
  const orden = ordenDe(comprador.id, vendedor.id, crearProductoConStock(vendedor.id, 5));

  const res = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: orden.id, card_token: 'ct_1' },
  });

  assert.strictEqual(res.status, 409);
  assert.strictEqual(res.datos.motivo, 'fuera_de_horario');
  assert.match(res.datos.error, /cerrado/i);
  assert.ok(res.datos.abreA, 'el comprador tiene que saber cuándo volver');
  assert.strictEqual(llamadasCrearPago.length, 0, 'no se debió llamar a MP');
});

test('un vendedor sin horario configurado sí puede cobrar', () => {
  // La exigencia de tener horario vive en la verificación. Cortarle las
  // ventas aquí castigaría al comprador por un requisito de perfil ajeno.
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  const { estadoDeAtencion } = require('../validation/horarioNegocio');
  assert.strictEqual(estadoDeAtencion(vendedor.id).abierto, true);
});

test('no se puede pagar un producto que ya no tiene existencias', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  conectar(vendedor.id);
  const producto = crearProductoConStock(vendedor.id, 1);
  const orden = ordenDe(comprador.id, vendedor.id, producto, 1);

  // Alguien se llevó la última unidad mientras esta pantalla estaba abierta.
  db.getDb().prepare('UPDATE products SET stock_quantity = 0 WHERE id = ?').run(producto);

  const res = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: orden.id, card_token: 'ct_1' },
  });

  assert.strictEqual(res.status, 409);
  assert.strictEqual(res.datos.motivo, 'sin_stock');
  assert.match(res.datos.error, /ya no está disponible/i);
  assert.strictEqual(llamadasCrearPago.length, 0);
});

test('pedir más unidades de las que quedan también se corta', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  conectar(vendedor.id);
  const producto = crearProductoConStock(vendedor.id, 2);
  const orden = ordenDe(comprador.id, vendedor.id, producto, 5);

  const res = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: orden.id, card_token: 'ct_1' },
  });

  assert.strictEqual(res.status, 409);
  assert.strictEqual(res.datos.motivo, 'sin_stock');
  assert.match(res.datos.error, /quedan 2/);
});

test('un producto viejo sin stock definido no bloquea el cobro', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  conectar(vendedor.id);
  const orden = ordenDe(comprador.id, vendedor.id, crearProductoConStock(vendedor.id, null));

  const res = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: orden.id, card_token: 'ct_1' },
  });

  // No sabemos cuántos hay; rechazar el cobro castigaría al comprador por un
  // dato que solo el vendedor puede arreglar.
  assert.notStrictEqual(res.datos?.motivo, 'sin_stock');
});

test('con stock suficiente y abierto, el cobro llega a Mercado Pago', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  conectar(vendedor.id);
  const orden = ordenDe(comprador.id, vendedor.id, crearProductoConStock(vendedor.id, 9));

  // `orders.mp_payment_id` es UNIQUE en toda la tabla, y el doble por defecto
  // devuelve siempre el mismo id.
  respuestaCrearPago = async () => ({ id: `pay_ok_${contador}`, status: 'approved' });

  const res = await pedir('POST', '/api/payments/checkout', {
    token: comprador.token,
    body: { order_id: orden.id, card_token: 'ct_ok' },
  });

  assert.strictEqual(res.status, 200, JSON.stringify(res.datos));
  assert.strictEqual(llamadasCrearPago.length, 1, 'las guardas no deben estorbar al camino feliz');
});
