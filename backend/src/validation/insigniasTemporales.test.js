const test = require('node:test');
const assert = require('node:assert/strict');

const {
  estaEnPrimeraSemana,
  validateInsigniasOcultas,
  aplicarInsigniasOcultas,
} = require('./insignias');

const ahora = Date.parse('2026-09-11T12:00:00Z');

test('la insignia temporal vive desde el otorgamiento hasta antes de siete dias', () => {
  assert.equal(estaEnPrimeraSemana('2026-09-11 12:00:00', ahora), true);
  assert.equal(estaEnPrimeraSemana('2026-09-04T12:00:00.001Z', ahora), true);
  assert.equal(estaEnPrimeraSemana('2026-09-04T12:00:00.000Z', ahora), false);
});

test('no activa la insignia con fechas ausentes, invalidas o futuras', () => {
  assert.equal(estaEnPrimeraSemana(null, ahora), false);
  assert.equal(estaEnPrimeraSemana('fecha-invalida', ahora), false);
  assert.equal(estaEnPrimeraSemana('2026-09-11T12:00:00.001Z', ahora), false);
});

test('las dos insignias temporales se pueden ocultar como las demas', () => {
  const ocultas = ['recien_llegado', 'recien_verificado'];
  assert.deepEqual(validateInsigniasOcultas(ocultas), { value: ocultas });
  assert.deepEqual(
    aplicarInsigniasOcultas(
      { recienRegistrado: true, recienVerificado: true },
      ocultas,
    ),
    { recienRegistrado: false, recienVerificado: false },
  );
});
