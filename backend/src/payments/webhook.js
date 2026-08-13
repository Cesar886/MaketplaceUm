/**
 * Webhook (IPN) de Mercado Pago.
 *
 * Tres propiedades que este endpoint tiene que cumplir sí o sí:
 *
 * 1. AUTENTICADO. Es una ruta pública sin JWT: sin validar la firma,
 *    cualquiera puede hacer POST diciendo "el pago X fue aprobado" y marcar
 *    órdenes como pagadas sin haber pagado.
 * 2. RÁPIDO. MP corta a los pocos segundos y reintenta. Se responde 200 en
 *    cuanto el evento queda registrado; el trabajo real va después.
 * 3. IDEMPOTENTE. MP reenvía el mismo evento varias veces, y ante un timeout
 *    muchas. Procesarlo dos veces no puede duplicar ningún efecto.
 *
 * El estado del pago NUNCA se toma del cuerpo de la notificación: solo se
 * lee el id y se consulta GET /v1/payments/{id}. El cuerpo de un webhook es
 * un aviso, no una fuente de verdad.
 */

const crypto = require('crypto');
const db = require('../database');
const { config } = require('./config');
const store = require('./store');
const { obtenerPago, MpError } = require('./mpClient');

/**
 * Valida la cabecera `x-signature` de MP.
 *
 * Formato: `x-signature: ts=<epoch>,v1=<hmac_sha256_hex>`
 * Manifest firmado: `id:<data.id>;request-id:<x-request-id>;ts:<ts>;`
 * Clave: MP_WEBHOOK_SECRET (panel de MP → Webhooks).
 */
function validarFirma(req) {
  const secreto = config.webhookSecret;
  if (!secreto) {
    // Sin secreto configurado no se puede verificar nada. Se rechaza en vez
    // de aceptar a ciegas: aceptar sería peor que no tener webhook.
    return { valida: false, motivo: 'MP_WEBHOOK_SECRET no configurado' };
  }

  const cabecera = req.headers['x-signature'];
  const requestId = req.headers['x-request-id'] || '';
  if (!cabecera) return { valida: false, motivo: 'Falta x-signature' };

  const partes = Object.fromEntries(
    String(cabecera).split(',').map(p => {
      const i = p.indexOf('=');
      return i === -1 ? ['', ''] : [p.slice(0, i).trim(), p.slice(i + 1).trim()];
    }),
  );
  const { ts, v1 } = partes;
  if (!ts || !v1) return { valida: false, motivo: 'x-signature mal formada' };

  // `data.id` viene en la query string. MP lo firma en minúsculas.
  const dataId = String(req.query['data.id'] || req.query.id || '').toLowerCase();

  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  const esperado = crypto.createHmac('sha256', secreto).update(manifest).digest('hex');

  // Comparación en tiempo constante: un `===` sobre un HMAC filtra
  // información por el tiempo que tarda en fallar.
  const a = Buffer.from(esperado, 'utf8');
  const b = Buffer.from(String(v1), 'utf8');
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return { valida: false, motivo: 'Firma no coincide' };
  }

  // Ventana de 5 minutos contra replay de una notificación capturada.
  const edadSeg = Math.abs(Date.now() / 1000 - Number(ts) / (String(ts).length > 11 ? 1000 : 1));
  if (!Number.isFinite(edadSeg) || edadSeg > 300) {
    return { valida: false, motivo: 'Timestamp fuera de la ventana permitida' };
  }

  return { valida: true };
}

/**
 * Procesa el evento: consulta el pago real en MP y actualiza la orden.
 * Se ejecuta DESPUÉS de haber respondido 200, así que ningún error de aquí
 * puede provocar un reintento innecesario de MP; se registra y ya.
 */
async function procesarEvento({ eventId, paymentId }) {
  try {
    // La orden se localiza por external_reference (que es nuestro order_id)
    // o por el mp_payment_id si ya lo teníamos guardado del checkout.
    let orden = store.getOrdenPorPagoMp(paymentId);

    // El token del vendedor es el que puede consultar ese pago. Si aún no
    // sabemos de qué orden se trata, se intenta con el de la plataforma.
    let accessToken;
    if (orden) {
      const cuenta = store.getCuentaVendedorConToken(orden.vendor_id);
      accessToken = cuenta ? cuenta.accessToken : undefined;
    }

    let pago = await obtenerPago(paymentId, accessToken);
    if (!pago) return;

    if (!orden && pago.external_reference) {
      orden = store.getOrdenPorId(pago.external_reference);

      // Este es justo el caso que el fallback por external_reference existe
      // para cubrir: la orden no se conocía todavía, así que la primera
      // consulta se hizo con el token de la plataforma (o sin ninguno), no
      // con el del vendedor. El vendedor es el único que puede leer su
      // propio pago con autoridad, así que ahora que se sabe de qué orden
      // se trata, se busca su token y se vuelve a consultar con él antes de
      // persistir nada.
      if (orden) {
        const cuenta = store.getCuentaVendedorConToken(orden.vendor_id);
        if (cuenta) {
          accessToken = cuenta.accessToken;
          pago = await obtenerPago(paymentId, accessToken);
          if (!pago) return;
        }
      }
    }
    if (!orden) {
      console.warn(`[pagos] Webhook de un pago sin orden asociada (payment ${paymentId})`);
      return;
    }

    const actualizada = store.actualizarPagoDeOrden(orden.id, {
      mpPaymentId: pago.id,
      paymentStatus: pago.status,
    });

    // Mismo efecto que produce el checkout cuando MP aprueba en el momento
    // (ver routes.js): una orden de carrito que queda pagada saca sus
    // productos del carrito. Si el pago pasó por revisión antifraude y se
    // aprueba después, esta notificación es el ÚNICO aviso que va a haber —
    // sin esto el comprador reencuentra en su carrito algo que ya pagó,
    // listo para pagarlo por segunda vez.
    if (actualizada && pago.status === 'approved' && orden.origin === 'cart') {
      db.clearCartItems(orden.buyer_id, orden.items.map(i => i.product_id));
    }

    store.marcarEventoProcesado(eventId);
    console.log(`[pagos] Orden ${orden.id} → ${pago.status}`);
  } catch (err) {
    // Detalle completo al log del servidor; nadie más lo ve.
    const detalle = err instanceof MpError ? JSON.stringify(err.detalle) : err.message;
    console.error(`[pagos] Error procesando webhook ${eventId}: ${err.message} ${detalle || ''}`);
  }
}

module.exports = { validarFirma, procesarEvento };
