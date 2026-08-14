// Cuándo se puede cobrar comisión de plataforma, y cuándo no.
//
// Nace del error 2059 de Mercado Pago: "You cannot use application_fee with
// this payment". No es un rechazo de tarjeta — es MP tumbando el cobro
// ENTERO porque la comisión no aplica, casi siempre porque el vendedor
// conectado es la misma cuenta que es dueña de la aplicación.
//
// Lo que estas pruebas protegen, y por qué importa el orden:
//
//  1. Que la comisión se OMITA cuando de verdad no puede cobrarse. Si no,
//     no hay cobro posible con esa cuenta.
//  2. Que NO se omita en ningún otro caso. Este es el lado caro: omitirla
//     de más no da ningún error, el cobro funciona, y la plataforma deja de
//     ganar dinero en silencio hasta que alguien cuadre las cuentas.
//
// Ninguna prueba de este archivo toca la API real de Mercado Pago.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-comision-')),
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

const mpClient = require('./mpClient');

// La plataforma es la cuenta 999. `validarTokenVendedor` es el GET /users/me
// que usa comision.js para averiguarlo.
let identidadDeLaPlataforma;
mpClient.validarTokenVendedor = async () => {
  if (typeof identidadDeLaPlataforma === 'function') return identidadDeLaPlataforma();
  return identidadDeLaPlataforma;
};

const { comisionCobrable, esRechazoDeComision, _resetCache } = require('./comision');

test.beforeEach(() => {
  _resetCache();
  identidadDeLaPlataforma = { id: 999 };
  delete process.env.PLATFORM_FEE_ENABLED;
});

// ─── Se omite cuando de verdad no aplica ────────────────────────

test('el vendedor que ES la cuenta de la aplicación cobra sin comisión', async () => {
  // Es el escenario del 2059: quien crea la app en el panel de MP conecta su
  // propia cuenta como primer vendedor porque es la que tiene a mano.
  assert.strictEqual(await comisionCobrable(10, '999'), 0);
});

test('da igual que el id venga como número o como texto', async () => {
  // El OAuth devuelve user_id numérico y la BD lo guarda como texto. Un
  // `===` sin normalizar dejaría pasar la comisión y el cobro fallaría.
  identidadDeLaPlataforma = { id: 999 };
  assert.strictEqual(await comisionCobrable(10, 999), 0);
});

test('PLATFORM_FEE_ENABLED=false apaga la comisión', async () => {
  process.env.PLATFORM_FEE_ENABLED = 'false';
  assert.strictEqual(await comisionCobrable(10, '123'), 0);
});

// ─── NO se omite en ningún otro caso ────────────────────────────

test('un vendedor distinto de la plataforma sí paga comisión', async () => {
  assert.strictEqual(await comisionCobrable(10, '123'), 10);
});

test('si no se puede identificar a la plataforma, la comisión SE MANDA', async () => {
  // Ante la duda se manda: el cobro falla con un error ruidoso que alguien
  // arregla hoy. Omitirla haría que el cobro funcione y la plataforma no
  // gane nada, sin ningún error, durante semanas.
  identidadDeLaPlataforma = () => { throw new Error('MP no responde'); };
  assert.strictEqual(await comisionCobrable(10, '123'), 10);
});

test('sin id de vendedor la comisión SE MANDA', async () => {
  assert.strictEqual(await comisionCobrable(10, null), 10);
});

test('solo el literal "false" apaga la comisión', async () => {
  // Un interruptor de dinero tiene que fallar hacia cobrar: un typo no
  // puede dejar a la plataforma trabajando gratis sin dar ningún error.
  for (const valor of ['', 'no', 'FALSO', '0', 'true', 'sí']) {
    process.env.PLATFORM_FEE_ENABLED = valor;
    assert.strictEqual(
      await comisionCobrable(10, '123'), 10,
      `PLATFORM_FEE_ENABLED='${valor}' no debería apagar la comisión`,
    );
  }
});

test('"FALSE" en mayúsculas sí apaga: es la misma intención escrita distinto', async () => {
  process.env.PLATFORM_FEE_ENABLED = 'FALSE';
  assert.strictEqual(await comisionCobrable(10, '123'), 0);
});

test('una comisión de 0 o negativa se queda en 0 sin preguntar a MP', async () => {
  let consultas = 0;
  identidadDeLaPlataforma = () => { consultas++; return { id: 999 }; };
  assert.strictEqual(await comisionCobrable(0, '123'), 0);
  assert.strictEqual(await comisionCobrable(-5, '123'), 0);
  assert.strictEqual(consultas, 0, 'no hay nada que decidir: no se sale a la red');
});

// ─── La caché ───────────────────────────────────────────────────

test('la identidad de la plataforma se consulta una sola vez', async () => {
  // Sin caché, cada cobro arrastraría una llamada extra a MP: su latencia en
  // el camino crítico del pago, y su caída como causa de fallos.
  let consultas = 0;
  identidadDeLaPlataforma = () => { consultas++; return { id: 999 }; };

  await comisionCobrable(10, '123');
  await comisionCobrable(10, '456');
  await comisionCobrable(10, '789');

  assert.strictEqual(consultas, 1);
});

test('un fallo al identificar la plataforma no se reintenta en cada cobro', async () => {
  let consultas = 0;
  identidadDeLaPlataforma = () => { consultas++; throw new Error('MP caído'); };

  await comisionCobrable(10, '123');
  await comisionCobrable(10, '123');

  assert.strictEqual(consultas, 1, 'reintentar añadiría un timeout a cada pago');
});

// ─── Reconocer el 2059 cuando llega ─────────────────────────────

test('se reconoce el 2059 dentro del error de Mercado Pago', () => {
  const err = new mpClient.MpError('Mercado Pago respondió 400', {
    status: 400,
    detalle: {
      message: 'You cannot use application_fee with this payment.',
      error: 'bad_request',
      cause: [{ code: 2059, description: 'You cannot use application_fee with this payment.' }],
    },
  });
  assert.strictEqual(esRechazoDeComision(err), true);
});

test('el código llega a veces como texto y también cuenta', () => {
  const err = new mpClient.MpError('400', {
    detalle: { cause: [{ code: '2059' }] },
  });
  assert.strictEqual(esRechazoDeComision(err), true);
});

test('un rechazo de tarjeta normal NO se confunde con el 2059', () => {
  // Si se confundieran, un rechazo legítimo dejaría de decirle a quien
  // compra que pruebe otra tarjeta, que es justo lo que tiene que hacer.
  const err = new mpClient.MpError('400', {
    detalle: { cause: [{ code: 3034, description: 'Invalid card number' }] },
  });
  assert.strictEqual(esRechazoDeComision(err), false);
});

test('un error sin causas no revienta ni se confunde', () => {
  assert.strictEqual(esRechazoDeComision(new mpClient.MpError('502')), false);
  assert.strictEqual(esRechazoDeComision(new Error('cualquier cosa')), false);
  assert.strictEqual(esRechazoDeComision(null), false);
  assert.strictEqual(esRechazoDeComision({ detalle: { cause: 'no es lista' } }), false);
});
