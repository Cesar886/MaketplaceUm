/**
 * Endpoints de pagos con Mercado Pago (split payments / marketplace).
 *
 * Reglas que aplican a TODO este archivo:
 *
 * - Ningún error crudo de MP sale hacia el cliente. Se registra completo en
 *   el servidor (ya redactado de secretos) y al usuario le llega un mensaje
 *   genérico. Un error de MP puede contener eco del payload enviado.
 * - La pertenencia de cada recurso se comprueba contra `req.user.id`, y se
 *   comprueba en el SQL (ver payments/store.js), no con un `if` suelto.
 * - Los importes SIEMPRE se recalculan en el servidor desde `order_items`.
 *   Un monto que venga del cliente es una invitación a pagar $1 por algo de
 *   $1000.
 */

const { randomUUID } = require('crypto');

const { requireAuth } = require('../auth');
const db = require('../database');
const cfg = require('./config');
const store = require('./store');
const mp = require('./mpClient');
const { calcularComision, redondear2 } = require('./fees');
const { tokenVigenteDeVendedor } = require('./vendorTokens');
const { validarFirma, procesarEvento } = require('./webhook');

const MENSAJE_GENERICO = 'No pudimos completar la operación. Intenta de nuevo en unos minutos.';

/**
 * Registra el fallo con todo el detalle en el servidor y responde algo
 * seguro. Es el único camino por el que un error de MP llega al cliente.
 */
function fallo(res, contexto, err, { status = 502, mensaje = MENSAJE_GENERICO } = {}) {
  const detalle = err instanceof mp.MpError
    ? `status=${err.status} detalle=${JSON.stringify(err.detalle)} causa=${err.causa || '-'}`
    : err?.stack || String(err);
  console.error(`[pagos] ${contexto}: ${detalle}`);
  res.status(status).json({ error: mensaje });
}

function getSeller(id) {
  return db.getDb().prepare('SELECT * FROM sellers WHERE id = ?').get(id) || null;
}

/** Solo negocios y estudiantes verificados pueden recibir dinero. */
function puedeVender(seller) {
  if (!seller) return false;
  if (!seller.verified) return false;
  return seller.tipo_cuenta === 'negocio' || seller.tipo_cuenta === 'estudiante';
}

function tarjetaPublica(fila) {
  // Lo único que sale hacia la app. No hay más datos guardados, pero se
  // construye el objeto de forma explícita para que añadir una columna
  // sensible en el futuro no la exponga por accidente con un spread.
  return {
    id: fila.mp_card_id,
    lastFourDigits: fila.last_four_digits,
    paymentMethod: fila.payment_method,
    expirationMonth: fila.expiration_month,
    expirationYear: fila.expiration_year,
  };
}

function ordenPublica(orden) {
  return {
    id: orden.id,
    buyerId: orden.buyer_id,
    vendorId: orden.vendor_id,
    amount: orden.amount,
    applicationFee: orden.application_fee,
    currency: orden.currency,
    status: orden.status,
    paymentStatus: orden.payment_status,
    origin: orden.origin,
    createdAt: orden.created_at,
    items: (orden.items || []).map(i => ({
      productId: i.product_id,
      quantity: i.quantity,
      unitPrice: i.unit_price,
      title: i.title_snapshot,
    })),
  };
}

function register(app) {
  // ─── Configuración pública ────────────────────────────────
  //
  // La app necesita la MP_PUBLIC_KEY para tokenizar tarjetas contra la API
  // pública de MP. Es una clave pública: puede salir del servidor. Se sirve
  // desde aquí en vez de compilarla en la app para poder rotarla sin
  // publicar una versión nueva en las tiendas.
  app.get('/api/payments/config', requireAuth, (req, res) => {
    if (!cfg.assertConfigurado(res)) return;
    res.json({
      publicKey: cfg.config.publicKey,
      currency: cfg.config.moneda,
      feePercent: cfg.porcentajeComision(),
    });
  });

  // ─── 1. OAuth: iniciar conexión del vendedor ──────────────
  app.get('/api/payments/oauth/connect', requireAuth, (req, res) => {
    if (!cfg.assertConfigurado(res)) return;

    const seller = getSeller(req.user.id);
    if (!puedeVender(seller)) {
      return res.status(403).json({
        error: 'Necesitas una cuenta verificada de negocio o estudiante para recibir pagos.',
      });
    }

    store.limpiarOAuthStatesViejos();
    const state = store.crearOAuthState(req.user.id);
    res.json({ url: mp.urlAutorizacion(state) });
  });

  // ─── 2. OAuth: callback ───────────────────────────────────
  //
  // Lo abre el navegador del vendedor, no la app: por eso responde HTML y
  // no JSON, y termina mandando de vuelta al deep link.
  app.get('/api/payments/oauth/callback', async (req, res) => {
    const paginaFinal = (titulo, texto, ok) => `<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${titulo}</title>
<style>
 body{font-family:system-ui,-apple-system,sans-serif;background:#0F2740;color:#fff;
      display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px}
 .c{max-width:420px;text-align:center}
 h1{font-size:20px;margin:0 0 12px}p{opacity:.8;line-height:1.5;margin:0 0 24px}
 a{display:inline-block;background:#C77B4A;color:#fff;text-decoration:none;
   padding:12px 24px;border-radius:12px;font-weight:600}
</style></head><body><div class="c">
<h1>${titulo}</h1><p>${texto}</p>
<a href="${cfg.config.appDeepLinkScheme}://payments/connected?ok=${ok ? '1' : '0'}">Volver a Mercadito UM</a>
</div></body></html>`;

    try {
      if (!cfg.estaConfigurado()) {
        return res.status(503).send(paginaFinal('Pagos no disponibles',
          'La plataforma todavía no tiene configurados los pagos.', false));
      }

      const { code, state } = req.query;
      if (!code || !state) {
        return res.status(400).send(paginaFinal('Faltan datos',
          'La autorización no se completó. Inténtalo de nuevo desde la app.', false));
      }

      // El `state` prueba que este callback corresponde a una conexión que
      // ESTE servidor inició para ESE vendedor. Sin él, alguien podría hacer
      // que se vinculara su cuenta de MP al vendedor equivocado.
      const sellerId = store.consumirOAuthState(String(state));
      if (!sellerId) {
        return res.status(400).send(paginaFinal('Enlace caducado',
          'El enlace de conexión ya se usó o expiró. Vuelve a intentarlo desde la app.', false));
      }

      // Endpoint: POST /oauth/token — canjea el code por los tokens.
      const datos = await mp.canjearCodigoOAuth(String(code));
      if (!datos?.access_token || !datos?.user_id) {
        throw new mp.MpError('Respuesta de OAuth sin access_token o user_id');
      }

      store.guardarCuentaVendedor(sellerId, {
        mpUserId: datos.user_id,
        accessToken: datos.access_token,
        refreshToken: datos.refresh_token,
        expiresIn: datos.expires_in,
        publicKey: datos.public_key,
      });
      console.log(`[pagos] Vendedor ${sellerId} conectó su cuenta de Mercado Pago`);

      res.send(paginaFinal('¡Cuenta conectada!',
        'Ya puedes recibir pagos en Mercadito UM.', true));
    } catch (err) {
      console.error(`[pagos] Error en callback de OAuth: ${
        err instanceof mp.MpError ? JSON.stringify(err.detalle) : err.stack}`);
      res.status(502).send(paginaFinal('No se pudo conectar',
        'Hubo un problema al conectar tu cuenta. Inténtalo de nuevo.', false));
    }
  });

  // Estado de la conexión del vendedor (para pintar la pantalla).
  app.get('/api/payments/account', requireAuth, (req, res) => {
    const cuenta = store.getCuentaVendedor(req.user.id);
    const seller = getSeller(req.user.id);
    res.json({
      connected: Boolean(cuenta),
      canConnect: puedeVender(seller),
      connectedAt: cuenta?.connected_at || null,
      // mp_user_id no es secreto, pero tampoco aporta nada a la UI.
    });
  });

  app.delete('/api/payments/account', requireAuth, (req, res) => {
    store.desconectarVendedor(req.user.id);
    res.json({ ok: true });
  });

  // ─── 3. Guardar una tarjeta ───────────────────────────────
  //
  // `token` es un card_token de un solo uso generado EN EL CLIENTE contra
  // https://api.mercadopago.com/v1/card_tokens con la MP_PUBLIC_KEY. El
  // número de tarjeta y el CVV van del dispositivo a MP directamente: no
  // pasan por este servidor y no se guardan en ninguna parte.
  app.post('/api/payments/cards', requireAuth, async (req, res) => {
    if (!cfg.assertConfigurado(res)) return;

    const { token } = req.body || {};
    if (!token || typeof token !== 'string') {
      return res.status(400).json({ error: 'Falta el token de la tarjeta.' });
    }

    const seller = getSeller(req.user.id);
    if (!seller?.email) {
      return res.status(400).json({
        error: 'Necesitas un correo en tu perfil para guardar tarjetas.',
      });
    }

    try {
      let customerId = store.getCustomerId(req.user.id);

      if (!customerId) {
        // MP rechaza crear un Customer con un email que ya tiene uno, así
        // que se busca primero. Pasa cuando la fila local se perdió pero el
        // Customer sigue existiendo del lado de MP.
        const existente = await mp.buscarCustomerPorEmail(seller.email);
        const customer = existente || await mp.crearCustomer({
          email: seller.email,
          nombre: seller.name,
        });
        customerId = customer.id;
        store.guardarCustomerId(req.user.id, customerId);
      }

      // Endpoint: POST /v1/customers/{id}/cards — credencial de plataforma.
      const tarjeta = await mp.guardarTarjetaEnCustomer(customerId, token);

      store.guardarTarjeta(req.user.id, {
        mpCardId: tarjeta.id,
        lastFour: tarjeta.last_four_digits,
        paymentMethod: tarjeta.payment_method?.id || tarjeta.payment_method?.name,
        expMonth: tarjeta.expiration_month,
        expYear: tarjeta.expiration_year,
      });

      res.status(201).json(tarjetaPublica(store.getTarjeta(req.user.id, tarjeta.id)));
    } catch (err) {
      // Un 4xx de MP aquí casi siempre es tarjeta inválida o token ya usado:
      // merece un mensaje accionable, sin reenviar nada de MP.
      if (err instanceof mp.MpError && err.status >= 400 && err.status < 500) {
        return fallo(res, 'Guardando tarjeta (rechazo de MP)', err, {
          status: 400,
          mensaje: 'No pudimos guardar esa tarjeta. Revisa los datos e intenta de nuevo.',
        });
      }
      fallo(res, 'Guardando tarjeta', err);
    }
  });

  // ─── 4. Listar tarjetas guardadas ─────────────────────────
  app.get('/api/payments/cards', requireAuth, (req, res) => {
    res.json(store.listarTarjetas(req.user.id).map(tarjetaPublica));
  });

  // ─── 5. Eliminar una tarjeta ──────────────────────────────
  app.delete('/api/payments/cards/:cardId', requireAuth, async (req, res) => {
    if (!cfg.assertConfigurado(res)) return;

    // Pertenencia ANTES de tocar MP: el cardId viene del cliente y sin esto
    // cualquiera podría borrar la tarjeta de otra persona pasando su id.
    const tarjeta = store.getTarjeta(req.user.id, req.params.cardId);
    if (!tarjeta) return res.status(404).json({ error: 'Tarjeta no encontrada.' });

    const customerId = store.getCustomerId(req.user.id);
    try {
      if (customerId) {
        // Endpoint: DELETE /v1/customers/{id}/cards/{card_id}
        await mp.eliminarTarjetaDeCustomer(customerId, tarjeta.mp_card_id);
      }
    } catch (err) {
      // Si ya no existe en MP (404), el borrado local es correcto igual.
      if (!(err instanceof mp.MpError && err.status === 404)) {
        return fallo(res, 'Eliminando tarjeta en MP', err);
      }
    }

    store.borrarTarjeta(req.user.id, tarjeta.mp_card_id);
    res.json({ ok: true });
  });

  // ─── Órdenes ──────────────────────────────────────────────
  //
  // Una orden es SIEMPRE de un solo vendedor: el split de MP cobra con el
  // token de un vendedor concreto. Un carrito con productos de dos negocios
  // produce dos órdenes y dos cobros.
  app.post('/api/orders', requireAuth, (req, res) => {
    const { productId, quantity, fromCart } = req.body || {};

    let lineas;
    if (fromCart) {
      lineas = db.getCartItems(req.user.id).map(i => ({
        productId: i.productId,
        quantity: i.quantity,
      }));
      if (lineas.length === 0) {
        return res.status(400).json({ error: 'Tu carrito está vacío.' });
      }
    } else {
      const cantidad = Number(quantity ?? 1);
      if (!productId || !Number.isInteger(cantidad) || cantidad < 1) {
        return res.status(400).json({ error: 'productId y quantity válidos son requeridos.' });
      }
      lineas = [{ productId, quantity: cantidad }];
    }

    // Agrupar por vendedor, leyendo precio y título de la base de datos.
    // El precio NUNCA viene del cliente.
    const porVendedor = new Map();
    for (const linea of lineas) {
      const producto = db.getProductById(linea.productId);
      if (!producto) {
        return res.status(404).json({ error: 'Uno de los productos ya no está disponible.' });
      }
      if (!producto.seller) {
        return res.status(409).json({ error: 'Uno de los productos no tiene vendedor asignado.' });
      }
      // `rowToProduct` (database.js) devuelve el precio ya numérico en
      // `price` — la columna `priceNum` de SQLite no se expone con ese
      // nombre en el objeto de producto.
      const precio = Number(producto.price);
      if (!Number.isFinite(precio) || precio <= 0) {
        return res.status(409).json({
          error: `"${producto.title}" no tiene un precio válido para comprarse en la app.`,
        });
      }
      if (producto.seller === req.user.id) {
        return res.status(400).json({ error: 'No puedes comprarte a ti mismo.' });
      }

      if (!porVendedor.has(producto.seller)) porVendedor.set(producto.seller, []);
      porVendedor.get(producto.seller).push({
        productId: producto.id,
        quantity: linea.quantity,
        unitPrice: precio,
        title: producto.title,
      });
    }

    const creadas = [];
    for (const [vendorId, items] of porVendedor) {
      const total = redondear2(items.reduce((s, i) => s + i.unitPrice * i.quantity, 0));
      let comision;
      try {
        comision = calcularComision(total);
      } catch (err) {
        console.error(`[pagos] No se pudo calcular la comisión: ${err.message}`);
        return res.status(503).json({ error: MENSAJE_GENERICO });
      }

      creadas.push(store.crearOrden({
        id: `ord_${randomUUID()}`,
        buyerId: req.user.id,
        vendorId,
        amount: total,
        applicationFee: comision,
        currency: cfg.config.moneda,
        origin: fromCart ? 'cart' : 'direct',
        items,
      }));
    }

    res.status(201).json(creadas.map(ordenPublica));
  });

  app.get('/api/orders', requireAuth, (req, res) => {
    const rol = req.query.role === 'vendor' ? 'vendor' : 'buyer';
    const ordenes = rol === 'vendor'
      ? store.listarOrdenesDeVendedor(req.user.id)
      : store.listarOrdenesDeComprador(req.user.id);
    res.json(ordenes.map(ordenPublica));
  });

  app.get('/api/orders/:id', requireAuth, (req, res) => {
    const orden = store.getOrden(req.user.id, req.params.id);
    if (!orden) return res.status(404).json({ error: 'Orden no encontrada.' });
    res.json(ordenPublica(orden));
  });

  // ─── 6. Checkout ──────────────────────────────────────────
  app.post('/api/payments/checkout', requireAuth, async (req, res) => {
    if (!cfg.assertConfigurado(res)) return;

    const { order_id: orderId, card_token: cardToken, installments,
            payment_method_id: paymentMethodId, issuer_id: issuerId } = req.body || {};

    if (!orderId || !cardToken) {
      return res.status(400).json({ error: 'Faltan datos para procesar el pago.' });
    }

    // La orden se busca filtrando por comprador: si es de otra persona,
    // simplemente no aparece.
    const orden = store.getOrden(req.user.id, String(orderId));
    if (!orden) return res.status(404).json({ error: 'Orden no encontrada.' });
    if (orden.status !== 'pending' || orden.payment_status === 'approved') {
      return res.status(409).json({ error: 'Esta orden ya fue procesada.' });
    }

    const comprador = getSeller(req.user.id);
    if (!comprador?.email) {
      return res.status(400).json({
        error: 'Necesitas un correo en tu perfil para pagar en la app.',
      });
    }

    // El vendedor tiene que poder recibir dinero ANTES de intentar cobrar:
    // si no, MP devuelve un error opaco y el comprador no entiende nada.
    const vendedor = getSeller(orden.vendor_id);
    const cuenta = store.getCuentaVendedor(orden.vendor_id);
    if (!cuenta) {
      return res.status(409).json({
        error: `${vendedor?.name || 'Este vendedor'} todavía no puede recibir pagos en la app. `
             + 'Contáctalo por chat para acordar otra forma de pago.',
      });
    }

    // El total se RECALCULA desde order_items. Nunca se usa un monto que
    // venga en el body: sería trivial pagar $1 por una orden de $1000.
    const total = redondear2(
      orden.items.reduce((s, i) => s + i.unit_price * i.quantity, 0),
    );
    if (total !== redondear2(orden.amount)) {
      console.error(`[pagos] Orden ${orden.id}: total de items (${total}) `
        + `!= amount guardado (${orden.amount})`);
      return res.status(409).json({ error: MENSAJE_GENERICO });
    }

    let comision;
    try {
      comision = calcularComision(total);
    } catch (err) {
      console.error(`[pagos] Comisión inválida en ${orden.id}: ${err.message}`);
      return res.status(503).json({ error: MENSAJE_GENERICO });
    }

    try {
      const tokenVendedor = await tokenVigenteDeVendedor(orden.vendor_id);
      if (!tokenVendedor?.accessToken) {
        return res.status(409).json({
          error: `${vendedor?.name || 'Este vendedor'} necesita reconectar su cuenta de pagos.`,
        });
      }

      const descripcion = orden.items.length === 1
        ? String(orden.items[0].title_snapshot || 'Compra en Mercadito UM').slice(0, 60)
        : `Compra en Mercadito UM (${orden.items.length} productos)`;

      // Endpoint: POST /v1/payments con el ACCESS TOKEN DEL VENDEDOR.
      // `application_fee` es la comisión que retiene la plataforma; el resto
      // entra a la cuenta de Mercado Pago del vendedor. Ese es el split.
      const pago = await mp.crearPago({
        accessTokenVendedor: tokenVendedor.accessToken,
        // Idempotencia atada a la orden: si la red se cae tras enviar el
        // cobro y la app reintenta, MP devuelve el mismo pago en vez de
        // cobrarle dos veces al comprador.
        idempotencyKey: `order-${orden.id}`,
        pago: {
          transaction_amount: total,
          token: cardToken,
          description: descripcion,
          installments: Number(installments) > 0 ? Number(installments) : 1,
          payment_method_id: paymentMethodId || undefined,
          issuer_id: issuerId || undefined,
          payer: { email: comprador.email },
          // Nuestro id de orden viaja a MP para poder reconciliar desde el
          // webhook aunque se pierda la respuesta de esta llamada.
          external_reference: orden.id,
          application_fee: comision,
          notification_url: `${cfg.config.appPublicUrl}/api/payments/webhook`,
          statement_descriptor: 'MERCADITOUM',
        },
      });

      store.actualizarPagoDeOrden(orden.id, {
        mpPaymentId: pago.id,
        paymentStatus: pago.status,
      });

      // Si el pago se aprobó y la orden venía del carrito, esos productos
      // salen del carrito.
      if (pago.status === 'approved' && orden.origin === 'cart') {
        db.clearCartItems(req.user.id, orden.items.map(i => i.product_id));
      }

      console.log(`[pagos] Orden ${orden.id}: pago ${pago.id} → ${pago.status}`);

      // `status_detail` de MP es un código estable ('cc_rejected_bad_filled_
      // security_code'), no un texto libre: se manda para que la app pueda
      // dar un mensaje útil. La traducción a español vive en el cliente.
      res.json({
        orderId: orden.id,
        status: pago.status,
        statusDetail: pago.status_detail,
        amount: total,
      });
    } catch (err) {
      if (err instanceof mp.MpError && err.status >= 400 && err.status < 500) {
        return fallo(res, `Checkout de la orden ${orden.id} (rechazo de MP)`, err, {
          status: 400,
          mensaje: 'No se pudo procesar el pago con esa tarjeta. Intenta con otra.',
        });
      }
      fallo(res, `Checkout de la orden ${orden.id}`, err);
    }
  });

  // ─── 7. Webhook ───────────────────────────────────────────
  //
  // Sin `requireAuth`: quien llama es Mercado Pago, no un usuario. Lo que
  // autentica la petición es la firma.
  //
  // No hace falta el body crudo (ni un `express.raw` que chocaría con el
  // `express.json()` global): MP firma un manifest construido con `data.id`,
  // `x-request-id` y `ts` — el cuerpo no entra en la firma.
  app.post('/api/payments/webhook', (req, res) => {
    const { valida, motivo } = validarFirma(req);
    if (!valida) {
      console.warn(`[pagos] Webhook rechazado: ${motivo}`);
      // 401 y no 200: si la firma no valida, no es MP quien llama.
      return res.status(401).json({ error: 'Firma inválida' });
    }

    const cuerpo = req.body && typeof req.body === 'object' ? req.body : {};

    const topic = cuerpo.type || cuerpo.topic || req.query.type || req.query.topic;
    const paymentId = cuerpo.data?.id || req.query['data.id'] || req.query.id;

    if (topic !== 'payment' || !paymentId) {
      // Otros temas (merchant_order, etc.) no se procesan todavía, pero se
      // responde 200 para que MP no los reintente indefinidamente.
      return res.status(200).json({ ok: true, ignored: true });
    }

    // El id del evento distingue ENTREGAS, no pagos: el mismo pago genera
    // varios eventos legítimos (pending → approved) y hay que procesarlos
    // todos. Lo que no puede repetirse es la misma entrega.
    const eventId = String(cuerpo.id || req.headers['x-request-id'] || `${paymentId}-${Date.now()}`);
    const esNuevo = store.registrarEventoWebhook({
      eventId,
      topic: String(topic),
      resourceId: String(paymentId),
    });

    // Se responde YA. MP corta a los pocos segundos y reintenta; el trabajo
    // real (consultar el pago, actualizar la orden) va después de responder.
    res.status(200).json({ ok: true });

    if (!esNuevo) {
      console.log(`[pagos] Webhook ${eventId} ya procesado, se ignora`);
      return;
    }
    // Deliberadamente sin await: la respuesta ya salió.
    procesarEvento({ eventId, paymentId: String(paymentId) });
  });
}

module.exports = { register };
