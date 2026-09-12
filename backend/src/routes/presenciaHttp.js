// Adaptador entre el registro de presencia (en memoria, en presence.js) y
// las rutas HTTP. Existe para que presence.js siga sin conocer ni a Express
// ni a SQLite y pueda probarse en aislamiento.

const db = require('../database');
const {
  presenciaVisible
} = require('../presence');

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
async function presenciaDe(req, visorId, objetivoId) {
  if (!visorId || !objetivoId) return {
    isOnline: false,
    lastActive: null
  };
  const registro = req.app.get('presencia');
  const [visor, objetivo] = await Promise.all([await db.getPresencia(visorId), await db.getPresencia(objetivoId)]);
  if (!presenciaVisible({
    visorComparte: visor.comparteEstado,
    objetivoComparte: objetivo.comparteEstado
  })) {
    return {
      isOnline: false,
      lastActive: null
    };
  }
  return {
    isOnline: registro ? registro.estaEnLinea(objetivoId) : false,
    lastActive: registro && registro.estaEnLinea(objetivoId) ? null : objetivo.lastActive
  };
}
module.exports = {
  presenciaDe
};
