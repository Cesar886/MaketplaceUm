const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { corsOrigin, securityHeaders, authIdentity, configureProxy } = require('./security');

test('CORS permite clientes sin Origin y solo origenes web configurados', () => {
  process.env.ALLOWED_ORIGINS = 'https://mercadito.example, https://admin.example/path';
  corsOrigin(undefined, (error, allowed) => { assert.ifError(error); assert.equal(allowed, true); });
  corsOrigin('https://admin.example', (error, allowed) => { assert.ifError(error); assert.equal(allowed, true); });
  corsOrigin('https://evil.example', error => assert.equal(error.status, 403));
});

test('las cabeceras defensivas se aplican y Express no se identifica', () => {
  const values = {};
  const res = { set(headers) { Object.assign(values, headers); }, removeHeader(name) { values[name] = undefined; } };
  let nextCalled = false;
  securityHeaders({}, res, () => { nextCalled = true; });
  assert.equal(values['X-Content-Type-Options'], 'nosniff');
  assert.equal(values['X-Frame-Options'], 'DENY');
  assert.match(values['Content-Security-Policy'], /frame-ancestors 'none'/);
  assert.equal(nextCalled, true);
});

test('TRUST_PROXY rechaza configuraciones ambiguas o excesivas', () => {
  const app = express();
  process.env.TRUST_PROXY = 'todos';
  assert.throws(() => configureProxy(app), /numero entre 1 y 10/);
  process.env.TRUST_PROXY = '1';
  configureProxy(app);
  assert.equal(app.get('trust proxy'), 1);
  delete process.env.TRUST_PROXY;
});

test('el limite de acceso identifica cuenta e instalacion, no la red', () => {
  const first = authIdentity({ body: { email: 'Alumno@UM.EDU.MX', deviceId: 'app-uno' }, ip: '10.0.0.1' });
  const same = authIdentity({ body: { email: ' alumno@um.edu.mx ', deviceId: 'app-uno' }, ip: '10.0.0.99' });
  const anotherApp = authIdentity({ body: { email: 'alumno@um.edu.mx', deviceId: 'app-dos' }, ip: '10.0.0.1' });
  assert.equal(first.account, same.account);
  assert.equal(first.installation, same.installation);
  assert.equal(first.account, anotherApp.account);
  assert.notEqual(first.installation, anotherApp.installation);
  assert.ok(!first.account.includes('alumno'));
});
