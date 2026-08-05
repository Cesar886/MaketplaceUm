const test = require('node:test');
const assert = require('node:assert');

const {
  generarCodigo,
  hashCodigo,
  verificarCodigo,
  calcularExpiracion,
  VIGENCIA_MINUTOS,
} = require('./otp');

// ─── generarCodigo ───────────────────────────────────────────

test('genera un código de exactamente 6 dígitos', () => {
  for (let i = 0; i < 200; i++) {
    assert.match(generarCodigo(), /^\d{6}$/);
  }
});

test('genera códigos distintos entre llamadas', () => {
  const codigos = new Set();
  for (let i = 0; i < 50; i++) codigos.add(generarCodigo());
  // 50 códigos iguales de 10^6 posibilidades sería un generador roto.
  assert.ok(codigos.size > 40, `solo se generaron ${codigos.size} códigos distintos`);
});

// ─── hashCodigo ──────────────────────────────────────────────

test('produce el mismo hash para el mismo código', () => {
  assert.strictEqual(hashCodigo('123456'), hashCodigo('123456'));
});

test('produce hashes distintos para códigos distintos', () => {
  assert.notStrictEqual(hashCodigo('123456'), hashCodigo('123457'));
});

test('el hash no contiene el código en claro', () => {
  assert.ok(!hashCodigo('123456').includes('123456'));
});

// ─── calcularExpiracion ──────────────────────────────────────

test('la expiración cae 10 minutos en el futuro', () => {
  const antes = Date.now();
  const expira = new Date(calcularExpiracion()).getTime();
  const esperado = antes + VIGENCIA_MINUTOS * 60 * 1000;
  assert.ok(Math.abs(expira - esperado) < 2000, 'la expiración no cae a los 10 minutos');
  assert.strictEqual(VIGENCIA_MINUTOS, 10);
});

// ─── verificarCodigo ─────────────────────────────────────────

const dentroDeVigencia = () => new Date(Date.now() + 5 * 60 * 1000).toISOString();
const yaExpirado = () => new Date(Date.now() - 60 * 1000).toISOString();

test('acepta el código correcto dentro de la vigencia', () => {
  const resultado = verificarCodigo('123456', hashCodigo('123456'), dentroDeVigencia());
  assert.deepStrictEqual(resultado, { ok: true, razon: null });
});

test('rechaza un código incorrecto', () => {
  const resultado = verificarCodigo('999999', hashCodigo('123456'), dentroDeVigencia());
  assert.deepStrictEqual(resultado, { ok: false, razon: 'incorrecto' });
});

test('rechaza el código correcto si ya expiró', () => {
  const resultado = verificarCodigo('123456', hashCodigo('123456'), yaExpirado());
  assert.deepStrictEqual(resultado, { ok: false, razon: 'expirado' });
});

test('rechaza cuando no hay código pendiente guardado', () => {
  assert.deepStrictEqual(
    verificarCodigo('123456', null, dentroDeVigencia()),
    { ok: false, razon: 'sin_codigo' },
  );
  assert.deepStrictEqual(
    verificarCodigo('123456', hashCodigo('123456'), null),
    { ok: false, razon: 'sin_codigo' },
  );
});

test('rechaza un código de longitud distinta sin lanzar excepción', () => {
  // timingSafeEqual lanza si los buffers difieren en longitud: el hash de
  // cualquier entrada mide lo mismo, pero la entrada del usuario no.
  const resultado = verificarCodigo('12', hashCodigo('123456'), dentroDeVigencia());
  assert.deepStrictEqual(resultado, { ok: false, razon: 'incorrecto' });
});

test('rechaza una entrada que no es string sin lanzar excepción', () => {
  assert.deepStrictEqual(
    verificarCodigo(undefined, hashCodigo('123456'), dentroDeVigencia()),
    { ok: false, razon: 'incorrecto' },
  );
});
