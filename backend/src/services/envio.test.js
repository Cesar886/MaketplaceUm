const test = require('node:test');
const assert = require('node:assert');

const { resolverModoEnvio } = require('./envio');

test('usa el proveedor real cuando está configurado', () => {
  assert.deepStrictEqual(
    resolverModoEnvio({ configurado: true, produccion: true }),
    { modo: 'proveedor' },
  );
  assert.deepStrictEqual(
    resolverModoEnvio({ configurado: true, produccion: false }),
    { modo: 'proveedor' },
  );
});

test('cae a modo dev cuando no hay proveedor y no es producción', () => {
  assert.deepStrictEqual(
    resolverModoEnvio({ configurado: false, produccion: false }),
    { modo: 'dev' },
  );
});

test('no envía ni finge en producción sin proveedor configurado', () => {
  // Fingir un envío en producción dejaría al usuario esperando un código que
  // nunca llega, sin señal de error en el servidor.
  assert.deepStrictEqual(
    resolverModoEnvio({ configurado: false, produccion: true }),
    { modo: 'no_disponible' },
  );
});
