/**
 * Disponibilidad de métodos de pago por vendedor.
 *
 * 'tarjeta' es distinto al resto del catálogo: 'efectivo' o 'cripto' son
 * acuerdos entre las partes que la app solo anuncia, mientras que 'tarjeta'
 * la cobra la app de verdad. Por eso solo existe si ESE vendedor tiene una
 * cuenta de pago conectada y viva, y la comprobación tiene que estar en el
 * servidor: si viviera solo en la UI, cualquier cliente que la ignore deja
 * órdenes con un método que nadie puede cobrar.
 */

const db = require('../database');
const store = require('./store');

/** Métodos que la app cobra por sí misma, y que por tanto tienen requisitos. */
const METODOS_PROCESADOS = new Set(['tarjeta']);

const MOTIVO_SIN_CUENTA = 'Este vendedor no tiene una cuenta de pagos conectada.';
const MOTIVO_DESCONECTADO = 'La cuenta de pagos de este vendedor se desconectó. '
  + 'Necesita reconectarla para volver a aceptar tarjeta.';
const MOTIVO_SIN_CLAVE = 'La cuenta de pagos de este vendedor está incompleta. '
  + 'Necesita reconectarla para poder aceptar tarjeta.';

/** Lista declarada por el vendedor (JSON en sellers.paymentMethods). */
function metodosAceptados(vendorId) {
  const fila = db.getDb()
    .prepare('SELECT paymentMethods FROM sellers WHERE id = ?')
    .get(vendorId);
  if (!fila || !fila.paymentMethods) return [];
  try {
    const lista = JSON.parse(fila.paymentMethods);
    return Array.isArray(lista) ? lista : [];
  } catch {
    return [];
  }
}

/**
 * ¿Este vendedor tiene una cuenta de pagos conectada y viva?
 *
 * Hoy coincide en implementación con `tarjetaDisponible`, pero responde a
 * otra pregunta: aquélla es "¿puedo ofrecer tarjeta en el checkout?" y ésta
 * es "¿tiene medio de cobro?", que es lo que exige la verificación de
 * negocio. Separarlas evita que un cambio en una arrastre a la otra sin
 * querer.
 */
function cuentaDePagosConectada(vendorId) {
  return Boolean(store.getCuentaVendedor(vendorId));
}

/**
 * Cobrar con tarjeta necesita DOS cosas, no una: la cuenta conectada (para
 * el cobro) y su public key guardada (para que el cliente pueda tokenizar).
 * Una cuenta sin public key —la respuesta de OAuth no siempre la trae— deja
 * al comprador en un callejón: la opción aparece y no hay con qué tokenizar.
 */
function tarjetaDisponible(vendorId) {
  const cuenta = store.getCuentaVendedor(vendorId);
  return Boolean(cuenta && cuenta.mp_public_key);
}

/**
 * @returns {string|null} por qué este vendedor no puede cobrar con tarjeta,
 *   o null si sí puede. Distingue los tres casos porque la acción que
 *   resuelve cada uno es distinta.
 */
function motivoTarjetaNoDisponible(vendorId) {
  if (tarjetaDisponible(vendorId)) return null;
  const activa = store.getCuentaVendedor(vendorId);
  if (activa) return MOTIVO_SIN_CLAVE;
  const cuenta = store.getCuentaVendedorIncluyendoRevocada(vendorId);
  return cuenta ? MOTIVO_DESCONECTADO : MOTIVO_SIN_CUENTA;
}

/**
 * Rechaza métodos que el vendedor no está en condiciones de cobrar. Se
 * aplica al guardar perfil y al guardar una publicación con métodos propios.
 *
 * @returns {{error?: string}} error listo para devolver en un 400
 */
function validarMetodosPermitidos(vendorId, metodos) {
  if (!Array.isArray(metodos)) return {};
  for (const metodo of metodos) {
    if (!METODOS_PROCESADOS.has(metodo)) continue;
    const motivo = motivoTarjetaNoDisponible(vendorId);
    if (motivo) {
      return {
        error: 'Conecta tu cuenta de Mercado Pago para aceptar pagos con tarjeta.',
      };
    }
  }
  return {};
}

/**
 * Lo que el checkout necesita saber de un vendedor: qué acepta, qué de eso
 * funciona ahora mismo, y con qué clave tokenizar si toca tarjeta.
 *
 * La `cardPublicKey` es la DEL VENDEDOR, no la de la plataforma: en el modo
 * marketplace un card_token creado con otra public key no pertenece a esa
 * cuenta y MP lo rechaza al cobrar.
 *
 * `methods` y `cardEnabled` responden a preguntas DISTINTAS, y por eso son
 * dos campos y no uno:
 *
 * - `methods` es lo que el vendedor ANUNCIA (su lista declarada). De ella
 *   depende validar una orden que pide un método explícito: a quien solo
 *   quiere cobrar en efectivo no se le puede imponer otra cosa.
 * - `cardEnabled` es si su cuenta PUEDE cobrar con tarjeta ahora mismo.
 *
 * Conectar Mercado Pago y marcar 'tarjeta' en el perfil son dos acciones
 * distintas, y la gente hace la primera sin la segunda. Como `/checkout` solo
 * exige la cuenta conectada y el token vivo —nunca mira la lista declarada—,
 * esconderle el pago a un vendedor conectado sería negarle ventas que su
 * cuenta cobraría hoy mismo.
 */
function metodosDeVendedor(vendorId) {
  const aceptados = metodosAceptados(vendorId);
  const cuenta = store.getCuentaVendedor(vendorId);

  const methods = aceptados.map((id) => {
    if (!METODOS_PROCESADOS.has(id)) return { id, available: true };
    const motivo = motivoTarjetaNoDisponible(vendorId);
    return motivo
      ? { id, available: false, unavailableReason: motivo }
      : { id, available: true };
  });

  const cardEnabled = tarjetaDisponible(vendorId);

  return {
    vendorId,
    methods,
    cardEnabled,
    cardPublicKey: cardEnabled ? (cuenta?.mp_public_key || null) : null,
  };
}

module.exports = {
  METODOS_PROCESADOS,
  metodosAceptados,
  cuentaDePagosConectada,
  tarjetaDisponible,
  motivoTarjetaNoDisponible,
  validarMetodosPermitidos,
  metodosDeVendedor,
};
