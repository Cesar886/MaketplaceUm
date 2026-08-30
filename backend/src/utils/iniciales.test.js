const test = require('node:test');
const assert = require('node:assert');
const { calcularIniciales } = require('./iniciales');

test('un nombre y un apellido dan una inicial de cada uno', () => {
  assert.equal(calcularIniciales('Daniel Perez'), 'DP');
});

test('una sola palabra da sus dos primeras letras', () => {
  assert.equal(calcularIniciales('SanksUm'), 'SA');
});

test('se toman solo las dos primeras iniciales de un nombre largo', () => {
  assert.equal(calcularIniciales('Ana Maria Lopez Garcia'), 'AM');
});

test('los espacios de sobra no producen iniciales vacías', () => {
  assert.equal(calcularIniciales('  Ana   Lopez  '), 'AL');
});

test('sin nombre se devuelve el marcador, nunca una cadena vacía', () => {
  assert.equal(calcularIniciales(''), '??');
  assert.equal(calcularIniciales(null), '??');
  assert.equal(calcularIniciales(undefined), '??');
});
