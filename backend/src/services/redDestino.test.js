const test = require('node:test');
const assert = require('node:assert');

const { esIpPrivada, esDestinoPermitido } = require('./redDestino');

// ─── esIpPrivada ─────────────────────────────────────────────

test('reconoce loopback IPv4 como privada', () => {
  assert.strictEqual(esIpPrivada('127.0.0.1'), true);
  assert.strictEqual(esIpPrivada('127.53.1.9'), true);
});

test('reconoce los rangos RFC1918 como privados', () => {
  assert.strictEqual(esIpPrivada('10.0.0.1'), true);
  assert.strictEqual(esIpPrivada('172.16.0.1'), true);
  assert.strictEqual(esIpPrivada('172.31.255.255'), true);
  assert.strictEqual(esIpPrivada('192.168.1.1'), true);
});

test('reconoce link-local como privada (metadata de la nube)', () => {
  // 169.254.169.254 es el endpoint de metadata de AWS/GCP/Azure: el destino
  // clásico de un SSRF.
  assert.strictEqual(esIpPrivada('169.254.169.254'), true);
});

test('reconoce CGNAT, 0.0.0.0/8 y multicast como no públicas', () => {
  assert.strictEqual(esIpPrivada('100.64.0.1'), true);
  assert.strictEqual(esIpPrivada('0.0.0.0'), true);
  assert.strictEqual(esIpPrivada('224.0.0.1'), true);
});

test('no confunde direcciones públicas vecinas de los rangos privados', () => {
  assert.strictEqual(esIpPrivada('172.15.0.1'), false);
  assert.strictEqual(esIpPrivada('172.32.0.1'), false);
  assert.strictEqual(esIpPrivada('11.0.0.1'), false);
  assert.strictEqual(esIpPrivada('192.167.1.1'), false);
  assert.strictEqual(esIpPrivada('8.8.8.8'), false);
});

test('reconoce loopback y ULA IPv6 como privadas', () => {
  assert.strictEqual(esIpPrivada('::1'), true);
  assert.strictEqual(esIpPrivada('::'), true);
  assert.strictEqual(esIpPrivada('fc00::1'), true);
  assert.strictEqual(esIpPrivada('fd12:3456::1'), true);
  assert.strictEqual(esIpPrivada('fe80::1'), true);
});

test('detecta una IPv4 privada disfrazada de IPv6 mapeada', () => {
  // ::ffff:127.0.0.1 es loopback escrito como IPv6: sin desenvolverlo, un
  // chequeo ingenuo lo dejaría pasar.
  assert.strictEqual(esIpPrivada('::ffff:127.0.0.1'), true);
  assert.strictEqual(esIpPrivada('::ffff:169.254.169.254'), true);
});

test('trata una IPv6 pública como pública', () => {
  assert.strictEqual(esIpPrivada('2001:4860:4860::8888'), false);
});

// ─── esDestinoPermitido ──────────────────────────────────────

test('rechaza un hostname que resuelve a loopback', async () => {
  assert.strictEqual(await esDestinoPermitido('localhost'), false);
});

test('rechaza una IP privada escrita directamente como host', async () => {
  assert.strictEqual(await esDestinoPermitido('127.0.0.1'), false);
  assert.strictEqual(await esDestinoPermitido('169.254.169.254'), false);
});

test('rechaza un host que no resuelve', async () => {
  assert.strictEqual(
    await esDestinoPermitido('no-existe-mercadito-um-98765.invalid'),
    false,
  );
});
