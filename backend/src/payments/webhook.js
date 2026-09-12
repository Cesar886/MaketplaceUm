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
const {
  config,
  traza
} = require('./config');
const store = require('./store');
const {
  obtenerPago,
  MpError
} = require('./mpClient');

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
    return {
      valida: false,
      motivo: 'MP_WEBHOOK_SECRET no configurado'
    };
  }
  const cabecera = req.headers['x-signature'];
  const requestId = req.headers['x-request-id'] || '';
  if (!cabecera) return {
    valida: false,
    motivo: 'Falta x-signature'
  };
  const partes = Object.fromEntries(String(cabecera).split(',').map(p => {
    const i = p.indexOf('=');
    return i === -1 ? ['', ''] : [p.slice(0, i).trim(), p.slice(i + 1).trim()];
  }));
  const {
    ts,
    v1
  } = partes;
  if (!ts || !v1) return {
    valida: false,
    motivo: 'x-signature mal formada'
  };

  // `data.id` viene en la query string. MP lo firma en minúsculas.
  const dataId = String(req.query['data.id'] || req.query.id || '').toLowerCase();
  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  const esperado = crypto.createHmac('sha256', secreto).update(manifest).digest('hex');

  // Comparación en tiempo constante: un `===` sobre un HMAC filtra
  // información por el tiempo que tarda en fallar.
  const a = Buffer.from(esperado, 'utf8');
  const b = Buffer.from(String(v1), 'utf8');
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return {
      valida: false,
      motivo: 'Firma no coincide'
    };
  }

  // Ventana de 5 minutos contra replay de una notificación capturada.
  const edadSeg = Math.abs(Date.now() / 1000 - Number(ts) / (String(ts).length > 11 ? 1000 : 1));
  if (!Number.isFinite(edadSeg) || edadSeg > 300) {
    return {
      valida: false,
      motivo: 'Timestamp fuera de la ventana permitida'
    };
  }
  return {
    valida: true
  };
}

/**
 * Procesa el evento: consulta el pago real en MP y actualiza la orden.
 * Se ejecuta DESPUÉS de haber respondido 200, así que ningún error de aquí
 * puede provocar un reintento innecesario de MP; se registra y ya.
 */
async function procesarEvento({
  eventId,
  paymentId
}) {
  traza(`evento ${eventId}: procesando pago ${paymentId}`);
  try {
    // La orden se localiza por external_reference (que es nuestro order_id)
    // o por el mp_payment_id si ya lo teníamos guardado del checkout.
    let orden = await store.getOrdenPorPagoMp(paymentId);
    traza(`evento ${eventId}: búsqueda por mp_payment_id -> ` + `${orden ? `orden ${orden.id}` : 'sin resultado, se intentará por external_reference'}`);

    // El token del vendedor es el que puede consultar ese pago. Si aún no
    // sabemos de qué orden se trata, se intenta con el de la plataforma.
    let accessToken;
    let sinTokenDelVendedor = false;
    if (orden) {
      const cuenta = await store.getCuentaVendedorConToken(orden.vendor_id);
      accessToken = cuenta ? cuenta.accessToken : undefined;
      sinTokenDelVendedor = !cuenta;
    }
    let pago = await obtenerPago(paymentId, accessToken);
    if (!pago) {
      // Silencio absoluto hasta ahora. Este `return` es un final posible del
      // webhook —el pago existe en MP pero no lo pudimos leer— y sin línea
      // era indistinguible de "el evento nunca llegó".
      //
      // La causa probable va DENTRO de esta línea y no en un aviso propio
      // más arriba: sin cuenta conectada la consulta se hace con la
      // credencial de la plataforma y MP no devuelve un pago que no es suyo.
      // Avisarlo por separado gastaba dos líneas en un solo hecho, y saltaba
      // igual las veces en que la consulta sí funcionaba.
      console.warn(`[pagos] Webhook ${eventId}: Mercado Pago no devolvió el pago ${paymentId}` + (sinTokenDelVendedor ? ` (el vendedor ${orden.vendor_id} no tiene cuenta conectada, así que se ` + 'consultó con la credencial de la plataforma)' : '') + '. La orden se queda como está.');
      return;
    }
    traza(`evento ${eventId}: MP dice pago ${pago.id} status=${pago.status} ` + `detalle=${pago.status_detail || '—'} monto=${pago.transaction_amount} ` + `comisión=${pago.application_fee ?? '(ninguna)'} ` + `external_reference=${pago.external_reference || '—'}`);
    if (!orden && pago.external_reference) {
      orden = await store.getOrdenPorId(pago.external_reference);

      // Este es justo el caso que el fallback por external_reference existe
      // para cubrir: la orden no se conocía todavía, así que la primera
      // consulta se hizo con el token de la plataforma (o sin ninguno), no
      // con el del vendedor. El vendedor es el único que puede leer su
      // propio pago con autoridad, así que ahora que se sabe de qué orden
      // se trata, se busca su token y se vuelve a consultar con él antes de
      // persistir nada.
      traza(`evento ${eventId}: búsqueda por external_reference ` + `"${pago.external_reference}" -> ${orden ? `orden ${orden.id}` : 'sin resultado'}`);
      if (orden) {
        const cuenta = await store.getCuentaVendedorConToken(orden.vendor_id);
        if (cuenta) {
          accessToken = cuenta.accessToken;
          traza(`evento ${eventId}: releyendo el pago con el token del vendedor`);
          pago = await obtenerPago(paymentId, accessToken);
          if (!pago) {
            console.warn(`[pagos] Webhook ${eventId}: el pago ${paymentId} dejó de ser legible al ` + `releerlo con el token del vendedor ${orden.vendor_id}.`);
            return;
          }
        }
      }
    }
    if (!orden) {
      console.warn(`[pagos] Webhook de un pago sin orden asociada (payment ${paymentId}, ` + `external_reference "${pago.external_reference || '—'}"). Si ese external_reference ` + 'es un id de orden nuestro, la orden se borró o nunca se guardó.');
      return;
    }
    const actualizada = await store.actualizarPagoDeOrden(orden.id, {
      mpPaymentId: pago.id,
      paymentStatus: pago.status
    });

    // `actualizada` en false se ignoraba en silencio. No siempre es un
    // fallo: casi siempre es la guarda de `actualizarPagoDeOrden` haciendo
    // su trabajo, porque MP no entrega los eventos en orden y un 'pending'
    // tardío no puede tumbar una orden ya aprobada. Un reenvío del MISMO
    // estado sí devuelve true, así que esto no se dispara en cada
    // reintento.
    //
    // Se registra igualmente porque es indistinguible, desde fuera, del
    // caso caro: el comprador pagó, MP avisó, y la orden no se marcó.
    if (!actualizada) {
      console.warn(`[pagos] Webhook ${eventId}: la orden ${orden.id} se dejó como estaba ` + `(${orden.payment_status || 'sin estado'}) ante el pago ${pago.id} ` + `(${pago.status}). Normalmente es un evento que llega desordenado y la ` + 'guarda impide que un estado final retroceda. Si la orden se queda así ' + 'con un pago aprobado, eso sí es un fallo.');
    }

    // Mismo efecto que produce el checkout cuando MP aprueba en el momento
    // (ver routes.js): una orden de carrito que queda pagada saca sus
    // productos del carrito. Si el pago pasó por revisión antifraude y se
    // aprueba después, esta notificación es el ÚNICO aviso que va a haber —
    // sin esto el comprador reencuentra en su carrito algo que ya pagó,
    // listo para pagarlo por segunda vez.
    if (actualizada && pago.status === 'approved' && orden.origin === 'cart') {
      await db.clearCartItems(orden.buyer_id, orden.items.map(i => i.product_id));
      traza(`evento ${eventId}: orden ${orden.id} venía del carrito, productos retirados`);
    }
    await store.marcarEventoProcesado(eventId);
    console.log(`[pagos] Orden ${orden.id} → ${pago.status}` + (pago.status === 'approved' ? '' : ` (${pago.status_detail || 'sin detalle'})`));
  } catch (err) {
    // Detalle completo al log del servidor; nadie más lo ve.
    const detalle = err instanceof MpError ? JSON.stringify(err.detalle) : err.message;
    console.error(`[pagos] Error procesando webhook ${eventId}: ${err.message} ${detalle || ''}`);
  }
}
module.exports = {
  validarFirma,
  procesarEvento
};
