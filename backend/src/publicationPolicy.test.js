const test = require('node:test');
const assert = require('node:assert/strict');
const { getPublicationPolicy, isExpired } = require('./publicationPolicy');

test('asigna los cinco niveles de publicación', async () => {
  assert.deepEqual((await getPublicationPolicy({ tipoCuenta: 'negocio', verified: true })).productsActive, 40);
  assert.equal((await getPublicationPolicy({ tipoCuenta: 'estudiante', verified: true })).productsDaily, 6);
  assert.equal((await getPublicationPolicy({ tipoCuenta: 'negocio', verified: false })).durationDays, 20);
  assert.equal((await getPublicationPolicy({ tipoCuenta: 'estudiante', verified: false })).wantedActive, 5);
  assert.equal((await getPublicationPolicy({ tipoCuenta: 'particular', verified: true })).wantedDaily, 1);
});

test('una fecha inválida se considera vencida y una publicación legacy no', () => {
  assert.equal(isExpired({ expiresAt: 'fecha-corrupta' }), true);
  assert.equal(isExpired({ expiresAt: null }), false);
});

test('empleado UM comparte política con estudiante UM', async () => {
  const policy = await getPublicationPolicy({
    tipoCuenta: 'estudiante',
    tipoVerificacion: 'empleado',
    verified: true,
  });
  assert.equal(policy.productsActive, 30);
  assert.equal(policy.durationDays, 60);
});
