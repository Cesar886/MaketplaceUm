/**
 * Iniciales para el avatar por defecto de una cuenta.
 *
 * "Daniel Perez" → "DP", "SanksUm" → "SA" (dos primeras letras), "" → "??".
 *
 * Nota: el comentario que acompañaba a esta función en index.js decía "SU".
 * El código nunca hizo eso; se conserva el comportamiento real, que es el que
 * ya tienen calculado todas las cuentas existentes.
 *
 * Vive aquí y no dentro de index.js porque ahora la usan dos caminos de alta
 * de cuenta (registro con contraseña y registro con Google) y son las mismas
 * iniciales: duplicar la función es la forma más fácil de que un día un
 * camino calcule "DP" y el otro "Da".
 */
function calcularIniciales(nombre) {
  if (!nombre) return '??';
  const partes = nombre.trim().split(/\s+/);
  if (partes.length === 1) {
    return partes[0].slice(0, 2).toUpperCase();
  }
  return partes.map(w => w[0]).join('').slice(0, 2).toUpperCase();
}

module.exports = { calcularIniciales };
