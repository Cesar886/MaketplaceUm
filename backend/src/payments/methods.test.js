// Catálogo de métodos de pago y disponibilidad de 'tarjeta' por vendedor.
//
// 'tarjeta' no es un método más del catálogo: solo existe de verdad si ese
// vendedor tiene una cuenta de pago conectada y viva. Estas pruebas fijan las
// dos mitades de esa regla — la que impide guardarla, y la que la reporta al
// checkout — porque si solo se respeta en la UI, el primer cliente de la API
// que la ignore deja una orden que nadie puede cobrar.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');
const crypto = require('node:crypto');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-methods-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';
process.env.MP_PUBLIC_KEY = 'TEST-public-key-plataforma';
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

const store = require('./store');
const { register } = require('./routes');
const { validatePaymentMethods } = require('../validation/sellerProfile');
const {
  tarjetaDisponible, motivoTarjetaNoDisponible, validarMetodosPermitidos,
} = require('./methods');

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

function crearUsuario({ tipoCuenta = 'estudiante', metodos = ['efectivo'] } = {}) {
  const id = `u_mt_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified,
       tipo_cuenta, paymentMethods)
     VALUES (?, ?, ?, 'TT', '', ?, 1, ?, ?)`,
  ).run(id, `Test ${id}`, `${id}@ejemplo.com`, tipoCuenta === 'negocio' ? 1 : 0, tipoCuenta,
    metodos === null ? null : JSON.stringify(metodos));
  return { id, token: generateToken(id) };
}

function conectar(sellerId, { publicKey = 'APP_USR-pubkey-del-vendedor' } = {}) {
  store.guardarCuentaVendedor(sellerId, {
    mpUserId: `mp_${sellerId}`,
    accessToken: 'vendor-access-token',
    refreshToken: 'vendor-refresh-token',
    expiresIn: 30 * 24 * 60 * 60,
    publicKey,
  });
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

// ─── El catálogo ────────────────────────────────────────────────

test('transferencia ya no es un método de pago válido', () => {
  const r = validatePaymentMethods(['transferencia'], { required: true });
  assert.ok(r.error, 'debería rechazarse: salió del catálogo');
});

test('tarjeta sí es un método del catálogo', () => {
  const r = validatePaymentMethods(['tarjeta'], { required: true });
  assert.ok(!r.error, `no debería rechazarse por catálogo: ${r.error}`);
  assert.deepStrictEqual(r.value, ['tarjeta']);
});

// ─── Disponibilidad por vendedor ────────────────────────────────

test('sin cuenta conectada, tarjeta no está disponible y hay un motivo', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  assert.strictEqual(tarjetaDisponible(vendedor.id), false);
  // Un motivo legible importa: el vendedor tiene que entender qué hacer,
  // no solo ver la opción apagada.
  assert.ok(motivoTarjetaNoDisponible(vendedor.id));
});

test('con cuenta conectada, tarjeta está disponible y sin motivo de bloqueo', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  conectar(vendedor.id);
  assert.strictEqual(tarjetaDisponible(vendedor.id), true);
  assert.strictEqual(motivoTarjetaNoDisponible(vendedor.id), null);
});

test('si el vendedor se desconecta, tarjeta deja de estar disponible', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  conectar(vendedor.id);
  store.desconectarVendedor(vendedor.id, { motivo: 'prueba', por: 'user' });
  assert.strictEqual(tarjetaDisponible(vendedor.id), false);
});

// ─── Endpoint que consume el checkout ───────────────────────────

test('el endpoint reporta tarjeta disponible con la public key DEL VENDEDOR', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  conectar(vendedor.id, { publicKey: 'APP_USR-pk-vendedor-42' });

  const res = await pedir('GET', `/api/payments/vendors/${vendedor.id}/methods`,
    { token: comprador.token });
  assert.strictEqual(res.status, 200);

  const tarjeta = res.datos.methods.find(m => m.id === 'tarjeta');
  assert.ok(tarjeta, 'tarjeta debe aparecer entre los métodos del vendedor');
  assert.strictEqual(tarjeta.available, true);

  // La tokenización tiene que hacerse con la key del VENDEDOR: un card_token
  // creado con la de la plataforma no pertenece a su cuenta y MP lo rechaza.
  assert.strictEqual(res.datos.cardPublicKey, 'APP_USR-pk-vendedor-42');
  assert.notStrictEqual(res.datos.cardPublicKey, process.env.MP_PUBLIC_KEY);
});

test('el endpoint marca tarjeta no disponible y no filtra ninguna public key', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  // Aceptó tarjeta pero nunca conectó (o se desconectó): queda como zombie.

  const res = await pedir('GET', `/api/payments/vendors/${vendedor.id}/methods`,
    { token: comprador.token });
  assert.strictEqual(res.status, 200);

  const tarjeta = res.datos.methods.find(m => m.id === 'tarjeta');
  assert.strictEqual(tarjeta.available, false);
  assert.ok(tarjeta.unavailableReason, 'el comprador debe saber por qué no puede pagar con tarjeta');
  assert.strictEqual(res.datos.cardPublicKey, null);
});

test('el endpoint solo lista lo que ese vendedor acepta', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo'] });

  const res = await pedir('GET', `/api/payments/vendors/${vendedor.id}/methods`,
    { token: comprador.token });
  assert.deepStrictEqual(res.datos.methods.map(m => m.id), ['efectivo']);
});

// ─── Enforcement al guardar el perfil ───────────────────────────

// El guard que aplican las rutas que guardan métodos (perfil, producto,
// búsqueda). Se prueba aquí directamente y no por HTTP porque esas rutas
// resuelven el vendedor contra el array en memoria de data.js, que no es lo
// que esta regla decide.

test('el guard rechaza tarjeta si el vendedor no tiene MP conectado', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });

  const r = validarMetodosPermitidos(vendedor.id, ['efectivo', 'tarjeta']);
  assert.ok(r.error, 'aceptarlo dejaría un método que no se puede cobrar y órdenes muertas');
  assert.match(r.error.toLowerCase(), /mercado pago|conecta/);
});

test('el guard deja pasar tarjeta si el vendedor está conectado', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  conectar(vendedor.id);

  assert.deepStrictEqual(validarMetodosPermitidos(vendedor.id, ['efectivo', 'tarjeta']), {});
});

test('el guard no se mete con los métodos que la app no cobra', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  // Sin cuenta conectada, pero efectivo/paypal/cripto son acuerdos entre las
  // partes que la app solo anuncia: no dependen de ninguna integración.
  assert.deepStrictEqual(
    validarMetodosPermitidos(vendedor.id, ['efectivo', 'paypal', 'cripto']), {},
  );
});

test('el guard vuelve a rechazar tarjeta tras una desconexión', () => {
  const vendedor = crearUsuario({ tipoCuenta: 'negocio' });
  conectar(vendedor.id);
  store.desconectarVendedor(vendedor.id, { motivo: 'revocado', por: 'webhook' });

  const r = validarMetodosPermitidos(vendedor.id, ['tarjeta']);
  assert.ok(r.error);
});

// ─── Método de pago al crear la orden ───────────────────────────

function crearProducto(sellerId, precio) {
  const id = `p_mt_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO products (id, title, price, priceNum, seller, category)
     VALUES (?, ?, ?, ?, ?, 'otros')`,
  ).run(id, `Producto ${id}`, `$${precio}`, precio, sellerId);
  return id;
}

test('la orden guarda el método de pago con el que se creó', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  conectar(vendedor.id);
  const producto = crearProducto(vendedor.id, 100);

  const res = await pedir('POST', '/api/orders', {
    token: comprador.token,
    body: { productId: producto, quantity: 1, paymentMethod: 'tarjeta' },
  });

  assert.strictEqual(res.status, 201, `respondió ${res.status}: ${JSON.stringify(res.datos)}`);
  assert.strictEqual(res.datos[0].paymentMethod, 'tarjeta');
  assert.strictEqual(
    store.getOrdenPorId(res.datos[0].id).payment_method, 'tarjeta',
    'sin persistirlo, nadie sabe cómo se acordó pagar esta orden',
  );
});

test('no se puede crear una orden con tarjeta si el vendedor no puede cobrarla', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo'] });
  const producto = crearProducto(vendedor.id, 100);

  // El cliente manda 'tarjeta' de todas formas: el servidor no puede fiarse
  // de que la app haya respetado lo que le dijo el endpoint de métodos.
  const res = await pedir('POST', '/api/orders', {
    token: comprador.token,
    body: { productId: producto, quantity: 1, paymentMethod: 'tarjeta' },
  });

  assert.strictEqual(res.status, 409,
    'aceptarla crearía una orden que nadie puede cobrar');
});

test('no se puede crear una orden con un método que el vendedor no acepta', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo'] });
  const producto = crearProducto(vendedor.id, 100);

  const res = await pedir('POST', '/api/orders', {
    token: comprador.token,
    body: { productId: producto, quantity: 1, paymentMethod: 'paypal' },
  });
  assert.strictEqual(res.status, 409);
});

test('una orden sin método declarado se sigue creando (compat)', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo'] });
  const producto = crearProducto(vendedor.id, 100);

  const res = await pedir('POST', '/api/orders', {
    token: comprador.token,
    body: { productId: producto, quantity: 1 },
  });
  assert.strictEqual(res.status, 201);
  assert.strictEqual(store.getOrdenPorId(res.datos[0].id).payment_method, null);
});

// ─── Coherencia de la clave pública ─────────────────────────────

test('sin public key guardada, tarjeta no se reporta como disponible', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['tarjeta'] });
  // Cuenta conectada pero SIN public key: pasa si la respuesta de OAuth no
  // la trajo. Sin ella el cliente no puede tokenizar nada.
  conectar(vendedor.id, { publicKey: null });

  const res = await pedir('GET', `/api/payments/vendors/${vendedor.id}/methods`,
    { token: comprador.token });

  const tarjeta = res.datos.methods.find(m => m.id === 'tarjeta');
  assert.strictEqual(tarjeta.available, false,
    'decir que acepta tarjeta sin clave para tokenizar deja al comprador en un callejón');
  assert.ok(tarjeta.unavailableReason);
  assert.strictEqual(res.datos.cardPublicKey, null);
});

// ─── Cobrar sin haber marcado "tarjeta" en el perfil ────────────
//
// Conectar la cuenta de Mercado Pago y marcar 'tarjeta' en el perfil son dos
// acciones distintas, y la gente hace la primera sin la segunda. El checkout
// solo exige la cuenta conectada y el token vivo (nunca mira la lista
// declarada), así que la UI no puede ser más estricta que él: esconder el
// pago a un vendedor que SÍ puede cobrar es negarle ventas por un checkbox.

test('un vendedor conectado puede cobrar aunque no haya marcado tarjeta', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo'] });
  conectar(vendedor.id, { publicKey: 'APP_USR-pk-sin-declarar' });

  const res = await pedir('GET', `/api/payments/vendors/${vendedor.id}/methods`,
    { token: comprador.token });
  assert.strictEqual(res.status, 200);

  assert.strictEqual(res.datos.cardEnabled, true,
    'su cuenta está viva: el cobro con tarjeta funcionaría hoy mismo');
  assert.strictEqual(res.datos.cardPublicKey, 'APP_USR-pk-sin-declarar',
    'sin la key del vendedor el cliente no puede tokenizar');

  // Pero la lista declarada NO se toca: es lo que el vendedor anuncia, y de
  // ella depende el guardado de órdenes con método explícito.
  assert.strictEqual(res.datos.methods.find(m => m.id === 'tarjeta'), undefined);
  assert.deepStrictEqual(res.datos.methods.map(m => m.id), ['efectivo']);
});

test('un vendedor sin cuenta conectada no puede cobrar con tarjeta', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo'] });

  const res = await pedir('GET', `/api/payments/vendors/${vendedor.id}/methods`,
    { token: comprador.token });

  assert.strictEqual(res.datos.cardEnabled, false);
  assert.strictEqual(res.datos.cardPublicKey, null);
});

test('desconectarse apaga cardEnabled aunque tarjeta siga declarada', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario({ tipoCuenta: 'negocio', metodos: ['efectivo', 'tarjeta'] });
  conectar(vendedor.id);
  store.desconectarVendedor(vendedor.id, { motivo: 'prueba', por: 'user' });

  const res = await pedir('GET', `/api/payments/vendors/${vendedor.id}/methods`,
    { token: comprador.token });

  assert.strictEqual(res.datos.cardEnabled, false);
  assert.strictEqual(res.datos.cardPublicKey, null);
});
