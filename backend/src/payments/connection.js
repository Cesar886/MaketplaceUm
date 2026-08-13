/**
 * Ciclo de vida de la conexión de pagos de un vendedor.
 *
 * Un vendedor puede perder la conexión de tres formas, y las tres tienen que
 * dejar el sistema en el MISMO estado:
 *
 *   1. La corta él desde la app (DELETE /api/payments/account).
 *   2. Revoca la autorización desde su panel de Mercado Pago → webhook.
 *   3. El webhook no llegó y nos enteramos al validar el token o al cobrar.
 *
 * Por eso la desconexión vive aquí y no repartida por las rutas: si cada
 * camino hiciera "su parte", el que se olvide de retirar 'tarjeta' deja al
 * comprador con un método que no cobra nada.
 */

const { randomUUID } = require('crypto');

const db = require('../database');
const store = require('./store');
const { validarTokenVendedor, MpError } = require('./mpClient');

const TIPO_NOTIFICACION = 'payment_account_disconnected';

/** Método que deja de tener sentido cuando la cuenta se cae. */
const METODO_TARJETA = 'tarjeta';

/**
 * Retira 'tarjeta' de los métodos aceptados de un vendedor.
 *
 * Si era el único, se cae a ['efectivo'] en vez de a []: el perfil exige al
 * menos un método, y dejarlo vacío le bloquearía guardar cualquier cambio
 * hasta que se diera cuenta de por qué.
 */
function retirarTarjetaDeLosMetodos(vendorId) {
  const fila = db.getDb()
    .prepare('SELECT paymentMethods FROM sellers WHERE id = ?')
    .get(vendorId);
  if (!fila || !fila.paymentMethods) return;

  let lista;
  try {
    lista = JSON.parse(fila.paymentMethods);
  } catch {
    return;
  }
  if (!Array.isArray(lista) || !lista.includes(METODO_TARJETA)) return;

  const restantes = lista.filter(m => m !== METODO_TARJETA);
  db.getDb()
    .prepare('UPDATE sellers SET paymentMethods = ? WHERE id = ?')
    .run(JSON.stringify(restantes.length ? restantes : ['efectivo']), vendorId);
}

function avisarAlVendedor(vendorId, motivo) {
  db.createNotification(
    `ntf_${randomUUID()}`,
    vendorId,
    TIPO_NOTIFICACION,
    'Tu cuenta de pagos se desconectó',
    'Dejaste de poder cobrar con tarjeta en Mercadito UM. '
      + 'Vuelve a conectar tu cuenta de Mercado Pago desde tu perfil para reactivarla.',
    { motivo: motivo || null },
  );
}

/**
 * Desconecta la cuenta de pagos de un vendedor y aplica TODAS las
 * consecuencias: retira 'tarjeta' de sus métodos, borra las tarjetas
 * guardadas que ya no se pueden cobrar y le avisa.
 *
 * @param {'user'|'webhook'|'token_check'} por quién detectó la desconexión
 * @returns {boolean} true si esta llamada la desconectó. false si ya estaba
 *   desconectada — importante porque MP reenvía el webhook de revocación
 *   varias veces y el vendedor no debe recibir una ristra de avisos iguales.
 */
function desconectar(vendorId, { motivo = null, por = 'user' } = {}) {
  const cambio = store.desconectarVendedor(vendorId, { motivo, por });
  if (!cambio) return false;

  retirarTarjetaDeLosMetodos(vendorId);
  store.borrarTarjetasDeVendedor(vendorId);

  // Una desconexión que pidió el propio vendedor no necesita avisarle de
  // algo que acaba de hacer a propósito.
  if (por !== 'user') avisarAlVendedor(vendorId, motivo);

  console.log(`[pagos] Vendedor ${vendorId} desconectado (${por}${motivo ? `: ${motivo}` : ''})`);
  return true;
}

/**
 * Comprueba contra Mercado Pago que el token del vendedor sigue vivo.
 *
 * Solo un 401/403 cuenta como revocación. Un 500 o una red caída NO
 * desconectan a nadie: sería tirarle el negocio a un vendedor por un hipo de
 * la API de MP, y el estado real se puede volver a consultar en un minuto.
 *
 * @returns {Promise<{conectado: boolean, motivo?: string}>}
 */
async function validarConexion(vendorId) {
  const cuenta = store.getCuentaVendedorConToken(vendorId);
  if (!cuenta?.accessToken) return { conectado: false, motivo: 'sin_cuenta' };

  try {
    await validarTokenVendedor(cuenta.accessToken);
    return { conectado: true };
  } catch (err) {
    const revocado = err instanceof MpError && (err.status === 401 || err.status === 403);
    if (!revocado) {
      // Se registra pero no se toca el estado: no sabemos nada nuevo.
      console.warn(`[pagos] No se pudo validar el token de ${vendorId}: ${err.message}`);
      return { conectado: true, motivo: 'validacion_no_concluyente' };
    }
    desconectar(vendorId, {
      motivo: 'Mercado Pago rechazó el token del vendedor',
      por: 'token_check',
    });
    return { conectado: false, motivo: 'revocado' };
  }
}

module.exports = {
  TIPO_NOTIFICACION,
  desconectar,
  validarConexion,
  retirarTarjetaDeLosMetodos,
};
