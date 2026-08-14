/**
 * Utilidades compartidas por las pruebas de pagos.
 *
 * No forma parte del servidor: `scripts/deploy.sh` lo excluye del despliegue
 * junto con los `*.test.js`.
 */

/**
 * Corre algo capturando lo que se escriba en consola, y devuelve todo junto
 * como una sola cadena.
 *
 * Los logs de diagnóstico son el producto de estos endpoints tanto como su
 * respuesta: existen para poder ver, cuando un cobro falle en el navegador,
 * qué se le mandó exactamente a Mercado Pago y qué contestó. Si no se
 * prueban, se rompen sin que nadie se entere hasta el día que hacen falta.
 *
 * Los argumentos que no son cadenas se serializan en vez de quedar en
 * "[object Object]": varias pruebas buscan un id dentro de un objeto
 * registrado, y sin esto no lo encontrarían.
 */
async function capturandoLogs(fn) {
  const lineas = [];
  const original = { log: console.log, warn: console.warn, error: console.error };
  for (const nivel of ['log', 'warn', 'error']) {
    console[nivel] = (...args) => lineas.push(args.map(a =>
      typeof a === 'string' ? a : JSON.stringify(a)).join(' '));
  }
  try {
    await fn();
  } finally {
    Object.assign(console, original);
  }
  return lineas.join('\n');
}

module.exports = { capturandoLogs };
