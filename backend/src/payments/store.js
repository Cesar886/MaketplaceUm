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

// Único proveedor implementado hoy. La columna `provider` existe para que
// añadir otro no obligue a migrar la tabla; mientras tanto, todo lo que no
// diga otra cosa habla de Mercado Pago.
const PROVEEDOR_POR_DEFECTO = 'mercadopago';

function guardarCuentaVendedor(sellerId, { mpUserId, accessToken, refreshToken, expiresIn, publicKey },
  provider = PROVEEDOR_POR_DEFECTO) {
  const expiraEn = Number.isFinite(expiresIn)
    ? new Date(Date.now() + expiresIn * 1000).toISOString()
    : null;

  db.getDb().prepare(`
    INSERT INTO vendor_payment_accounts
      (seller_id, provider, mp_user_id, mp_access_token_enc, mp_refresh_token_enc,
       mp_token_expires_at, mp_public_key, connected_at, revoked_at,
       disconnect_reason, disconnected_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL)
    ON CONFLICT(seller_id, provider) DO UPDATE SET
      mp_user_id = excluded.mp_user_id,
      mp_access_token_enc = excluded.mp_access_token_enc,
      mp_refresh_token_enc = excluded.mp_refresh_token_enc,
      mp_token_expires_at = excluded.mp_token_expires_at,
      mp_public_key = excluded.mp_public_key,
      connected_at = excluded.connected_at,
      -- Reconectar limpia el rastro de la desconexión anterior: si no, un
      -- vendedor que ya volvió seguiría viendo el aviso de "reconecta tu
      -- cuenta" para siempre.
      revoked_at = NULL,
      disconnect_reason = NULL,
      disconnected_by = NULL
  `).run(
    sellerId,
    provider,
    String(mpUserId),
    cifrar(accessToken),
    refreshToken ? cifrar(refreshToken) : null,
    expiraEn,
    publicKey || null,
    ahora(),
  );
}

/** Fila cruda (tokens aún cifrados). Para saber si está conectado. */
function getCuentaVendedor(sellerId, provider = PROVEEDOR_POR_DEFECTO) {
  return db.getDb()
    .prepare(`SELECT * FROM vendor_payment_accounts
              WHERE seller_id = ? AND provider = ? AND revoked_at IS NULL`)
    .get(sellerId, provider) || null;
}

/**
 * Cuenta incluso si está desconectada. La necesita la UI para poder decir
 * "tu conexión se cayó, reconéctala" en vez de "no tienes cuenta", que son
 * dos situaciones distintas para el vendedor.
 */
function getCuentaVendedorIncluyendoRevocada(sellerId, provider = PROVEEDOR_POR_DEFECTO) {
  return db.getDb()
    .prepare('SELECT * FROM vendor_payment_accounts WHERE seller_id = ? AND provider = ?')
    .get(sellerId, provider) || null;
}

/**
 * Cuenta del vendedor con los tokens YA DESCIFRADOS. Único sitio donde el
 * token existe en claro en el proceso; el valor devuelto no debe guardarse
 * en ninguna estructura de larga vida ni loguearse.
 */
/**
 * Vendedor dueño de una cuenta de MP, buscado por el id de usuario DE MP.
 * Es lo único que trae el webhook de revocación: MP habla de su propio
 * user_id, no del nuestro. Busca también entre las revocadas para que un
 * reenvío del webhook encuentre la cuenta y no genere un aviso de
 * "desconocido" en los logs.
 */
function getVendedorPorMpUserId(mpUserId, provider = PROVEEDOR_POR_DEFECTO) {
  return db.getDb()
    .prepare('SELECT * FROM vendor_payment_accounts WHERE mp_user_id = ? AND provider = ?')
    .get(String(mpUserId), provider) || null;
}

function getCuentaVendedorConToken(sellerId, provider = PROVEEDOR_POR_DEFECTO) {
  const fila = getCuentaVendedor(sellerId, provider);
  if (!fila) return null;
  return {
    ...fila,
    accessToken: descifrar(fila.mp_access_token_enc),
    refreshToken: descifrar(fila.mp_refresh_token_enc),
  };
}

function actualizarTokensVendedor(sellerId, { accessToken, refreshToken, expiresIn },
  provider = PROVEEDOR_POR_DEFECTO) {
  const expiraEn = Number.isFinite(expiresIn)
    ? new Date(Date.now() + expiresIn * 1000).toISOString()
    : null;
  db.getDb().prepare(`
    UPDATE vendor_payment_accounts
    SET mp_access_token_enc = ?, mp_refresh_token_enc = COALESCE(?, mp_refresh_token_enc),
        mp_token_expires_at = ?
    WHERE seller_id = ? AND provider = ?
  `).run(cifrar(accessToken), refreshToken ? cifrar(refreshToken) : null, expiraEn,
    sellerId, provider);
}

/**
 * Marca la cuenta como desconectada. `motivo` y `por` quedan guardados para
 * que la app distinga una desconexión voluntaria de una revocación detectada
 * desde fuera: el mensaje que se le muestra al vendedor no es el mismo.
 *
 * @param {'user'|'webhook'|'token_check'} por quién detectó la desconexión
 * @returns {boolean} true si esta llamada la desconectó (false si ya lo estaba)
 */
function desconectarVendedor(sellerId, { motivo = null, por = 'user',
  provider = PROVEEDOR_POR_DEFECTO } = {}) {
  const cambios = db.getDb().prepare(`
    UPDATE vendor_payment_accounts
    SET revoked_at = ?, disconnect_reason = ?, disconnected_by = ?
    WHERE seller_id = ? AND provider = ? AND revoked_at IS NULL
  `).run(ahora(), motivo, por, sellerId, provider).changes;
  return cambios > 0;
}

// ─── Customer y tarjetas del comprador ──────────────────────
//
// Todo lo de aquí va por PAREJA (comprador, vendedor). El Customer de MP y
// sus tarjetas viven dentro de la cuenta del vendedor que los creó, así que
// una tarjeta no es del comprador a secas: es del comprador CON ese vendedor.
// La columna se sigue llamando `seller_id` por herencia del esquema (esa
// tabla de usuarios se llama `sellers`), pero aquí siempre es el comprador.

function getCustomerId(buyerId, vendorId) {
  const fila = db.getDb()
    .prepare('SELECT mp_customer_id FROM buyer_mp_customers WHERE seller_id = ? AND vendor_id = ?')
    .get(buyerId, vendorId);
  return fila ? fila.mp_customer_id : null;
}

function guardarCustomerId(buyerId, vendorId, mpCustomerId) {
  db.getDb().prepare(`
    INSERT INTO buyer_mp_customers (seller_id, vendor_id, mp_customer_id, created_at)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(seller_id, vendor_id) DO UPDATE SET mp_customer_id = excluded.mp_customer_id
  `).run(buyerId, vendorId, mpCustomerId, ahora());
}

function guardarTarjeta(buyerId, vendorId, tarjeta) {
  db.getDb().prepare(`
    INSERT INTO saved_cards
      (seller_id, vendor_id, mp_card_id, last_four_digits, payment_method,
       expiration_month, expiration_year, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(seller_id, vendor_id, mp_card_id) DO UPDATE SET
      last_four_digits = excluded.last_four_digits,
      payment_method = excluded.payment_method,
      expiration_month = excluded.expiration_month,
      expiration_year = excluded.expiration_year
  `).run(
    buyerId,
    vendorId,
    tarjeta.mpCardId,
    tarjeta.lastFour || null,
    tarjeta.paymentMethod || null,
    tarjeta.expMonth || null,
    tarjeta.expYear || null,
    ahora(),
  );
}

function listarTarjetas(buyerId, vendorId) {
  return db.getDb()
    .prepare(`SELECT * FROM saved_cards WHERE seller_id = ? AND vendor_id = ?
              ORDER BY created_at DESC`)
    .all(buyerId, vendorId);
}

/** null si no existe, no es de este comprador, o es de otro vendedor. */
function getTarjeta(buyerId, vendorId, mpCardId) {
  return db.getDb()
    .prepare('SELECT * FROM saved_cards WHERE seller_id = ? AND vendor_id = ? AND mp_card_id = ?')
    .get(buyerId, vendorId, mpCardId) || null;
}

function borrarTarjeta(buyerId, vendorId, mpCardId) {
  return db.getDb()
    .prepare('DELETE FROM saved_cards WHERE seller_id = ? AND vendor_id = ? AND mp_card_id = ?')
    .run(buyerId, vendorId, mpCardId).changes > 0;
}

/**
 * Borra las tarjetas que un vendedor ya no puede cobrar. Se usa cuando su
 * cuenta se desconecta: esos Customers dejan de ser alcanzables, así que
 * seguir ofreciéndolas en el checkout solo produce cobros fallidos.
 */
function borrarTarjetasDeVendedor(vendorId) {
  const db_ = db.getDb();
  const n = db_.prepare('DELETE FROM saved_cards WHERE vendor_id = ?').run(vendorId).changes;
  db_.prepare('DELETE FROM buyer_mp_customers WHERE vendor_id = ?').run(vendorId);
  return n;
}

// ─── Órdenes ────────────────────────────────────────────────

function crearOrden({ id, buyerId, vendorId, amount, applicationFee, currency, origin,
  paymentMethod = null, items }) {
  const crear = db.getDb().transaction(() => {
    db.getDb().prepare(`
      INSERT INTO orders
        (id, buyer_id, vendor_id, amount, application_fee, currency,
         status, payment_status, payment_method, origin, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 'pending', NULL, ?, ?, ?, ?)
    `).run(id, buyerId, vendorId, amount, applicationFee, currency,
      paymentMethod, origin, ahora(), ahora());

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

/**
 * Estados en los que el pago guardado está MUERTO: no cobró y ya no va a
 * cobrar. Son los únicos desde los que la orden admite un intento de cobro
 * nuevo — con otra tarjeta, típicamente.
 *
 * Todo lo demás (approved, authorized, in_process, pending, in_mediation,
 * refunded, charged_back) significa que hay o hubo dinero de por medio;
 * lanzar un segundo cobro ahí es un cargo duplicado real.
 */
const ESTADOS_MUERTOS = new Set(['rejected', 'cancelled']);

/**
 * ¿Se puede intentar cobrar esta orden? Vive aquí, junto a los conjuntos de
 * estados, para que el checkout no tenga que reimplementar el criterio con
 * un `if` que se desincronice de ESTADOS_MUERTOS.
 */
function admiteNuevoIntentoDePago(orden) {
  if (!orden) return false;
  if (orden.status === 'paid') return false;
  return !orden.payment_status || ESTADOS_MUERTOS.has(orden.payment_status);
}

/**
 * Cuánto margen se añade al bloqueo por encima de la caducidad que Mercado
 * Pago tiene apuntada para la preferencia.
 *
 * El bloqueo tiene que sobrevivir a la ventana de pago, nunca al revés:
 * relojes que no van sincronizados, una petición que tardó, o el propio MP
 * aceptando un pago justo en el límite. Si el bloqueo cayera antes, se abre
 * exactamente el hueco de cobro duplicado que existe para cerrar.
 */
const MARGEN_PREFERENCIA_MS = 2 * 60 * 1000;

/**
 * Reserva EN EXCLUSIVA el derecho a crear una preferencia para esta orden.
 *
 * Es un candado, y hace falta uno de verdad porque comprobar "¿hay
 * preferencia viva?" y crearla son dos pasos con un `await` a Mercado Pago
 * en medio. Node atiende otra petición durante esa espera, así que dos
 * peticiones de la misma orden pueden pasar las dos la comprobación antes de
 * que ninguna haya creado nada — y acabar con DOS enlaces vivos capaces de
 * cobrar lo mismo.
 *
 * El UPDATE condicional lo resuelve porque en SQLite es atómico: de dos
 * peticiones simultáneas, exactamente una ve `changes === 1`.
 *
 * Se reserva la ventana ANTES de hablar con Mercado Pago, no después. Al
 * revés el candado no serviría de nada: la carrera ocurre justo durante esa
 * llamada. Si la llamada falla, [liberarPreferencia] deshace la reserva.
 *
 * @returns {boolean} true si esta petición se quedó con la reserva.
 */
function reservarPreferencia(orderId, expiraEn) {
  return db.getDb().prepare(`
    UPDATE orders
    SET mp_preference_expires_at = ?, updated_at = ?
    WHERE id = ?
      AND (mp_preference_expires_at IS NULL OR mp_preference_expires_at <= ?)
  `).run(
    new Date(expiraEn.getTime() + MARGEN_PREFERENCIA_MS).toISOString(),
    ahora(),
    orderId,
    new Date().toISOString(),
  ).changes > 0;
}

/**
 * Deshace una reserva cuya preferencia nunca llegó a existir.
 *
 * Sin esto, un fallo de red al hablar con Mercado Pago dejaría la orden
 * bloqueada para TODOS los métodos de pago durante la ventana entera, por
 * un cobro que no ocurrió. Solo borra si no hay preferencia guardada: si la
 * hay, es pagable y el bloqueo tiene que seguir.
 */
function liberarPreferencia(orderId) {
  return db.getDb().prepare(`
    UPDATE orders SET mp_preference_expires_at = NULL, updated_at = ?
    WHERE id = ? AND mp_preference_id IS NULL
  `).run(ahora(), orderId).changes > 0;
}

/**
 * Apunta en la orden la preferencia de Mercado Pago que se acaba de crear.
 *
 * Guardar el `init_point` no es un lujo: es lo que permite devolver LA MISMA
 * preferencia si alguien vuelve a pedir pagar con su cuenta, en vez de crear
 * una segunda igual de pagable que la primera.
 */
function guardarPreferenciaDeOrden(orderId, { preferenceId, initPoint, expiraEn }) {
  return db.getDb().prepare(`
    UPDATE orders
    SET mp_preference_id = ?, mp_preference_init_point = ?,
        mp_preference_expires_at = ?, updated_at = ?
    WHERE id = ?
  `).run(
    String(preferenceId),
    String(initPoint),
    new Date(expiraEn.getTime() + MARGEN_PREFERENCIA_MS).toISOString(),
    ahora(),
    orderId,
  ).changes > 0;
}

/**
 * El pago por Mercado Pago que esta orden tiene EN CURSO, o null.
 *
 * Mientras devuelva algo, cobrar esa orden por cualquier otro camino es un
 * cargo duplicado esperando a ocurrir.
 *
 * Se mira `mp_preference_expires_at` y NO `mp_preference_id`, y la
 * diferencia es una rendija por la que se cuela un cobro doble: entre que
 * [reservarPreferencia] escribe la fecha y la preferencia existe de verdad
 * hay una llamada a Mercado Pago en vuelo. Exigir el id ahí devolvería null
 * y dejaría pasar un cobro con tarjeta justo cuando está naciendo un enlace
 * de pago para la misma orden.
 *
 * Por eso `initPoint` puede venir null: significa "reservada, todavía no
 * hay enlace". Bloquea igual, pero no se puede ofrecer.
 *
 * @returns {{id: string|null, initPoint: string|null, expiraEn: Date}|null}
 */
function preferenciaVivaDeOrden(orden) {
  if (!orden?.mp_preference_expires_at) return null;

  const expira = new Date(orden.mp_preference_expires_at).getTime();
  // Una fecha ilegible se trata como VIVA, no como caducada: ante la duda,
  // bloquear un cobro es recuperable (se reintenta en unos minutos) y
  // permitir uno duplicado no lo es.
  if (Number.isFinite(expira) && expira <= Date.now()) return null;

  return {
    id: orden.mp_preference_id || null,
    initPoint: orden.mp_preference_init_point || null,
    expiraEn: Number.isFinite(expira) ? new Date(expira) : new Date(Date.now() + 60000),
  };
}

function actualizarPagoDeOrden(orderId, { mpPaymentId, paymentStatus }) {
  const orden = db.getDb().prepare('SELECT * FROM orders WHERE id = ?').get(orderId);
  if (!orden) return false;

  // ¿Esta notificación es de OTRO pago del que ya teníamos guardado? Pasa
  // cuando el comprador reintentó con otra tarjeta tras un rechazo: la orden
  // acumula varios intentos de cobro y solo uno es el bueno.
  const esOtroPago = Boolean(
    mpPaymentId && orden.mp_payment_id
    && String(orden.mp_payment_id) !== String(mpPaymentId),
  );

  if (esOtroPago) {
    // El intento nuevo solo sustituye al guardado si el guardado está
    // muerto. Al revés no: el webhook tardío de un intento rechazado no
    // puede tumbar la orden que otro pago ya dejó aprobada.
    if (!ESTADOS_MUERTOS.has(orden.payment_status)) return false;
  } else if (orden.payment_status && ESTADOS_FINALES.has(orden.payment_status)
      && orden.payment_status !== paymentStatus) {
    // Mismo pago: MP no garantiza el orden de entrega, así que un estado
    // final no retrocede. Salvo que el nuevo estado sea también final y
    // posterior (un reembolso después de una aprobación).
    if (!(orden.payment_status === 'approved' && ESTADOS_FINALES.has(paymentStatus))) {
      return false;
    }
  }

  const status = paymentStatus === 'approved' ? 'paid'
    : ['rejected', 'cancelled'].includes(paymentStatus) ? 'cancelled'
    : orden.status;

  // ¿Es ESTA llamada la que aprueba el pago? Se calcula ANTES del UPDATE,
  // comparando contra el estado guardado. Es la única condición segura para
  // descontar inventario:
  //
  // Mercado Pago reenvía el mismo webhook varias veces, y con el mismo
  // estado. El UPDATE de abajo es idempotente (escribir 'approved' encima de
  // 'approved' no cambia nada), pero un descuento NO lo es: sin esta guarda,
  // tres entregas de la misma notificación descuentan tres veces y dejan el
  // inventario en negativo sin que nadie haya comprado de más.
  const apruebaAhora = paymentStatus === 'approved'
    && orden.payment_status !== 'approved';

  // Todo en una transacción: si el descuento falla, el pago no puede quedar
  // registrado como cobrado — y al revés, una orden marcada como pagada sin
  // descontar vende dos veces lo mismo.
  db.getDb().transaction(() => {
    db.getDb().prepare(`
      UPDATE orders SET mp_payment_id = COALESCE(?, mp_payment_id),
                        payment_status = ?, status = ?, updated_at = ?
      WHERE id = ?
    `).run(mpPaymentId ? String(mpPaymentId) : null, paymentStatus, status, ahora(), orderId);

    if (apruebaAhora) descontarInventario(orderId);
  })();

  return true;
}

/**
 * Resta del inventario lo que se acaba de vender.
 *
 * `MAX(0, ...)` porque un stock negativo es peor que uno en cero: todos los
 * cálculos de disponibilidad asumen >= 0, y uno negativo los rompe en
 * silencio. No debería llegar aquí (el checkout comprueba existencias justo
 * antes de cobrar), pero si dos compras entran a la vez, el dinero ya se
 * cobró y lo que toca es dejar el inventario en un estado sano.
 *
 * `stock_quantity IS NOT NULL` deja fuera a los productos antiguos que
 * todavía no tienen inventario definido: tumbar el registro de un pago ya
 * cobrado por eso sería mucho peor que no descontar.
 */
function descontarInventario(orderId) {
  const actualizar = db.getDb().prepare(`
    UPDATE products
    SET stock_quantity = MAX(0, stock_quantity - ?),
        stock_updated_at = ?
    WHERE id = ? AND stock_quantity IS NOT NULL
  `);
  for (const item of getItems(orderId)) {
    actualizar.run(item.quantity || 1, ahora(), item.product_id);
  }
}

/**
 * Marca que esta orden no se puede cobrar por el método elegido y hace falta
 * otro. No es lo mismo que 'cancelled': la compra sigue en pie, lo que falló
 * es la forma de pagarla. Sin un estado propio se quedaría en 'pending' y
 * nadie —ni el comprador ni el vendedor— sabría que hay algo que hacer.
 */
function marcarRequiereOtroMetodo(orderId) {
  return db.getDb().prepare(`
    UPDATE orders SET status = 'requires_other_method', updated_at = ?
    WHERE id = ? AND status = 'pending'
  `).run(ahora(), orderId).changes > 0;
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

/**
 * Si es true, esta entrega ya se procesó CON ÉXITO y no hay nada que hacer.
 * Si es false, puede que nunca haya llegado o que haya llegado y fallado a
 * medias (obtenerPago reventó, por ejemplo) — en ambos casos se debe
 * procesar, para que un reintento de MP no se pierda por un fallo previo.
 */
function eventoFueProcesado(eventId) {
  const fila = db.getDb()
    .prepare('SELECT processed_at FROM mp_webhook_events WHERE event_id = ?')
    .get(String(eventId));
  return !!(fila && fila.processed_at);
}

module.exports = {
  crearOAuthState,
  consumirOAuthState,
  limpiarOAuthStatesViejos,
  PROVEEDOR_POR_DEFECTO,
  guardarCuentaVendedor,
  getCuentaVendedor,
  getCuentaVendedorIncluyendoRevocada,
  getVendedorPorMpUserId,
  getCuentaVendedorConToken,
  actualizarTokensVendedor,
  desconectarVendedor,
  getCustomerId,
  guardarCustomerId,
  guardarTarjeta,
  listarTarjetas,
  getTarjeta,
  borrarTarjeta,
  borrarTarjetasDeVendedor,
  crearOrden,
  getOrden,
  getOrdenPorId,
  getOrdenPorPagoMp,
  listarOrdenesDeComprador,
  listarOrdenesDeVendedor,
  actualizarPagoDeOrden,
  admiteNuevoIntentoDePago,
  guardarPreferenciaDeOrden,
  preferenciaVivaDeOrden,
  reservarPreferencia,
  liberarPreferencia,
  MARGEN_PREFERENCIA_MS,
  marcarRequiereOtroMetodo,
  registrarEventoWebhook,
  eventoFueProcesado,
  marcarEventoProcesado,
};
