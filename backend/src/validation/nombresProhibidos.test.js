// Tests de la lista negra de nombres de perfil.
//
// Hay dos riesgos y los dos importan: dejar pasar un "S0p0rte Ofici4l" que
// se hace pasar por la cuenta oficial de reportes, y bloquear a alguien que
// de verdad se llama "Concepción" o vende "artículos de cocina". La mitad
// de este archivo son casos legítimos que NO deben bloquearse.

const test = require('node:test');
const assert = require('node:assert');

const { revisarNombre, validarNombreProhibido } = require('./nombresProhibidos');
const { validateName } = require('./sellerProfile');

function motivo(nombre) {
  const r = revisarNombre(nombre);
  return r && r.motivo;
}

test('bloquea nombres de administración y staff', () => {
  for (const nombre of [
    'Admin', 'admin', 'ADMINISTRADOR', 'El Administrador', 'sysadmin',
    'Moderador MercaditoUM', 'Staff', 'root', 'Super Usuario', 'Webmaster',
  ]) {
    assert.strictEqual(motivo(nombre), 'suplantacion', `debería bloquear: ${nombre}`);
  }
});

test('bloquea nombres de soporte, reportes y denuncias', () => {
  for (const nombre of [
    'Soporte', 'Soporte Técnico MercaditoUM', 'Centro de Ayuda',
    'Reportes', 'Cuenta de Reportes', 'Reportes Oficiales',
    'Denuncias UM', 'Atención al Cliente', 'Trust and Safety',
    'Seguridad MercaditoUM', 'Anti Fraude',
  ]) {
    assert.strictEqual(motivo(nombre), 'suplantacion', `debería bloquear: ${nombre}`);
  }
});

test('bloquea sellos de autoridad y cuentas de sistema', () => {
  for (const nombre of [
    'Cuenta Oficial', 'Perfil Verificado', 'MercaditoUM', 'Mercadito UM',
    'no-reply', 'Notificaciones', 'Alertas Oficiales', 'Mercado Pago',
    'Facturación', 'Verificación de cuenta',
  ]) {
    assert.strictEqual(motivo(nombre), 'suplantacion', `debería bloquear: ${nombre}`);
  }
});

test('bloquea las palabras cortas solo cuando van sueltas', () => {
  assert.strictEqual(motivo('Bot'), 'suplantacion');
  assert.strictEqual(motivo('Mod'), 'suplantacion');
  assert.strictEqual(motivo('Info'), 'suplantacion');
  // …pero no dentro de una palabra normal.
  assert.strictEqual(motivo('Botines Rossi'), null);
  assert.strictEqual(motivo('Modesto Ayala'), null);
  assert.strictEqual(motivo('Ayudante de cocina'), null);
});

test('bloquea insultos y contenido sexual explícito', () => {
  for (const nombre of [
    'hijo de puta', 'Hijueputa', 'El Puto Amo', 'pendejo', 'Mierda',
    'Gilipollas', 'La Zorra', 'motherfucker', 'Bitch', 'Nigga',
    'porno gratis', 'OnlyFans', 'Pedófilo', 'Hitler', 'Nazi',
  ]) {
    assert.strictEqual(motivo(nombre), 'ofensivo', `debería bloquear: ${nombre}`);
  }
});

test('bloquea insultos cortos solo como palabra suelta', () => {
  assert.strictEqual(motivo('Puta'), 'ofensivo');
  assert.strictEqual(motivo('Ana Puta'), 'ofensivo');
  assert.strictEqual(motivo('Culo'), 'ofensivo');
  assert.strictEqual(motivo('Tetas'), 'ofensivo');
});

test('atraviesa los disfraces habituales', () => {
  for (const nombre of [
    '4dm1n', 'A d m i n', 'a.d.m.i.n', 'A_D_M_I_N', 'aaadmiiin',
    'S0p0rte', 'R3port3s', 'Ofici4l', '@dmin', 'ＡＤＭＩＮ',
    'аdmin', // "а" cirílica
    'ad​min', // zero-width space en medio
    'p3nd3j0', 'H1J0 D3 PUT4', 'Sopörté',
  ]) {
    assert.ok(revisarNombre(nombre), `debería bloquear: ${nombre}`);
  }
});

test('bloquea "concha" suelta aunque en España sea un nombre', () => {
  // En el español rioplatense/mexicano es vulgar, y el marketplace es de
  // aquí: se prefiere el falso positivo (que elija "Conchi" o su apellido).
  assert.strictEqual(motivo('Concha'), 'ofensivo');
  assert.strictEqual(motivo('Conchita Vera'), null);
});

test('exige al menos una letra', () => {
  assert.strictEqual(motivo('12345'), 'sin_letras');
  assert.strictEqual(motivo('***'), 'sin_letras');
  assert.strictEqual(motivo('🔥🔥🔥'), 'sin_letras');
});

test('NO bloquea nombres y negocios legítimos', () => {
  for (const nombre of [
    'Ana María Gómez', 'José Pérez', 'Concepción Vera',
    'Penélope Cruz', 'Mario Marín', 'Mariana Ríos', 'Pedro Núñez',
    'Cálculo Fácil', 'Artículos de Cocina', 'Camisetas La Paz',
    'Computadoras del Este', 'Vehículos Ramírez', 'Películas Retro',
    'Pollería Doña Rosa', 'Panadería El Trigal', 'Mundo Analítico',
    'Escoger Bien', 'Analista Contable', 'Sexto Sentido',
    'Diseños Zorrilla', 'Repuestos Vergara', 'Skills Academy',
    'Dietética Natural', 'Vacuna Vet', 'Perrera Feliz',
    'Isis Ramírez', 'Street Wear Py', 'Pajarería El Nido', 'Pájaro Azul',
  ]) {
    assert.strictEqual(motivo(nombre), null, `NO debería bloquear: ${nombre}`);
  }
});

test('validarNombreProhibido devuelve mensaje o null', () => {
  assert.strictEqual(validarNombreProhibido('Ana Gómez'), null);
  assert.match(validarNombreProhibido('Soporte Oficial'), /oficial/i);
  assert.match(validarNombreProhibido('pendejo'), /ofensivo/i);
});

test('validateName aplica la lista negra junto al resto de reglas', () => {
  assert.strictEqual(validateName('Ana Gómez'), null);
  assert.ok(validateName('Admin'));
  assert.ok(validateName('hijo de puta'));
  // Las reglas viejas siguen intactas.
  assert.ok(validateName('A'));
  assert.ok(validateName('x'.repeat(61)));
  assert.ok(validateName(undefined));
});
