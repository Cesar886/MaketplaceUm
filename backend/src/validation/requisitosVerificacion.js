/**
 * Requisitos que una cuenta debe cumplir para quedar verificada.
 *
 * Existe como módulo propio, y no como una tirada de `if` dentro del endpoint
 * de verificación, porque la MISMA regla se evalúa en tres sitios:
 *
 *   1. Al cerrar la verificación (los tres flujos: estudiante, negocio,
 *      externo) — routes/verificacion.js.
 *   2. Al conectar Mercado Pago, que puede cerrar una verificación que estaba
 *      esperando justo eso — el callback de OAuth.
 *   3. Al pintar el checklist en la app, ANTES de que la persona toque el
 *      botón — GET /api/verificacion/estado.
 *
 * Si cada uno tuviera su copia, el checklist acabaría diciendo "todo listo"
 * mientras el backend sigue rechazando, que es la peor versión posible de
 * este flujo: el usuario no tiene forma de saber qué está mal.
 *
 * Cada requisito se devuelve ESTRUCTURADO (no un string suelto) para que el
 * mensaje de error del backend y las palomitas de la app salgan del mismo
 * dato y no puedan desincronizarse.
 */

const db = require('../database');
const {
  cuentaDePagosConectada
} = require('../payments/methods');
const {
  mercadoPagoHabilitado
} = require('../payments/config');

/** Métodos que la app cobra de verdad y por tanto exigen cuenta conectada. */
const METODO_TARJETA = 'tarjeta';

/**
 * Estados manuales que sacan un producto del escaparate. Uno pausado o ya
 * vendido no se puede comprar, así que no tiene sentido exigirle inventario
 * para dejar verificar a su dueño.
 */
const ESTADOS_FUERA_DE_VENTA = new Set(['sold', 'paused']);
async function obtenerSeller(usuarioId) {
  return (await db.getDb().prepare('SELECT id, isBusiness, tipo_cuenta, businessHours, paymentMethods FROM sellers WHERE id = ?').get(usuarioId)) || null;
}
function parsearJson(crudo, porDefecto) {
  if (!crudo) return porDefecto;
  try {
    const valor = JSON.parse(crudo);
    return valor ?? porDefecto;
  } catch {
    // Un JSON corrupto se trata como ausente: es exactamente igual de
    // inservible, y reventar aquí tumbaría la verificación entera.
    return porDefecto;
  }
}

/** Días con horario configurado. Ver validation/sellerProfile.js. */
function tieneHorario(seller) {
  const horario = parsearJson(seller?.businessHours, {});
  if (typeof horario !== 'object' || Array.isArray(horario)) return false;
  // No hace falta comprobar rangos degenerados (00:00-00:00): al guardar,
  // `validateBusinessHours` ya rechaza cualquier cierre <= apertura.
  return Object.keys(horario).length > 0;
}
function metodosDe(seller) {
  const lista = parsearJson(seller?.paymentMethods, []);
  return Array.isArray(lista) ? lista : [];
}

/**
 * Productos a la venta a los que les falta decidir el inventario.
 *
 * `stock_quantity` NULL significaba "sin límite". Se retira esa opción: un
 * producto que se puede pagar dentro de la app necesita una cantidad contra
 * la que descontar, o se vende lo que ya no existe.
 */
async function productosSinStock(usuarioId) {
  return (await db.getDb().prepare(`SELECT id, title, manual_status FROM products
       WHERE seller = ? AND stock_quantity IS NULL
       ORDER BY title`).all(usuarioId)).filter(p => !ESTADOS_FUERA_DE_VENTA.has(p.manual_status)).map(p => ({
    id: p.id,
    title: p.title
  }));
}

/**
 * Los cuatro requisitos con su estado actual, SIEMPRE en el mismo orden.
 *
 * El orden es estable a propósito: si bailara, quien arregla lo que se le
 * pide vería aparecer un requisito distinto cada vez, sin saber nunca
 * cuántos le quedan.
 *
 * @returns {Array<{id, titulo, detalle, cumplido, accion, productos?}>}
 *   `accion` le dice a la app a dónde llevar a la persona para resolverlo.
 */
async function requisitosDeVerificacion(usuarioId) {
  const seller = await obtenerSeller(usuarioId);
  // Las dos columnas que dicen "esto es un negocio", no una sola:
  // `tipo_cuenta` es la canónica (la que mira exigirTipo en
  // routes/verificacion.js) pero puede venir NULL en filas antiguas, e
  // `isBusiness` es la que existía antes de ella. Si alguna vez divergen,
  // esto se queda del lado estricto —pedir el horario de más, nunca de
  // menos—, que es el error barato de los dos.
  const esNegocio = Boolean(seller && (seller.tipo_cuenta === 'negocio' || seller.isBusiness));
  const metodos = metodosDe(seller);
  const aceptaTarjeta = metodos.includes(METODO_TARJETA);
  const sinStock = seller ? await productosSinStock(usuarioId) : [];
  return [{
    id: 'horario',
    titulo: 'Horario de atención',
    // Solo se le exige al NEGOCIO. Un alumno o una cuenta externa no
    // atienden en un horario publicado —venden coordinando por chat—, y
    // además el perfil de vendedor solo persiste `businessHours` para
    // negocios (ver routes/sellers.js): pedírselo a los demás los dejaba
    // con un requisito imposible de cumplir y la verificación bloqueada
    // para siempre. El vendedor inexistente sigue incumpliendo.
    cumplido: Boolean(seller) && (!esNegocio || tieneHorario(seller)),
    detalle: 'Configura al menos un día con su horario en "Editar perfil". ' + 'Es lo que le dice al comprador si estás abierto cuando te compra.',
    accion: 'editar_perfil'
  }, {
    id: 'metodos_pago',
    titulo: 'Métodos de pago',
    cumplido: metodos.length > 0,
    detalle: 'Elige al menos un método de pago que aceptas en "Editar perfil".',
    accion: 'editar_perfil'
  }, {
    id: 'mercadopago',
    titulo: 'Cuenta de cobros',
    // TODO: Mercado Pago pendiente para próxima actualización - no
    // eliminar, solo descomentar la línea de abajo (y borrar la que la
    // reemplaza) cuando MERCADO_PAGO_HABILITADO=true y el frontend
    // reactive kMercadoPagoHabilitado.
    //
    // Validación original: solo se exige a quien anuncia tarjeta —es el
    // único método que la app cobra de verdad—, y a quien solo acepta
    // efectivo pedirle una cuenta de Mercado Pago sería bloquearle algo
    // que no va a usar.
    // cumplido: !aceptaTarjeta || cuentaDePagosConectada(usuarioId),
    //
    // Mientras Mercado Pago esté deshabilitado en el backend, este
    // requisito se da siempre por cumplido: nadie puede conectar una
    // cuenta desde una app que tiene la integración oculta, así que
    // exigirlo dejaría a cualquier cuenta (negocio, estudiante, externo)
    // atorada en 'pendiente' para siempre.
    cumplido: !mercadoPagoHabilitado() || !aceptaTarjeta || (await cuentaDePagosConectada(usuarioId)),
    detalle: 'Aceptas pagos con tarjeta, así que necesitas conectar tu cuenta ' + 'de Mercado Pago para poder cobrarlos.',
    accion: 'conectar_mercadopago'
  }, {
    id: 'stock_productos',
    titulo: 'Inventario de tus productos',
    cumplido: sinStock.length === 0,
    detalle: sinStock.length === 0 ? 'Todos tus productos tienen cantidad definida.' : `Define la cantidad disponible de: ${sinStock.map(p => p.title).join(', ')}.`,
    accion: 'revisar_productos',
    productos: sinStock
  }];
}
async function cumpleTodos(usuarioId) {
  return (await requisitosDeVerificacion(usuarioId)).every(r => r.cumplido);
}

/**
 * El primer requisito sin cumplir, o null si están todos.
 *
 * Se devuelve UNO y no la lista entera para el mensaje de error: la app ya
 * pinta el checklist completo, y un error que enumera cuatro cosas a la vez
 * no se lee.
 */
async function primerFaltante(usuarioId) {
  return (await requisitosDeVerificacion(usuarioId)).find(r => !r.cumplido) || null;
}
module.exports = {
  requisitosDeVerificacion,
  cumpleTodos,
  primerFaltante,
  productosSinStock
};
