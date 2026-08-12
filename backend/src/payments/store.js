/**
 * Acceso a datos de todo lo relacionado con pagos.
 *
 * Todas las consultas que tocan un recurso de usuario reciben el `sellerId`
 * (el `sub` del JWT) y filtran por él en el propio SQL. Es deliberado: la
 * comprobación de pertenencia no puede quedar como un `if` que alguien
 * olvide en una ruta — si el WHERE no encuentra la fila, la operación
 * simplemente no ocurre.
 *
 * Los tokens de vendedor entran y salen de aquí CIFRADOS; el descifrado es
 * explícito en `getCuentaVendedorConToken()` para que se vea en el código
 * dónde existe el token en claro.
 */

const { randomUUID } = require('crypto');
const db = require('../database');
const { cifrar, descifrar } = require('./crypto');

const ahora = () => new Date().toISOString();

// ─── OAuth: state anti-CSRF ─────────────────────────────────

function crearOAuthState(sellerId) {
  const state = randomUUID();
  db.getDb()
    .prepare('INSERT INTO payment_oauth_states (state, seller_id, created_at) VALUES (?, ?, ?)')
    .run(state, sellerId, ahora());
  return state;
}

/**
 * Consume un `state`: lo valida y lo marca como usado en la misma operación.
 * Devuelve el seller_id, o null si no existe, ya se usó o caducó (15 min).
 * Un state de un solo uso impide reproducir un callback capturado.
 */
function consumirOAuthState(state) {
  const fila = db.getDb()
    .prepare('SELECT * FROM payment_oauth_states WHERE state = ? AND used_at IS NULL')
    .get(state);
  if (!fila) return null;

  const edadMin = (Date.now() - new Date(fila.created_at).getTime()) / 60000;
  if (!Number.isFinite(edadMin) || edadMin > 15) return null;

  db.getDb().prepare('UPDATE payment_oauth_states SET used_at = ? WHERE state = ?')
    .run(ahora(), state);
  return fila.seller_id;
}

function limpiarOAuthStatesViejos() {
  db.getDb()
    .prepare("DELETE FROM payment_oauth_states WHERE created_at < datetime('now', '-1 day')")
    .run();
}

// ─── Cuenta de Mercado Pago del vendedor ────────────────────

function guardarCuentaVendedor(sellerId, { mpUserId, accessToken, refreshToken, expiresIn, publicKey }) {
  const expiraEn = Number.isFinite(expiresIn)
    ? new Date(Date.now() + expiresIn * 1000).toISOString()
    : null;

  db.getDb().prepare(`
    INSERT INTO vendor_payment_accounts
      (seller_id, mp_user_id, mp_access_token_enc, mp_refresh_token_enc,
       mp_token_expires_at, mp_public_key, connected_at, revoked_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, NULL)
    ON CONFLICT(seller_id) DO UPDATE SET
      mp_user_id = excluded.mp_user_id,
      mp_access_token_enc = excluded.mp_access_token_enc,
      mp_refresh_token_enc = excluded.mp_refresh_token_enc,
      mp_token_expires_at = excluded.mp_token_expires_at,
      mp_public_key = excluded.mp_public_key,
      connected_at = excluded.connected_at,
      revoked_at = NULL
  `).run(
    sellerId,
    String(mpUserId),
    cifrar(accessToken),
    refreshToken ? cifrar(refreshToken) : null,
    expiraEn,
    publicKey || null,
    ahora(),
  );
}

/** Fila cruda (tokens aún cifrados). Para saber si está conectado. */
function getCuentaVendedor(sellerId) {
  return db.getDb()
    .prepare('SELECT * FROM vendor_payment_accounts WHERE seller_id = ? AND revoked_at IS NULL')
    .get(sellerId) || null;
}

/**
 * Cuenta del vendedor con los tokens YA DESCIFRADOS. Único sitio donde el
 * token existe en claro en el proceso; el valor devuelto no debe guardarse
 * en ninguna estructura de larga vida ni loguearse.
 */
function getCuentaVendedorConToken(sellerId) {
  const fila = getCuentaVendedor(sellerId);
  if (!fila) return null;
  return {
    ...fila,
    accessToken: descifrar(fila.mp_access_token_enc),
    refreshToken: descifrar(fila.mp_refresh_token_enc),
  };
}

function actualizarTokensVendedor(sellerId, { accessToken, refreshToken, expiresIn }) {
  const expiraEn = Number.isFinite(expiresIn)
    ? new Date(Date.now() + expiresIn * 1000).toISOString()
    : null;
  db.getDb().prepare(`
    UPDATE vendor_payment_accounts
    SET mp_access_token_enc = ?, mp_refresh_token_enc = COALESCE(?, mp_refresh_token_enc),
        mp_token_expires_at = ?
    WHERE seller_id = ?
  `).run(cifrar(accessToken), refreshToken ? cifrar(refreshToken) : null, expiraEn, sellerId);
}

function desconectarVendedor(sellerId) {
  db.getDb()
    .prepare('UPDATE vendor_payment_accounts SET revoked_at = ? WHERE seller_id = ?')
    .run(ahora(), sellerId);
}

// ─── Customer y tarjetas del comprador ──────────────────────

function getCustomerId(sellerId) {
  const fila = db.getDb()
    .prepare('SELECT mp_customer_id FROM buyer_mp_customers WHERE seller_id = ?')
    .get(sellerId);
  return fila ? fila.mp_customer_id : null;
}

function guardarCustomerId(sellerId, mpCustomerId) {
  db.getDb().prepare(`
    INSERT INTO buyer_mp_customers (seller_id, mp_customer_id, created_at)
    VALUES (?, ?, ?)
    ON CONFLICT(seller_id) DO UPDATE SET mp_customer_id = excluded.mp_customer_id
  `).run(sellerId, mpCustomerId, ahora());
}

function guardarTarjeta(sellerId, tarjeta) {
  db.getDb().prepare(`
    INSERT INTO saved_cards
      (seller_id, mp_card_id, last_four_digits, payment_method,
       expiration_month, expiration_year, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(seller_id, mp_card_id) DO UPDATE SET
      last_four_digits = excluded.last_four_digits,
      payment_method = excluded.payment_method,
      expiration_month = excluded.expiration_month,
      expiration_year = excluded.expiration_year
  `).run(
    sellerId,
    tarjeta.mpCardId,
    tarjeta.lastFour || null,
    tarjeta.paymentMethod || null,
    tarjeta.expMonth || null,
    tarjeta.expYear || null,
    ahora(),
  );
}

function listarTarjetas(sellerId) {
  return db.getDb()
    .prepare('SELECT * FROM saved_cards WHERE seller_id = ? ORDER BY created_at DESC')
    .all(sellerId);
}

/** null si la tarjeta no existe O no es de este usuario. */
function getTarjeta(sellerId, mpCardId) {
  return db.getDb()
    .prepare('SELECT * FROM saved_cards WHERE seller_id = ? AND mp_card_id = ?')
    .get(sellerId, mpCardId) || null;
}

function borrarTarjeta(sellerId, mpCardId) {
  return db.getDb()
    .prepare('DELETE FROM saved_cards WHERE seller_id = ? AND mp_card_id = ?')
    .run(sellerId, mpCardId).changes > 0;
}

// ─── Órdenes ────────────────────────────────────────────────

function crearOrden({ id, buyerId, vendorId, amount, applicationFee, currency, origin, items }) {
  const crear = db.getDb().transaction(() => {
    db.getDb().prepare(`
      INSERT INTO orders
        (id, buyer_id, vendor_id, amount, application_fee, currency,
         status, payment_status, origin, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 'pending', NULL, ?, ?, ?)
    `).run(id, buyerId, vendorId, amount, applicationFee, currency, origin, ahora(), ahora());

    const insItem = db.getDb().prepare(`
      INSERT INTO order_items (order_id, product_id, quantity, unit_price, title_snapshot)
      VALUES (?, ?, ?, ?, ?)
    `);
    for (const it of items) {
      insItem.run(id, it.productId, it.quantity, it.unitPrice, it.title || null);
    }
  });
  crear();
  return getOrden(buyerId, id);
}

/** Orden de un comprador. Filtra por buyer_id: el WHERE es la autorización. */
function getOrden(buyerId, orderId) {
  const orden = db.getDb()
    .prepare('SELECT * FROM orders WHERE id = ? AND buyer_id = ?')
    .get(orderId, buyerId);
  if (!orden) return null;
  return { ...orden, items: getItems(orderId) };
}

/** Orden sin filtro de usuario. SOLO para el webhook, que no tiene sesión. */
function getOrdenPorId(orderId) {
  const orden = db.getDb().prepare('SELECT * FROM orders WHERE id = ?').get(orderId);
  return orden ? { ...orden, items: getItems(orderId) } : null;
}

function getOrdenPorPagoMp(mpPaymentId) {
  const orden = db.getDb()
    .prepare('SELECT * FROM orders WHERE mp_payment_id = ?')
    .get(String(mpPaymentId));
  return orden ? { ...orden, items: getItems(orden.id) } : null;
}

function getItems(orderId) {
  return db.getDb()
    .prepare('SELECT * FROM order_items WHERE order_id = ? ORDER BY id')
    .all(orderId);
}

function listarOrdenesDeComprador(buyerId, limite = 50) {
  return db.getDb()
    .prepare('SELECT * FROM orders WHERE buyer_id = ? ORDER BY created_at DESC LIMIT ?')
    .all(buyerId, limite)
    .map(o => ({ ...o, items: getItems(o.id) }));
}

function listarOrdenesDeVendedor(vendorId, limite = 50) {
  return db.getDb()
    .prepare('SELECT * FROM orders WHERE vendor_id = ? ORDER BY created_at DESC LIMIT ?')
    .all(vendorId, limite)
    .map(o => ({ ...o, items: getItems(o.id) }));
}

/**
 * Estados de pago que se consideran finales: una vez ahí, una notificación
 * tardía y desordenada de MP no puede hacerlos retroceder. MP no garantiza
 * el orden de entrega de los webhooks, así que sin esto un "pending" que
 * llega tarde podría pisar un "approved" ya registrado.
 */
const ESTADOS_FINALES = new Set(['approved', 'refunded', 'charged_back', 'cancelled']);

function actualizarPagoDeOrden(orderId, { mpPaymentId, paymentStatus }) {
  const orden = db.getDb().prepare('SELECT * FROM orders WHERE id = ?').get(orderId);
  if (!orden) return false;

  if (orden.payment_status && ESTADOS_FINALES.has(orden.payment_status)
      && orden.payment_status !== paymentStatus) {
    // Salvo que el nuevo estado sea también final y posterior (un reembolso
    // después de una aprobación), se ignora.
    if (!(orden.payment_status === 'approved' && ESTADOS_FINALES.has(paymentStatus))) {
      return false;
    }
  }

  const status = paymentStatus === 'approved' ? 'paid'
    : ['rejected', 'cancelled'].includes(paymentStatus) ? 'cancelled'
    : orden.status;

  db.getDb().prepare(`
    UPDATE orders SET mp_payment_id = COALESCE(?, mp_payment_id),
                      payment_status = ?, status = ?, updated_at = ?
    WHERE id = ?
  `).run(mpPaymentId ? String(mpPaymentId) : null, paymentStatus, status, ahora(), orderId);
  return true;
}

// ─── Idempotencia del webhook ───────────────────────────────

/**
 * Registra el evento y dice si es NUEVO. El UNIQUE de la tabla es lo que
 * hace la garantía: si dos entregas del mismo evento llegan a la vez, solo
 * una consigue insertar y la otra recibe false.
 */
function registrarEventoWebhook({ eventId, topic, resourceId }) {
  try {
    db.getDb().prepare(`
      INSERT INTO mp_webhook_events (event_id, topic, resource_id, received_at)
      VALUES (?, ?, ?, ?)
    `).run(String(eventId), topic || null, resourceId ? String(resourceId) : null, ahora());
    return true;
  } catch (err) {
    if (String(err.message).includes('UNIQUE')) return false; // Ya procesado.
    throw err;
  }
}

function marcarEventoProcesado(eventId) {
  db.getDb()
    .prepare('UPDATE mp_webhook_events SET processed_at = ? WHERE event_id = ?')
    .run(ahora(), String(eventId));
}

module.exports = {
  crearOAuthState,
  consumirOAuthState,
  limpiarOAuthStatesViejos,
  guardarCuentaVendedor,
  getCuentaVendedor,
  getCuentaVendedorConToken,
  actualizarTokensVendedor,
  desconectarVendedor,
  getCustomerId,
  guardarCustomerId,
  guardarTarjeta,
  listarTarjetas,
  getTarjeta,
  borrarTarjeta,
  crearOrden,
  getOrden,
  getOrdenPorId,
  getOrdenPorPagoMp,
  listarOrdenesDeComprador,
  listarOrdenesDeVendedor,
  actualizarPagoDeOrden,
  registrarEventoWebhook,
  marcarEventoProcesado,
};
