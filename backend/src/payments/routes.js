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

const { randomUUID, createHash } = require('crypto');
const rateLimit = require('express-rate-limit');

const { requireAuth } = require('../auth');
const db = require('../database');
const cfg = require('./config');
const store = require('./store');
const mp = require('./mpClient');
const metodos = require('./methods');
const conexion = require('./connection');
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

/**
 * ¿Este vendedor puede conectar una cuenta de cobros?
 *
 * La condición NO es "ya está verificado", y no puede serlo: conectar Mercado
 * Pago es requisito para verificarse, así que exigir la verificación para
 * conectar deja la regla mordiéndose la cola y a nadie le sale ninguna de las
 * dos. Lo que se exige es lo que de verdad protege el endpoint: que la
 * persona haya DEMOSTRADO SU IDENTIDAD con el OTP de su correo institucional
 * o su teléfono (`verificaciones.identidad_confirmada_en`). Quien ya está
 * verificado lo cumple por definición.
 *
 * Tampoco se filtra ya por tipo de cuenta: 'particular' también debe conectar
 * para verificarse, y dejarlo fuera de la lista lo condenaba a no poder
 * verificarse nunca.
 */
function puedeVender(seller) {
  if (!seller) return false;
  if (seller.verified) return true;
  const verificacion = db.getDb()
    .prepare('SELECT identidad_confirmada_en FROM verificaciones WHERE usuario_id = ?')
    .get(seller.id);
  return Boolean(verificacion?.identidad_confirmada_en);
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

/**
 * Tope de intentos por COMPRADOR sobre un endpoint que mueve dinero.
 *
 * Por comprador y no por IP a propósito: en la red del campus todo el mundo
 * sale por la misma IP, así que un límite por IP dejaría sin comprar a media
 * universidad en cuanto una persona se pasara. El principal autenticado es
 * la unidad correcta — y como estos endpoints van detrás de `requireAuth`,
 * `req.user.id` siempre está.
 *
 * Debe montarse SIEMPRE después de requireAuth: sin `req.user` no hay clave.
 */
function limitePorComprador({ minutos, max }) {
  return rateLimit({
    windowMs: minutos * 60 * 1000,
    limit: max,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    keyGenerator: req => req.user.id,
    message: {
      error: 'Demasiados intentos de pago. Espera unos minutos antes de volver a intentarlo.',
    },
  });
}

/**
 * Identifica un intento de cobro concreto sin exponer el card_token, que es
 * de un solo uso pero sensible igual. Un prefijo del SHA-256 basta: solo
 * tiene que distinguir dos tarjetas sobre la misma orden.
 */
function huellaDelIntento(cardToken) {
  return createHash('sha256').update(String(cardToken)).digest('hex').slice(0, 32);
}

/**
 * Avisa a las dos partes de que esa orden no se puede cobrar con tarjeta.
 * Son dos mensajes distintos porque las acciones son distintas: el comprador
 * tiene que elegir otro método, el vendedor tiene que reconectar su cuenta
 * (a ese ya lo avisó `conexion.desconectar`; aquí se le da el contexto de la
 * venta concreta que se quedó a medias).
 */
function avisarPagoNoDisponible(orden, vendedor) {
  db.createNotification(
    `ntf_${randomUUID()}`, orden.buyer_id, 'order_requires_other_method',
    'Tu pago con tarjeta no se pudo procesar',
    `${vendedor?.name || 'El vendedor'} no puede cobrar con tarjeta en este momento. `
      + 'Contáctalo por chat para acordar otra forma de pago.',
    { orderId: orden.id, vendorId: orden.vendor_id },
  );
  db.createNotification(
    `ntf_${randomUUID()}`, orden.vendor_id, 'order_requires_other_method',
    'Una venta se quedó sin poder cobrarse',
    'Un comprador intentó pagarte con tarjeta y tu cuenta de pagos no está conectada. '
      + 'Reconéctala desde tu perfil para no perder más ventas.',
    { orderId: orden.id, buyerId: orden.buyer_id },
  );
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
    paymentMethod: orden.payment_method,
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
        error: 'Antes de conectar tu cuenta de cobros tienes que confirmar el código '
          + 'que te enviamos por correo o SMS.',
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
    // Paleta y tipografía espejo de `website/app/globals.css` (que a su vez
    // espeja `lib/app_theme.dart`), para que esta pantalla combine con la
    // landing aunque no comparta build system con ella.
    const iconoExito = `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#a84b37" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12.5l5 5L20 6.5"/></svg>`;
    const iconoError = `<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#3d5c70" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6 6l12 12M18 6L6 18"/></svg>`;

    const paginaFinal = (titulo, texto, ok) => `<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${titulo}</title>
<style>
 *{box-sizing:border-box}
 body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,system-ui,sans-serif;
      background:#fafaf8;color:#1b1a16;
      display:flex;min-height:100vh;align-items:center;justify-content:center;
      margin:0;padding:24px;line-height:1.55}
 .tarjeta{width:100%;max-width:380px;background:#fff;border-radius:20px;
      box-shadow:0 4px 24px rgba(27,26,22,.08);padding:40px 28px;text-align:center}
 .icono{width:56px;height:56px;border-radius:999px;display:flex;
      align-items:center;justify-content:center;margin:0 auto 20px;
      background:${ok ? 'rgba(168,75,55,.12)' : 'rgba(61,92,112,.1)'}}
 h1{font-size:21px;font-weight:700;letter-spacing:-.01em;color:#2b4150;margin:0 0 10px}
 p{font-size:14px;color:#6e6b64;margin:0 0 28px}
 a{display:inline-block;width:100%;background:#a84b37;color:#fff;text-decoration:none;
   padding:14px 24px;border-radius:12px;font-weight:600;font-size:15px}
 a:active{background:#8f3f2e}
</style></head><body>
<div class="tarjeta">
<div class="icono">${ok ? iconoExito : iconoError}</div>
<h1>${titulo}</h1><p>${texto}</p>
<a href="${cfg.config.appDeepLinkScheme}://payments/connected?ok=${ok ? '1' : '0'}">Volver a Mercadito UM</a>
</div>
</body></html>`;

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

      // Conectar la cuenta puede ser lo ÚNICO que le faltaba a una
      // verificación. Se cierra aquí, en el punto por el que pasan todas las
      // conexiones, y no en la pantalla que la inició: se conecta desde el
      // formulario de verificación, desde "Editar perfil" y desde la pantalla
      // de cobros, y solo uno de esos tres sitios sabe reintentar.
      //
      // Un fallo aquí no puede tumbar la conexión, que ya está guardada: el
      // usuario se quedaría sin cuenta conectada Y sin verificar.
      try {
        require('../routes/verificacion').completarVerificacionPendientePorPagos(sellerId);
      } catch (err) {
        console.error(`[pagos] No se pudo cerrar la verificación de ${sellerId}: ${err.stack}`);
      }

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
    // Pasa por conexion.desconectar y no por store: desconectar implica
    // además retirar 'tarjeta' de sus métodos y borrar las tarjetas que ya
    // no se pueden cobrar. Hacerlo "a mano" aquí es cómo se queda un
    // vendedor anunciando un método muerto.
    conexion.desconectar(req.user.id, { motivo: 'El vendedor la desconectó', por: 'user' });
    res.json({ ok: true });
  });

  // ─── Validación bajo demanda del token del vendedor ───────
  //
  // Red de seguridad para cuando el webhook de revocación no llegó. La app
  // la llama al abrir la pantalla de pagos del vendedor, para que vea su
  // estado real y no uno que quedó viejo hace semanas.
  app.post('/api/payments/account/validate', requireAuth, async (req, res) => {
    if (!cfg.assertConfigurado(res)) return;
    const resultado = await conexion.validarConexion(req.user.id);
    res.json({ connected: resultado.conectado, reason: resultado.motivo || null });
  });

  // ─── Métodos de pago disponibles de un vendedor ───────────
  //
  // Lo consume el checkout para decidir qué ofrecerle al comprador. Se
  // evalúa EN VIVO en cada llamada y no se cachea: entre que el comprador
  // abrió la pantalla y paga, el vendedor pudo revocar la autorización desde
  // su panel de Mercado Pago.
  app.get('/api/payments/vendors/:vendorId/methods', requireAuth, (req, res) => {
    const vendorId = String(req.params.vendorId);
    if (!getSeller(vendorId)) {
      return res.status(404).json({ error: 'Vendedor no encontrado.' });
    }
    res.json(metodos.metodosDeVendedor(vendorId));
  });

  // ─── 3. Guardar una tarjeta (con un vendedor concreto) ────
  //
  // La ruta lleva el vendedor en el path y no en el body a propósito: en
  // este modelo una tarjeta NO es del comprador a secas, es del comprador
  // CON un vendedor. Que el ámbito esté en la URL hace imposible escribir un
  // handler que se olvide de él.
  //
  // `token` es un card_token de un solo uso generado EN EL CLIENTE contra
  // https://api.mercadopago.com/v1/card_tokens con la PUBLIC KEY DEL
  // VENDEDOR (la sirve GET /api/sellers/:id/payment-methods). El número de
  // tarjeta y el CVV van del dispositivo a MP directamente: no pasan por
  // este servidor y no se guardan en ninguna parte.
  //
  // Mismo riesgo que el checkout: asociar una tarjeta la valida contra MP, y
  // la respuesta distingue una tarjeta buena de una mala. Sirve igual de bien
  // para probar números robados, y aquí ni siquiera hace falta una orden.
  app.post('/api/payments/vendors/:vendorId/cards', requireAuth,
    limitePorComprador({ minutos: 60, max: 10 }), async (req, res) => {
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

    const vendorId = String(req.params.vendorId);
    const vendedor = getSeller(vendorId);

    try {
      // El Customer se crea DENTRO de la cuenta del vendedor, así que hace
      // falta su token antes de tocar nada.
      const tokenVendedor = await tokenVigenteDeVendedor(vendorId);
      if (!tokenVendedor?.accessToken) {
        return res.status(409).json({
          error: `${vendedor?.name || 'Este vendedor'} no puede recibir pagos con tarjeta ahora mismo.`,
        });
      }

      let customerId = store.getCustomerId(req.user.id, vendorId);

      if (!customerId) {
        // MP rechaza crear un Customer con un email que ya tiene uno en esa
        // cuenta, así que se busca primero. Pasa cuando la fila local se
        // perdió pero el Customer sigue existiendo del lado de MP.
        const existente = await mp.buscarCustomerPorEmail(seller.email, tokenVendedor.accessToken);
        const customer = existente || await mp.crearCustomer(
          { email: seller.email, nombre: seller.name },
          tokenVendedor.accessToken,
        );
        customerId = customer.id;
        store.guardarCustomerId(req.user.id, vendorId, customerId);
      }

      const tarjeta = await mp.guardarTarjetaEnCustomer(
        customerId, token, tokenVendedor.accessToken,
      );

      store.guardarTarjeta(req.user.id, vendorId, {
        mpCardId: tarjeta.id,
        lastFour: tarjeta.last_four_digits,
        paymentMethod: tarjeta.payment_method?.id || tarjeta.payment_method?.name,
        expMonth: tarjeta.expiration_month,
        expYear: tarjeta.expiration_year,
      });

      res.status(201).json(
        tarjetaPublica(store.getTarjeta(req.user.id, vendorId, tarjeta.id)),
      );
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

  // ─── 4. Listar tarjetas guardadas con un vendedor ─────────
  app.get('/api/payments/vendors/:vendorId/cards', requireAuth, (req, res) => {
    res.json(
      store.listarTarjetas(req.user.id, String(req.params.vendorId)).map(tarjetaPublica),
    );
  });

  // ─── 5. Eliminar una tarjeta ──────────────────────────────
  app.delete('/api/payments/vendors/:vendorId/cards/:cardId', requireAuth, async (req, res) => {
    if (!cfg.assertConfigurado(res)) return;

    const vendorId = String(req.params.vendorId);

    // Pertenencia ANTES de tocar MP: el cardId viene del cliente y sin esto
    // cualquiera podría borrar la tarjeta de otra persona pasando su id.
    const tarjeta = store.getTarjeta(req.user.id, vendorId, req.params.cardId);
    if (!tarjeta) return res.status(404).json({ error: 'Tarjeta no encontrada.' });

    const customerId = store.getCustomerId(req.user.id, vendorId);
    try {
      if (customerId) {
        // Si el vendedor ya no está conectado no hay token con el que borrar
        // en MP. El borrado local se hace igual: la tarjeta ya es inútil.
        const tokenVendedor = await tokenVigenteDeVendedor(vendorId);
        if (tokenVendedor?.accessToken) {
          await mp.eliminarTarjetaDeCustomer(
            customerId, tarjeta.mp_card_id, tokenVendedor.accessToken,
          );
        }
      }
    } catch (err) {
      // Si ya no existe en MP (404), el borrado local es correcto igual.
      if (!(err instanceof mp.MpError && err.status === 404)) {
        return fallo(res, 'Eliminando tarjeta en MP', err);
      }
    }

    store.borrarTarjeta(req.user.id, vendorId, tarjeta.mp_card_id);
    res.json({ ok: true });
  });

  // ─── Órdenes ──────────────────────────────────────────────
  //
  // Una orden es SIEMPRE de un solo vendedor: el split de MP cobra con el
  // token de un vendedor concreto. Un carrito con productos de dos negocios
  // produce dos órdenes y dos cobros.
  app.post('/api/orders', requireAuth, (req, res) => {
    const { productId, quantity, fromCart, paymentMethod } = req.body || {};

    // Cómo se acordó pagar. Opcional por compatibilidad con clientes que no
    // lo mandan; cuando viene, se valida contra el vendedor ANTES de crear
    // nada. No basta con que la app haya consultado /methods: ese endpoint
    // informa, no autoriza, y nada impide llamar a este directamente.
    const metodoSolicitado = paymentMethod == null ? null : String(paymentMethod);

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

    // Se valida el método contra TODOS los vendedores antes de crear
    // ninguna orden: un carrito de dos negocios no puede acabar con la
    // primera orden creada y la segunda rechazada.
    if (metodoSolicitado) {
      for (const vendorId of porVendedor.keys()) {
        const disponibles = metodos.metodosDeVendedor(vendorId);
        const elegido = disponibles.methods.find(m => m.id === metodoSolicitado);
        if (!elegido || !elegido.available) {
          const vendedor = getSeller(vendorId);
          return res.status(409).json({
            error: elegido?.unavailableReason
              || `${vendedor?.name || 'Este vendedor'} no acepta ese método de pago.`,
            vendorId,
          });
        }
      }
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
        paymentMethod: metodoSolicitado,
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
  // Poder reintentar tras un rechazo es correcto para el comprador, pero es
  // también el mecanismo del "card testing": probar tarjetas robadas una tras
  // otra contra un endpoint que responde si el cargo pasó. 10 intentos por
  // cuarto de hora es holgado para una persona que se equivoca de tarjeta y
  // ridículo para quien valida números en lote.
  app.post('/api/payments/checkout', requireAuth,
    limitePorComprador({ minutos: 15, max: 10 }), async (req, res) => {
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
    // Un intento anterior solo deja reintentar si murió sin cobrar (una
    // tarjeta rechazada). No basta con mirar `orden.status`: un pago que MP
    // dejó 'in_process' deja la orden en 'pending', y cobrar otra vez ahí
    // sería un cargo duplicado real. El criterio vive en el store, junto a
    // los conjuntos de estados.
    if (!store.admiteNuevoIntentoDePago(orden)) {
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

    // Última comprobación antes de mover dinero: que la autorización del
    // vendedor siga viva AHORA. Entre que se creó la orden y este momento
    // pudo revocarla desde su panel de MP, y el webhook pudo no haber
    // llegado. Sin esto la llamada de cobro falla con un error opaco y la
    // orden se queda en 'pending' sin que nadie sepa qué hacer con ella.
    const conectado = await conexion.validarConexion(orden.vendor_id);
    if (!conectado.conectado) {
      store.marcarRequiereOtroMetodo(orden.id);
      avisarPagoNoDisponible(orden, vendedor);
      return res.status(409).json({
        error: `${vendedor?.name || 'Este vendedor'} ya no puede cobrar con tarjeta. `
             + 'Contáctalo por chat para acordar otra forma de pago.',
        orderStatus: 'requires_other_method',
      });
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
        // Idempotencia atada al INTENTO (orden + tarjeta), no solo a la
        // orden. Si la red se cae tras enviar el cobro y la app reenvía la
        // misma petición, la clave se repite y MP devuelve el mismo pago en
        // vez de cobrarle dos veces al comprador. Pero un reintento
        // deliberado con OTRA tarjeta tras un rechazo es un cobro distinto:
        // con la clave atada solo a la orden, MP devolvería el pago cacheado
        // y el comprador vería otra vez el rechazo de la tarjeta que ya
        // descartó, sin que la nueva llegara a intentarse nunca.
        //
        // Va el hash, no el card_token: es un dato sensible y no tiene por
        // qué viajar en una cabecera ni acabar en un log de MP.
        idempotencyKey: `order-${orden.id}-${huellaDelIntento(cardToken)}`,
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
      // Un 401/403 aquí no es "tarjeta rechazada": es que el token del
      // vendedor dejó de valer entre la validación de arriba y este cobro.
      // La ventana es corta pero existe, y el resultado sin esto sería el
      // mismo agujero: orden en 'pending' que nadie sabe cómo resolver.
      if (err instanceof mp.MpError && (err.status === 401 || err.status === 403)) {
        conexion.desconectar(orden.vendor_id, {
          motivo: 'Mercado Pago rechazó el token del vendedor al cobrar',
          por: 'token_check',
        });
        store.marcarRequiereOtroMetodo(orden.id);
        avisarPagoNoDisponible(orden, vendedor);
        return fallo(res, `Checkout de la orden ${orden.id} (token del vendedor revocado)`, err, {
          status: 409,
          mensaje: `${vendedor?.name || 'Este vendedor'} ya no puede cobrar con tarjeta. `
                 + 'Contáctalo por chat para acordar otra forma de pago.',
        });
      }
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

    // ─── Revocación de la autorización del vendedor ─────────
    //
    // Cuando un vendedor quita la aplicación desde su panel de Mercado Pago,
    // MP avisa por aquí. El identificador que trae es SU user_id, no el
    // nuestro, así que hay que traducirlo.
    //
    // Se exige una señal EXPLÍCITA de desautorización, y no basta con que el
    // topic sea 'application' o 'mp-connect'. Por esos topics también llegan
    // eventos que no son revocaciones (una autorización nueva, sin ir más
    // lejos), y equivocarse en esta dirección le corta el cobro a un vendedor
    // que no hizo nada.
    //
    // Quedarse corto es mucho más barato: si MP cambia el nombre del evento y
    // este `if` deja de reconocerlo, la validación del token antes de cada
    // cobro detecta la revocación igual. Al revés no hay red que lo salve.
    const accion = String(cuerpo.action || '').toLowerCase();
    const esRevocacion = accion.includes('deauthorized')
      || accion.includes('unauthorized')
      || accion === 'revoked';

    if (esRevocacion) {
      const mpUserId = cuerpo.user_id || cuerpo.data?.id || req.query['data.id'];
      res.status(200).json({ ok: true });

      if (mpUserId) {
        const cuenta = store.getVendedorPorMpUserId(mpUserId);
        if (cuenta) {
          conexion.desconectar(cuenta.seller_id, {
            motivo: 'El vendedor revocó la autorización desde Mercado Pago',
            por: 'webhook',
          });
        } else {
          console.warn(`[pagos] Revocación de un mp_user_id sin cuenta local (${mpUserId})`);
        }
      }
      return;
    }

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

    // `esNuevo` solo dice si esta ENTREGA ya se había visto, no si se
    // procesó con éxito: un intento anterior pudo haber reventado a medias
    // (obtenerPago caído, timeout, etc.) sin llegar a marcarse como
    // procesado. Descartar el reintento en ese caso perdería el evento para
    // siempre, así que el criterio real para ignorar es "ya se procesó",
    // nunca "ya se recibió".
    if (!esNuevo && store.eventoFueProcesado(eventId)) {
      console.log(`[pagos] Webhook ${eventId} ya procesado, se ignora`);
      return;
    }
    // Deliberadamente sin await: la respuesta ya salió.
    procesarEvento({ eventId, paymentId: String(paymentId) });
  });
}

module.exports = { register };
