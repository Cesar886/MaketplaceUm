/**
 * Decide si en un cobro concreto se puede cobrar comisión de plataforma.
 *
 * Nace del error 2059 de Mercado Pago —"You cannot use application_fee with
 * this payment"— que NO es un rechazo de la tarjeta: es MP diciendo que en
 * ese cobro la comisión no aplica. Manda el pago entero al fracaso, así que
 * el comprador ve "no se pudo procesar" por un problema que no tiene nada
 * que ver con su tarjeta.
 *
 * Su causa principal es que el vendedor conectado sea LA MISMA cuenta de
 * Mercado Pago que es dueña de la aplicación. Nadie puede cobrarse una
 * comisión a sí mismo. Y es un caso que ocurre constantemente al probar:
 * quien crea la aplicación en el panel de MP conecta su propia cuenta como
 * primer vendedor, porque es la que tiene a mano.
 *
 * ── La regla de este archivo ──────────────────────────────────
 *
 * La comisión SOLO se omite cuando se sabe con certeza que no puede
 * cobrarse. Ante la duda —una consulta a MP que falló, una cuenta que no se
 * pudo identificar— se manda igual.
 *
 * La asimetría es deliberada y va en contra del instinto de "que el pago no
 * falle": mandar la comisión de más hace que el cobro falle con un error
 * ruidoso que alguien arregla esa misma tarde. Omitirla de más hace que el
 * cobro funcione perfectamente y la plataforma no gane nada, en silencio,
 * hasta que alguien cuadre las cuentas semanas después. El fallo caro es el
 * silencioso.
 */

const cfg = require('./config');

// El módulo entero y no `const { validarTokenVendedor } = ...`: una
// desestructuración fija la referencia en el `require` y deja de ver
// cualquier reasignación posterior, que es justo como las pruebas sustituyen
// las llamadas a Mercado Pago. Es también lo que hace routes.js.
const mp = require('./mpClient');

/**
 * Id de Mercado Pago de la cuenta DUEÑA de la aplicación.
 *
 * Se memoiza porque es un valor fijo por despliegue y esto se consulta en
 * cada cobro: sin caché, cada pago arrastraría una llamada extra a MP y su
 * latencia, y un fallo suyo pasaría a poder tumbar cobros.
 *
 * El fallo se cachea en negativo a propósito (`null` con marca de tiempo):
 * si MP está caído, reintentarlo en cada cobro solo añade 20 segundos de
 * timeout a cada pago. Se reintenta pasados unos minutos.
 */
let cache = { id: undefined, expira: 0 };

const TTL_OK = 60 * 60 * 1000;   // 1 h: es un dato que no cambia nunca.
const TTL_FALLO = 5 * 60 * 1000; // 5 min: reintento tras un fallo de red.

/** Solo para las pruebas: olvida lo memoizado. */
function _resetCache() {
  cache = { id: undefined, expira: 0 };
}

/**
 * @returns {Promise<string|null>} el user_id de MP de la plataforma, o null
 *   si no se pudo averiguar (sin credencial, o MP no respondió).
 */
async function idDeLaPlataforma() {
  if (cache.expira > Date.now()) return cache.id;

  if (!cfg.config.accessToken) {
    cache = { id: null, expira: Date.now() + TTL_FALLO };
    return null;
  }

  try {
    const yo = await mp.validarTokenVendedor(cfg.config.accessToken);
    const id = yo?.id != null ? String(yo.id) : null;
    cache = { id, expira: Date.now() + (id ? TTL_OK : TTL_FALLO) };
    return id;
  } catch (err) {
    const detalle = err instanceof mp.MpError ? `status=${err.status}` : err.message;
    console.error(`[pagos] No se pudo identificar la cuenta de la plataforma: ${detalle}`);
    cache = { id: null, expira: Date.now() + TTL_FALLO };
    return null;
  }
}

/**
 * La comisión que se puede mandar de verdad en este cobro.
 *
 * @param {number} comision calculada por `fees.calcularComision`
 * @param {string|null} mpUserIdVendedor id de MP del vendedor que cobra,
 *   tal como lo guardó el OAuth
 * @param {string} contexto para el log (id de la orden)
 * @returns {Promise<number>} la comisión, o 0 si no se puede cobrar
 */
async function comisionCobrable(comision, mpUserIdVendedor, contexto = '') {
  if (!(comision > 0)) return 0;

  if (!cfg.comisionHabilitada()) {
    console.warn(`[pagos] ${contexto}: comisión omitida por PLATFORM_FEE_ENABLED=false`);
    return 0;
  }

  // Sin saber quién cobra no se puede afirmar que sea la plataforma. Se
  // manda la comisión: ver la regla de la cabecera.
  if (!mpUserIdVendedor) return comision;

  const plataforma = await idDeLaPlataforma();
  if (!plataforma) return comision;

  if (String(mpUserIdVendedor) === plataforma) {
    // Este es el 2059. Se omite la comisión para que el cobro salga, y se
    // avisa fuerte: en producción significa que un vendedor está cobrando
    // sin dejarle nada a la plataforma, y eso hay que verlo en el log.
    console.warn(
      `[pagos] ${contexto}: el vendedor (${mpUserIdVendedor}) es la cuenta dueña `
      + 'de la aplicación de Mercado Pago. Se cobra SIN comisión: MP rechaza '
      + 'application_fee cuando quien cobra es uno mismo (error 2059). '
      + 'En producción, conecta una cuenta de vendedor distinta.',
    );
    return 0;
  }

  return comision;
}

/** Código de MP para "no puedes usar application_fee en este pago". */
const CODIGO_COMISION_NO_APLICABLE = 2059;

/**
 * ¿Este fallo de MP es el 2059?
 *
 * Importa distinguirlo porque llega como un 400, y un 400 de `/v1/payments`
 * se traduce por defecto a "no se pudo procesar el pago con esa tarjeta,
 * intenta con otra". Eso es una mentira que cuesta caro: la tarjeta está
 * perfecta, y quien compra prueba una segunda y una tercera —cada una un
 * intento gastado del límite antifraude— para acabar creyendo que su banco
 * le bloquea.
 *
 * Si esto salta después de [comisionCobrable], la causa que queda es que la
 * aplicación de Mercado Pago no esté creada con el modelo de integración
 * "Marketplace". Eso no se puede cambiar en una aplicación ya creada: hay
 * que crear otra.
 */
function esRechazoDeComision(err) {
  const causas = err?.detalle?.cause;
  if (!Array.isArray(causas)) return false;
  return causas.some(c => Number(c?.code) === CODIGO_COMISION_NO_APLICABLE);
}

module.exports = {
  comisionCobrable,
  idDeLaPlataforma,
  esRechazoDeComision,
  CODIGO_COMISION_NO_APLICABLE,
  _resetCache,
};
