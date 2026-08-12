const test = require('node:test');
const assert = require('node:assert');
const { validateSocialUrl, validateWhatsappNumber } = require('./sellerProfile');

test('acepta una URL https del dominio correcto', () => {
  assert.deepStrictEqual(
    validateSocialUrl('facebook', 'https://facebook.com/minegocio'),
    { value: 'https://facebook.com/minegocio' },
  );
  assert.deepStrictEqual(
    validateSocialUrl('instagram', 'https://www.instagram.com/minegocio'),
    { value: 'https://www.instagram.com/minegocio' },
  );
  assert.deepStrictEqual(
    validateSocialUrl('twitter', 'https://x.com/minegocio'),
    { value: 'https://x.com/minegocio' },
  );
});

test('rechaza una URL de otra plataforma pegada en el campo equivocado', () => {
  const result = validateSocialUrl('instagram', 'https://facebook.com/minegocio');
  assert.ok(result.error);
  assert.match(result.error, /Instagram/);
});

test('rechaza un hostname que solo contiene el dominio como substring (bypass)', () => {
  const result = validateSocialUrl('facebook', 'https://facebook.com.evil.example/phish');
  assert.ok(result.error);
});

test('rechaza http (no https)', () => {
  const result = validateSocialUrl('tiktok', 'http://tiktok.com/@minegocio');
  assert.ok(result.error);
});

test('rechaza un valor que no es una URL', () => {
  const result = validateSocialUrl('twitter', 'no es un link');
  assert.ok(result.error);
});

test('vacío limpia el campo (value: null), no es error', () => {
  assert.deepStrictEqual(validateSocialUrl('facebook', ''), { value: null });
  assert.deepStrictEqual(validateSocialUrl('facebook', undefined), { value: null });
  assert.deepStrictEqual(validateSocialUrl('facebook', null), { value: null });
});

test('rechaza una URL más larga de 200 caracteres', () => {
  const largo = 'https://facebook.com/' + 'a'.repeat(200);
  const result = validateSocialUrl('facebook', largo);
  assert.ok(result.error);
});

test('WhatsApp: acepta solo dígitos con código de país', () => {
  assert.deepStrictEqual(validateWhatsappNumber('5215512345678'), { value: '5215512345678' });
});

test('WhatsApp: rechaza el signo + y espacios', () => {
  assert.ok(validateWhatsappNumber('+52 155 1234 5678').error);
});

test('WhatsApp: rechaza una URL wa.me completa', () => {
  assert.ok(validateWhatsappNumber('https://wa.me/5215512345678').error);
});

test('WhatsApp: rechaza menos de 10 dígitos', () => {
  assert.ok(validateWhatsappNumber('123').error);
});

test('WhatsApp: vacío limpia el campo', () => {
  assert.deepStrictEqual(validateWhatsappNumber(''), { value: null });
});
