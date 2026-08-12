// Tests del color de acento del perfil.
//
// Lo que se protege aquí es que el campo sea una lista CERRADA de ids y no un
// hex libre. Cada id se resuelve en el cliente a cuatro colores coordinados
// (relleno, foreground y la variante de línea de cada tema) verificados a
// contraste AA. Un hex arbitrario mandado por el cliente se saltaría esa
// verificación y podría dejar el botón del perfil con texto ilegible.

const test = require('node:test');
const assert = require('node:assert');

const {
  validateColorAcento,
  VALID_ACCENT_IDS,
} = require('./sellerProfile');

test('acepta los 8 ids de la paleta', () => {
  assert.strictEqual(VALID_ACCENT_IDS.length, 8);
  for (const id of VALID_ACCENT_IDS) {
    assert.strictEqual(validateColorAcento(id), null, `rechazó ${id}`);
  }
});

test('la paleta son 6 pasteles más 2 sobrios', () => {
  // El orden importa: es el que ve la persona en el selector.
  assert.deepStrictEqual(VALID_ACCENT_IDS, [
    'azul_niebla',
    'salvia',
    'durazno',
    'lavanda',
    'rosa_polvo',
    'celeste',
    'navy',
    'wine',
  ]);
});

test('null y undefined son válidos: vuelven al color de marca', () => {
  assert.strictEqual(validateColorAcento(null), null);
  assert.strictEqual(validateColorAcento(undefined), null);
});

test('rechaza un hex aunque sea un color válido', () => {
  // El caso que motiva la lista cerrada: un hex se ve razonable pero no trae
  // con qué pintar el texto encima.
  assert.ok(validateColorAcento('#C7D8EE'));
  assert.ok(validateColorAcento('C7D8EE'));
});

test('rechaza un id inventado o de otro tipo', () => {
  assert.ok(validateColorAcento('turquesa'));
  assert.ok(validateColorAcento(''));
  assert.ok(validateColorAcento(42));
  assert.ok(validateColorAcento({ id: 'salvia' }));
  assert.ok(validateColorAcento(['salvia']));
});
