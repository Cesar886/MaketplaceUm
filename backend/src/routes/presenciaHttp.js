// Adaptador entre el registro de presencia (en memoria, en presence.js) y
// las rutas HTTP. Existe para que presence.js siga sin conocer ni a Express
// ni a SQLite y pueda probarse en aislamiento.

const db = require('../database');
const { describirPresencia } = require('../presence');

/**
 * Campos de presencia de `objetivoId` tal y como los ve `visorId`, listos
 * para expandirse en una respuesta JSON.
 *
 * Si la app no tiene registro montado (tests de otras rutas, o el servidor
 * arrancado sin Socket.IO) nadie figura en línea: se degrada a `last_active`
 * en vez de romper el endpoint.
 *
 * @returns {{isOnline: boolean, lastActive: string|null}}
 */
function presenciaDe(req, visorId, objetivoId) {
  const registro = req.app.get('presencia');
  return describirPresencia({
    visorId,
    objetivoId,
    estaEnLinea: registro ? (id) => registro.estaEnLinea(id) : () => false,
    getPresencia: (id) => db.getPresencia(id),
  });
}

module.exports = { presenciaDe };
