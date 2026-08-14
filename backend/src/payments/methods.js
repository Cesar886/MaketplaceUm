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

// Los motivos del pago con cuenta de MP se redactan aparte y no reusan los
// de arriba porque aquéllos terminan en "para volver a aceptar tarjeta": es
// el método equivocado, y un mensaje que nombra algo que la persona no
// eligió se lee como un error de la app.
const MOTIVO_MP_DESCONECTADO = 'La cuenta de pagos de este vendedor se desconectó. '
  + 'Necesita reconectarla para volver a cobrar en la app.';

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
 * Cobrar por la cuenta de Mercado Pago del COMPRADOR necesita una cosa
 * menos que la tarjeta: la cuenta del vendedor conectada, y nada más.
 *
 * No hace falta su public key porque en este flujo no se tokeniza nada en el
 * dispositivo — el comprador escribe sus credenciales en Mercado Pago, no en
 * la app, y lo único que creamos aquí es una preferencia con el token del
 * vendedor. Por eso un vendedor cuyo OAuth no devolvió public key puede
 * cobrar por este camino aunque no pueda por el de tarjeta.
 *
 * Está aparte de [cuentaDePagosConectada] por lo mismo que aquélla está
 * aparte de [tarjetaDisponible]: hoy coinciden en implementación, pero
 * responden a preguntas distintas y no tienen por qué moverse juntas.
 */
function cuentaMpDisponible(vendorId) {
  return Boolean(store.getCuentaVendedor(vendorId));
}

/**
 * @returns {string|null} por qué no se puede pagar con cuenta de Mercado
 *   Pago a este vendedor, o null si sí se puede.
 */
function motivoCuentaMpNoDisponible(vendorId) {
  if (cuentaMpDisponible(vendorId)) return null;
  const cuenta = store.getCuentaVendedorIncluyendoRevocada(vendorId);
  return cuenta ? MOTIVO_MP_DESCONECTADO : MOTIVO_SIN_CUENTA;
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
  const walletEnabled = cuentaMpDisponible(vendorId);

  return {
    vendorId,
    methods,
    cardEnabled,
    cardPublicKey: cardEnabled ? (cuenta?.mp_public_key || null) : null,

    // Segundo carril de cobro sobre la MISMA orden: el comprador paga desde
    // su propia cuenta de Mercado Pago en vez de escribir una tarjeta.
    // Va como campo propio y no como un elemento más de `methods` porque
    // `methods` es lo que el vendedor DECLARA en su perfil, y esto no se
    // declara: se deriva de tener la cuenta conectada, igual que
    // `cardEnabled`.
    walletEnabled,
    walletUnavailableReason: walletEnabled ? null : motivoCuentaMpNoDisponible(vendorId),
  };
}

module.exports = {
  METODOS_PROCESADOS,
  metodosAceptados,
  cuentaDePagosConectada,
  tarjetaDisponible,
  cuentaMpDisponible,
  motivoCuentaMpNoDisponible,
  motivoTarjetaNoDisponible,
  validarMetodosPermitidos,
  metodosDeVendedor,
};
