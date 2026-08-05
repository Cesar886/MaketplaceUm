// Política de envío compartida por mailer.js (email) y sms.js (SMS).
//
// Los dos adaptadores se comportan igual cuando faltan credenciales, y esa
// decisión vive aquí para poder testearla sin tocar red ni variables de
// entorno globales.

/**
 * @param {{ configurado: boolean, produccion: boolean }} contexto
 * @returns {{ modo: 'proveedor'|'dev'|'no_disponible' }}
 *   - proveedor: hay credenciales, se envía de verdad.
 *   - dev: sin credenciales fuera de producción; el código se imprime en la
 *     consola del backend y viaja en la respuesta como `codigo_dev`.
 *   - no_disponible: sin credenciales en producción; el endpoint responde 503
 *     en vez de dejar al usuario esperando un código que nunca llega.
 */
function resolverModoEnvio({ configurado, produccion }) {
  if (configurado) return { modo: 'proveedor' };
  return { modo: produccion ? 'no_disponible' : 'dev' };
}

function esProduccion() {
  return process.env.NODE_ENV === 'production';
}

module.exports = { resolverModoEnvio, esProduccion };
