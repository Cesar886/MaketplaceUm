// Validación de configuración de Mercado Pago: qué variables son
// obligatorias antes de considerar el módulo de pagos "listo".

const test = require('node:test');
const assert = require('node:assert');

function conEnv(vars, fn) {
  const previos = {};
  for (const k of Object.keys(vars)) previos[k] = process.env[k];
  Object.assign(process.env, vars);
  delete require.cache[require.resolve('./config')];
  try {
    return fn(require('./config'));
  } finally {
    for (const k of Object.keys(vars)) {
      if (previos[k] === undefined) delete process.env[k];
      else process.env[k] = previos[k];
    }
    delete require.cache[require.resolve('./config')];
  }
}

const BASE = {
  MP_PUBLIC_KEY: 'TEST-public-key',
  MP_ACCESS_TOKEN: 'TEST-access-token',
  MP_CLIENT_ID: 'TEST-client-id',
  MP_CLIENT_SECRET: 'TEST-client-secret',
  PAYMENTS_ENCRYPTION_KEY: 'a'.repeat(64),
  APP_PUBLIC_URL: 'https://ejemplo.test',
  PLATFORM_FEE_PERCENT: '5',
};

test('estaConfigurado() es false si falta MP_WEBHOOK_SECRET, aunque el resto esté completo', () => {
  conEnv({ ...BASE, MP_WEBHOOK_SECRET: '' }, ({ estaConfigurado, faltantes }) => {
    assert.strictEqual(estaConfigurado(), false);
    assert.ok(faltantes().includes('MP_WEBHOOK_SECRET'));
  });
});

test('estaConfigurado() es true cuando MP_WEBHOOK_SECRET también está presente', () => {
  conEnv({ ...BASE, MP_WEBHOOK_SECRET: 'shh' }, ({ estaConfigurado, faltantes }) => {
    assert.strictEqual(estaConfigurado(), true);
    assert.deepStrictEqual(faltantes(), []);
  });
});
