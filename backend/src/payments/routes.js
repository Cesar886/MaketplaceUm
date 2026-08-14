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
const { comisionCobrable, esRechazoDeComision } = require('./comision');
const { tokenVigenteDeVendedor } = require('./vendorTokens');
const { validarFirma, procesarEvento } = require('./webhook');
const { paginaPuente } = require('./paginaPuente');
const { estadoDeAtencion, mensajeCerrado } = require('../validation/horarioNegocio');

const MENSAJE_GENERICO = 'No pudimos completar la operación. Intenta de nuevo en unos minutos.';

/**
 * Cuánto tiempo es pagable una preferencia de Mercado Pago.
 *
 * Es a la vez el tiempo que la orden queda bloqueada para los demás métodos
 * de pago (ver `prepararCobro`), así que el número tiene dos costes
 * opuestos: de más, quien abandona el pago espera para poder usar la
 * tarjeta; de menos, no da tiempo a terminar un checkout con la
 * verificación del banco de por medio.
 */
const VENTANA_PREFERENCIA_MS = 15 * 60 * 1000;

/**
 * Fecha en el formato que Mercado Pago acepta en `expiration_date_to`.
 *
 * `Date.prototype.toISOString()` produce '…Z', y aunque es ISO 8601 válido,
 * MP documenta y espera el desplazamiento explícito ('…+00:00'). La 'Z' ha
 * dado 400 en sus endpoints, y aquí un 400 no degrada nada: tumba la
 * creación de la preferencia y con ella todo el método de pago.
 */
function fechaMp(fecha) {
  return fecha.toISOString().replace(/Z$/, '+00:00');
}

/**
 * De qué tipo son las credenciales de LA PLATAFORMA, sin revelar su valor.
 *
 * Solo vale para las credenciales de la aplicación (`MP_ACCESS_TOKEN`,
 * `MP_PUBLIC_KEY`), donde el prefijo sí significa lo que parece.
 *
 * NO sirve para el token de un VENDEDOR: los usuarios de prueba que
 * autorizan por OAuth reciben tokens `APP_USR-` igual que las cuentas
 * reales. Etiquetar uno de esos como "PRODUCCIÓN" es afirmar algo falso, y
 * eso ya costó un diagnóstico entero — se persiguió una mezcla
 * test/producción que nunca existió. Para el vendedor está
 * [describirCuentaVendedor], que pregunta en vez de suponer.
 */
function tipoDeCredencialDePlataforma(valor) {
  if (!valor) return 'ausente';
  if (valor.startsWith('TEST-')) return 'PRUEBA (TEST-)';
  if (valor.startsWith('APP_USR-')) return 'PRODUCCIÓN (APP_USR-)';
  return 'desconocido';
}

/**
 * Si la cuenta que va a cobrar es un usuario de prueba de Mercado Pago.
 *
 * Se resuelve con lo que responde `GET /users/me` con el token del vendedor,
 * no con el prefijo del token. MP nombra a sus usuarios de prueba con nick
 * `TESTUSER…` y correo en `@testuser.com`.
 */
function esCuentaDePrueba(usuarioMp) {
  const nick = String(usuarioMp?.nickname || '');
  const email = String(usuarioMp?.email || '');
  return nick.startsWith('TESTUSER') || email.endsWith('@testuser.com');
}

/** Descripción del vendedor para el log: quién es, no qué prefijo tiene. */
function describirCuentaVendedor(usuarioMp) {
  if (!usuarioMp) return 'no identificada (MP no respondió a /users/me)';
  const quien = `id=${usuarioMp.id ?? '?'} nick=${usuarioMp.nickname || '?'}`;
  return esCuentaDePrueba(usuarioMp)
    ? `${quien} — cuenta DE PRUEBA de Mercado Pago`
    : `${quien} — cuenta real`;
}

/** ¿La URL apunta al checkout de sandbox de Mercado Pago? */
function esEnlaceDeSandbox(url) {
  try {
    return /(^|\.)sandbox\./i.test(new URL(url).hostname);
  } catch {
    return false;
  }
}

/**
 * Cuál de los dos enlaces de la preferencia se le da al comprador.
 *
 * Al crear una preferencia, MP devuelve DOS enlaces: `init_point` (checkout
 * de producción, www.mercadopago.com.mx) y `sandbox_init_point`. Una
 * preferencia creada con credenciales de PRUEBA solo es válida en el
 * checkout de sandbox: abrirla en el de producción pinta la pantalla
 * genérica "Oh, no, algo anduvo mal" sin importar con qué cuenta —real o de
 * prueba— entre el comprador.
 *
 * La respuesta, COMPROBADA a mano el 2026-08-14: siempre `init_point`,
 * también con credenciales `TEST-`. Se abrió una preferencia creada con el
 * token de un vendedor de prueba en www.mercadopago.com.mx sin sesión
 * iniciada y su checkout pintó el formulario, aceptó la tarjeta de prueba y
 * llegó a "Revisa tu pago". El entorno de sandbox de Mercado Pago ya no es
 * un entorno aparte: su host sigue respondiendo, pero devuelve la misma
 * página marcada `"productive": true` y sin `router_request_id`.
 *
 * Esto se dejó por escrito porque la hipótesis contraria costó una noche
 * entera. El síntoma —el checkout cargando "Oh, no, algo anduvo mal"— NO
 * venía del enlace: venía de la cuenta compradora de prueba, a la que MP le
 * exigía validar un código enviado a un buzón que no existe. Mandar al
 * comprador a sandbox no lo arregló, porque nunca fue eso.
 *
 * Queda `MP_USE_SANDBOX_INIT_POINT=true` como salida de emergencia por si MP
 * revive el entorno, y el log dice en cada preferencia qué se entregó y por
 * qué, que es lo que faltaba para poder descartar esta hipótesis en un
 * minuto en vez de en una noche.
 */
function elegirInitPoint({ orden, preferencia, usuarioMpVendedor }) {
  const normal = preferencia?.init_point || '';
  const sandbox = preferencia?.sandbox_init_point || '';

  const plataformaEnPruebas = String(cfg.config.accessToken || '').startsWith('TEST-');
  const vendedorDePrueba = !!usuarioMpVendedor && esCuentaDePrueba(usuarioMpVendedor);
  const forzado = cfg.forzarSandboxInitPoint();

  const entorno = [
    `plataforma ${plataformaEnPruebas ? 'TEST-' : 'APP_USR-'}`,
    usuarioMpVendedor
      ? `vendedor ${vendedorDePrueba ? 'de PRUEBA' : 'real'}`
      : 'vendedor sin identificar',
  ].join(', ');

  if (forzado && sandbox) {
    console.warn(
      `[pagos] Orden ${orden.id}: usando SANDBOX porque MP_USE_SANDBOX_INIT_POINT=true `
      + `lo fuerza (salida de emergencia; ${entorno}). El checkout normal funciona `
      + 'también con credenciales de prueba: quita la variable si no sabes por qué está.',
    );
    return sandbox;
  }

  // El orden de la frase no es casual: el entorno va AL FINAL. Ponerlo antes
  // hacía que la línea de un vendedor real siguiera con "…de prueba" y
  // pareciera decir lo contrario de lo que dice (hay una prueba que lo fija:
  // una etiqueta mal leída ya costó un diagnóstico entero).
  console.log(
    `[pagos] Orden ${orden.id}: enlace elegido = checkout NORMAL (init_point), `
    + `el correcto también en pruebas — ${entorno}`,
  );
  return normal;
}

/**
 * Última red antes de darle la URL al comprador: que no se cuele un enlace
 * de sandbox sin haberlo pedido.
 *
 * Lanza en vez de avisar. Es el fallo que acabamos de vivir —un enlace que
 * MP acepta crear y que luego no lleva a ninguna parte—, y devolverlo solo
 * cambia un error visible aquí por uno que descubre el comprador y nosotros
 * no vemos nunca.
 */
function motivoEnlaceInutilizable(url) {
  if (esEnlaceDeSandbox(url) && !cfg.forzarSandboxInitPoint()) {
    return `apunta al checkout de sandbox: ${url}`;
  }
  return null;
}

function verificarEnlaceCoherente({ orden, url }) {
  const motivo = motivoEnlaceInutilizable(url);
  if (motivo) {
    throw new mp.MpError(`Orden ${orden.id}: el enlace de pago ${motivo}`);
  }
}

/**
 * Deja en el log todo lo necesario para diagnosticar un checkout que falla
 * DESPUÉS de crearse bien.
 *
 * Existe por un caso concreto: MP responde 200, devolvemos su enlace, y al
 * abrirlo su checkout pinta "algo salió mal". Con un log que solo decía
 * "preferencia creada" era imposible distinguir un payload mal formado de
 * una credencial cruzada o de una cuenta mal configurada.
 *
 * Todo pasa por `mp.redactar()`. No es ceremonia: las respuestas de MP hacen
 * eco de parte de lo enviado, y este archivo imprime el payload entero.
 */
function registrarDiagnosticoPreferencia({ orden, payload, respuesta, usuarioMpVendedor }) {
  console.log(
    `[pagos][diag] Orden ${orden.id}: cuenta del vendedor = `
    + `${describirCuentaVendedor(usuarioMpVendedor)}; credenciales de la `
    + `plataforma = ${tipoDeCredencialDePlataforma(cfg.config.accessToken)}`,
  );

  // La mezcla que sí importa, comprobada contra quién es la cuenta y no
  // contra el prefijo de su token.
  const plataformaEnPruebas = String(cfg.config.accessToken || '').startsWith('TEST-');
  if (usuarioMpVendedor && plataformaEnPruebas !== esCuentaDePrueba(usuarioMpVendedor)) {
    console.warn(
      `[pagos][diag] Orden ${orden.id}: INCONSISTENCIA de entorno. La plataforma está en `
      + `${plataformaEnPruebas ? 'PRUEBAS' : 'PRODUCCIÓN'} y la cuenta del vendedor es `
      + `${esCuentaDePrueba(usuarioMpVendedor) ? 'de PRUEBA' : 'real'}. `
      + 'Mercado Pago no admite esta combinación y su checkout fallará al abrirse.',
    );
  }
  if (cfg.depuracionPreferencia()) {
    console.log(
      `[pagos][diag] Orden ${orden.id}: payload -> POST /checkout/preferences: `
      + JSON.stringify(mp.redactar(payload)),
    );
    console.log(
      `[pagos][diag] Orden ${orden.id}: respuesta de Mercado Pago: `
      + JSON.stringify(mp.redactar(respuesta)),
    );
  } else {
    // Lo mismo en una línea legible. Estos cuatro datos son los que han
    // hecho falta en cada vuelta del diagnóstico; el resto del volcado no
    // se usó nunca sin saber ya qué se buscaba.
    console.log(
      `[pagos][diag] Orden ${orden.id}: preferencia ${respuesta?.id || '?'} `
      + `collector_id=${respuesta?.collector_id ?? '?'} `
      + `marketplace_fee=${respuesta?.marketplace_fee ?? '(sin comisión)'} `
      + `sandbox_init_point=${respuesta?.sandbox_init_point ? 'sí' : 'no'}`,
    );
  }

  if (respuesta?.sandbox_init_point) {
    console.log(
      `[pagos][diag] Orden ${orden.id}: MP devolvió también un sandbox_init_point. `
      + 'Cuál se entrega lo decide el tipo de credencial (ver la línea "usando …" '
      + 'que sigue), no una variable de entorno.',
    );
  }
}

/**
 * Relee en Mercado Pago la preferencia recién creada y avisa si no guardó lo
 * que se le mandó.
 *
 * Hace falta porque el eco de la creación NO sirve como comprobación: MP
 * devuelve felizmente una preferencia válida aunque haya ignorado el
 * `marketplace_fee`. Ese fallo no da ningún error —el comprador paga, la
 * plataforma no cobra— y no se descubre hasta cuadrar cuentas.
 *
 * Es diagnóstico puro: nunca lanza. El enlace de pago ya existe y es válido,
 * y dejar a alguien sin poder pagar porque una comprobación opcional falló
 * sería cambiar un problema de contabilidad por uno de ventas.
 */
async function comprobarPreferenciaGuardada({ orden, preferenciaId, comisionEnviada, accessTokenVendedor }) {
  try {
    const guardada = await mp.obtenerPreferencia(preferenciaId, accessTokenVendedor);
    if (cfg.depuracionPreferencia()) {
      console.log(
        `[pagos][diag] Orden ${orden.id}: preferencia releída de MP: `
        + JSON.stringify(mp.redactar(guardada)),
      );
    }

    const guardadaFee = Number(guardada?.marketplace_fee) || 0;
    if (comisionEnviada > 0 && guardadaFee !== comisionEnviada) {
      console.warn(
        `[pagos][diag] Orden ${orden.id}: Mercado Pago NO guardó el marketplace_fee `
        + `(enviado ${comisionEnviada}, guardado ${guardadaFee}). El cobro funcionará `
        + 'igual, pero la plataforma no cobrará comisión en esta orden.',
      );
    }
  } catch (err) {
    console.warn(
      `[pagos][diag] Orden ${orden.id}: falló la relectura de la preferencia `
      + `${preferenciaId} (solo diagnóstico, el pago sigue su curso): `
      + `${err?.message || err}`,
    );
  }
}

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
 * El primer producto de la orden cuyo inventario ya no alcanza, o null si
 * todos alcanzan.
 *
 * Los productos con `stock_quantity` NULL (publicados antes de que el
 * inventario fuera obligatorio) no bloquean: no sabemos cuántos hay, y
 * rechazar el cobro por eso castigaría al comprador por un dato que solo el
 * vendedor puede arreglar.
 */
function existenciasInsuficientes(orden) {
  const consultar = db.getDb()
    .prepare('SELECT id, title, stock_quantity FROM products WHERE id = ?');
  for (const item of orden.items || []) {
    const producto = consultar.get(item.product_id);
    if (!producto || producto.stock_quantity === null) continue;
    const pedido = item.quantity || 1;
    if (producto.stock_quantity < pedido) {
      return {
        id: producto.id,
        title: producto.title,
        disponible: producto.stock_quantity,
        pedido,
      };
    }
  }
  return null;
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
function limitePorComprador({ minutos, max, soloSiSalioAMp = false }) {
  return rateLimit({
    windowMs: minutos * 60 * 1000,
    limit: max,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    keyGenerator: req => req.user.id,

    // `soloSiSalioAMp` descuenta únicamente las peticiones que llegaron a
    // tocar Mercado Pago. Lo usa el pago con cuenta de MP, donde el candado
    // de la preferencia ya impide crear más de una por orden: sin esto,
    // quien toca el botón varias veces gasta su cupo en respuestas 409 que
    // no llegaron a MP, y acaba sin poder pagar durante un cuarto de hora
    // por haber tenido prisa.
    //
    // El cobro con tarjeta NO lo usa: allí el límite existe contra el
    // "card testing" (probar tarjetas robadas en lote), y ahí los intentos
    // fallidos son justo los que hay que contar.
    //
    // Va por `skipFailedRequests` y no por `skip`: `skip` se evalúa ANTES
    // del handler, cuando todavía no se sabe nada de lo que va a pasar.
    // `skipFailedRequests` se resuelve al terminar la respuesta.
    //
    // Y el criterio es una marca explícita, no el código de estado: la
    // respuesta que devuelve una preferencia ya creada es un 200 perfecto
    // que NO tocó Mercado Pago, y contarla agota el cupo igual.
    skipFailedRequests: soloSiSalioAMp,
    requestWasSuccessful: soloSiSalioAMp
      ? (req, res) => res.locals.salioAMercadoPago === true
      : undefined,
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

/**
 * Todo lo que hay que comprobar ANTES de mover dinero por una orden, sea
 * cual sea el carril de cobro.
 *
 * Existe porque hay dos formas de pagar la misma orden —tarjeta tokenizada
 * en la app, o la cuenta de Mercado Pago del comprador— y las dos tienen que
 * pasar exactamente por las mismas guardas. Duplicarlas en dos endpoints es
 * cómo una de las dos se queda sin la comprobación de stock, o sin la de
 * horario, la próxima vez que alguien toque una sola de ellas.
 *
 * Contrato: si algo falla, YA respondió a `res` y devuelve null. Quien llama
 * solo tiene que hacer `if (!preparado) return;`.
 *
 * `metodo` no cambia ninguna decisión: solo la redacción de los mensajes,
 * porque "ya no puede cobrar con tarjeta" es desconcertante para quien
 * eligió pagar con su cuenta de Mercado Pago.
 *
 * @returns {Promise<{orden, comprador, vendedor, total: number, comision: number}|null>}
 */
async function prepararCobro(req, res, orderId, { metodo = 'tarjeta' } = {}) {
  const comoTarjeta = metodo === 'tarjeta';

  // La orden se busca filtrando por comprador: si es de otra persona,
  // simplemente no aparece.
  const orden = store.getOrden(req.user.id, String(orderId));
  if (!orden) {
    res.status(404).json({ error: 'Orden no encontrada.' });
    return null;
  }
  // Un intento anterior solo deja reintentar si murió sin cobrar (una
  // tarjeta rechazada). No basta con mirar `orden.status`: un pago que MP
  // dejó 'in_process' deja la orden en 'pending', y cobrar otra vez ahí
  // sería un cargo duplicado real. El criterio vive en el store, junto a
  // los conjuntos de estados.
  if (!store.admiteNuevoIntentoDePago(orden)) {
    res.status(409).json({ error: 'Esta orden ya fue procesada.' });
    return null;
  }

  // Una preferencia de Mercado Pago viva es un cobro que puede entrar en
  // cualquier momento, aunque la orden siga en 'pending' y `admiteNuevoIntento`
  // la deje pasar. Cobrar por otro camino mientras tanto es un cargo
  // duplicado REAL, y encima invisible: el webhook del segundo pago se
  // niega a pisar al primero, así que el dinero se cobra y no queda
  // registrado en ninguna orden.
  //
  // No hay forma de cancelarla desde aquí, y por eso no se ofrece: mientras
  // Mercado Pago la acepte, lo único seguro es esperar a que caduque.
  const viva = store.preferenciaVivaDeOrden(orden);
  if (viva && metodo !== 'cuenta_mp') {
    const minutos = Math.max(1, Math.ceil((viva.expiraEn.getTime() - Date.now()) / 60000));
    res.status(409).json({
      error: 'Tienes un pago con Mercado Pago en curso para este pedido. '
           + 'Termínalo ahí, o espera '
           + `${minutos} minuto${minutos === 1 ? '' : 's'} para pagar de otra forma. `
           + 'No pagues dos veces.',
      motivo: 'preferencia_en_curso',
      minutosRestantes: minutos,
    });
    return null;
  }

  const comprador = getSeller(req.user.id);
  if (!comprador?.email) {
    res.status(400).json({
      error: 'Necesitas un correo en tu perfil para pagar en la app.',
    });
    return null;
  }

  // El vendedor tiene que poder recibir dinero ANTES de intentar cobrar:
  // si no, MP devuelve un error opaco y el comprador no entiende nada.
  const vendedor = getSeller(orden.vendor_id);
  const cuenta = store.getCuentaVendedor(orden.vendor_id);
  if (!cuenta) {
    res.status(409).json({
      error: `${vendedor?.name || 'Este vendedor'} todavía no puede recibir pagos en la app. `
           + 'Contáctalo por chat para acordar otra forma de pago.',
    });
    return null;
  }

  // El total se RECALCULA desde order_items. Nunca se usa un monto que
  // venga en el body: sería trivial pagar $1 por una orden de $1000. Esto
  // es también lo que garantiza que los dos métodos cobren lo mismo: ambos
  // salen de aquí con el total del servidor, no con uno que traiga la app.
  const total = redondear2(
    orden.items.reduce((s, i) => s + i.unit_price * i.quantity, 0),
  );
  if (total !== redondear2(orden.amount)) {
    console.error(`[pagos] Orden ${orden.id}: total de items (${total}) `
      + `!= amount guardado (${orden.amount})`);
    res.status(409).json({ error: MENSAJE_GENERICO });
    return null;
  }

  let comision;
  try {
    comision = calcularComision(total);
  } catch (err) {
    console.error(`[pagos] Comisión inválida en ${orden.id}: ${err.message}`);
    res.status(503).json({ error: MENSAJE_GENERICO });
    return null;
  }

  // ¿El vendedor está abierto? Se comprueba EN EL SERVIDOR: la app también
  // lo pinta, pero la hora de un teléfono la cambia quien lo usa, y de esto
  // depende que un cobro entre o no.
  //
  // Quien no tiene horario configurado no queda bloqueado: `abierto` es
  // true en ese caso. Esa exigencia vive en la verificación, no aquí —
  // cortarle las ventas a un vendedor por un requisito de perfil sería
  // castigar al comprador por algo que no puede resolver.
  const atencion = estadoDeAtencion(orden.vendor_id);
  if (!atencion.abierto) {
    res.status(409).json({
      error: mensajeCerrado(vendedor?.name, atencion)
        + ' Escríbele por chat para acordar la entrega.',
      motivo: 'fuera_de_horario',
      abreA: atencion.abreA,
      diaAbre: atencion.diaAbre,
    });
    return null;
  }

  // ¿Sigue habiendo existencias? Entre que el comprador abrió la pantalla y
  // toca pagar, otra persona pudo llevarse la última unidad. Comprobarlo
  // aquí no elimina la carrera (dos cobros simultáneos pueden pasar los dos),
  // pero sí el caso común, y el descuento usa MAX(0, ...) para que ni
  // siquiera esa carrera deje el inventario en negativo.
  const sinExistencias = existenciasInsuficientes(orden);
  if (sinExistencias) {
    res.status(409).json({
      error: `${sinExistencias.title} ya no está disponible: `
        + `quedan ${sinExistencias.disponible} y pediste ${sinExistencias.pedido}.`,
      motivo: 'sin_stock',
      productId: sinExistencias.id,
    });
    return null;
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
    res.status(409).json({
      error: `${vendedor?.name || 'Este vendedor'} ya no puede cobrar `
           + `${comoTarjeta ? 'con tarjeta' : 'por Mercado Pago'}. `
           + 'Contáctalo por chat para acordar otra forma de pago.',
      orderStatus: 'requires_other_method',
    });
    return null;
  }

  // `preferenciaViva` solo llega con valor por el carril de Mercado Pago:
  // el de tarjeta ya se cortó arriba si existía.
  return {
    orden, comprador, vendedor, total, comision, preferenciaViva: viva,
    usuarioMpVendedor: conectado.usuarioMp || null,
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
    const paginaFinal = (titulo, texto, ok) => paginaPuente({
      titulo,
      texto,
      ok,
      deepLink: `${cfg.config.appDeepLinkScheme}://payments/connected?ok=${ok ? '1' : '0'}`,
    });

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

    // Las mismas guardas que usa el pago con cuenta de Mercado Pago: orden
    // del comprador, no cobrada ya, vendedor abierto, con stock y con la
    // autorización viva, y el total recalculado en el servidor.
    const preparado = await prepararCobro(req, res, orderId, { metodo: 'tarjeta' });
    if (!preparado) return;
    const { orden, comprador, vendedor, total, comision } = preparado;

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

      // La comisión que de verdad se puede cobrar en ESTE cobro. Puede
      // salir 0 —vendedor que es la propia cuenta de la aplicación, o
      // PLATFORM_FEE_ENABLED=false— y entonces no se manda el campo: MP
      // rechaza el pago ENTERO con el error 2059 si se le manda un
      // application_fee que no aplica. Ver payments/comision.js.
      const comisionAEnviar = await comisionCobrable(
        comision, tokenVendedor.mpUserId, `Orden ${orden.id}`,
      );

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
          // `undefined` y no 0: un application_fee de 0 explícito también lo
          // rechaza MP. El campo tiene que desaparecer del cuerpo.
          application_fee: comisionAEnviar > 0 ? comisionAEnviar : undefined,
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

      // `status_detail` va SIEMPRE que no sea una aprobación. Es el código
      // que distingue "la tarjeta no tiene fondos" de "el CVV está mal" de
      // "MP no admite comisión en este cobro" (cc_rejected_*, 2059…), y sin
      // él un rechazo en el log es solo la palabra "rejected".
      console.log(
        `[pagos] Orden ${orden.id}: pago ${pago.id} → ${pago.status}`
        + (pago.status === 'approved' ? '' : ` (${pago.status_detail || 'sin detalle'})`),
      );
      cfg.traza(
        `orden ${orden.id}: cobro con tarjeta — monto=${total} `
        + `comisión=${comisionAEnviar > 0 ? comisionAEnviar : '(ninguna)'} `
        + `cuotas=${Number(installments) > 0 ? Number(installments) : 1} `
        + `método=${paymentMethodId || '(el que deduzca MP)'}`,
      );

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
      // El 2059 llega como 400, pero NO es un problema de la tarjeta: es la
      // configuración del split. Sin esta rama se traduciría a "intenta con
      // otra tarjeta" y quien compra quemaría intentos del límite
      // antifraude probando tarjetas que están perfectas.
      if (err instanceof mp.MpError && esRechazoDeComision(err)) {
        return fallo(res, `Checkout de la orden ${orden.id} (error 2059: `
          + 'Mercado Pago no admite application_fee en este cobro. Revisa que la '
          + 'aplicación de MP esté creada con el modelo de integración '
          + '"Marketplace" y que el vendedor no sea la cuenta dueña de la '
          + 'aplicación)', err, {
          status: 409,
          mensaje: 'No pudimos cobrar este pedido por una configuración de la '
                 + 'plataforma. No es tu tarjeta: no vuelvas a intentarlo, ya '
                 + 'estamos avisados.',
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

  // ─── 6b. Checkout con la cuenta de Mercado Pago del comprador ──
  //
  // El otro carril de cobro de la MISMA orden. En vez de tokenizar una
  // tarjeta en la app, se crea una preferencia en la cuenta del vendedor y
  // se manda al comprador a Mercado Pago, donde entra con sus credenciales
  // y paga con lo que tenga (saldo, sus tarjetas guardadas allí, meses sin
  // intereses…). Nosotros no vemos nada de eso.
  //
  // Esto NO es migrar a Checkout Pro: el pago con tarjeta dentro de la app
  // sigue existiendo igual, y las dos rutas cobran la misma orden, con el
  // mismo total recalculado en el servidor y la misma comisión.
  //
  // El límite es más holgado que el de /checkout porque aquí no hay nada
  // que probar en lote: crear una preferencia no dice si una tarjeta sirve.
  // Existe solo para que nadie llene la cuenta del vendedor de preferencias.
  app.post('/api/payments/checkout/wallet', requireAuth,
    limitePorComprador({ minutos: 15, max: 20, soloSiSalioAMp: true }), async (req, res) => {
    if (!cfg.assertConfigurado(res)) return;

    const { order_id: orderId } = req.body || {};
    if (!orderId) {
      return res.status(400).json({ error: 'Faltan datos para procesar el pago.' });
    }

    const preparado = await prepararCobro(req, res, orderId, { metodo: 'cuenta_mp' });
    if (!preparado) return;
    const {
      orden, comprador, vendedor, total, comision, preferenciaViva, usuarioMpVendedor,
    } = preparado;

    // Ya hay una preferencia pagable para esta orden: se devuelve ESA. Crear
    // una segunda dejaría dos enlaces vivos capaces de cobrar lo mismo, y
    // basta con que alguien tenga las dos pestañas abiertas para pagar dos
    // veces. Es también lo que hace que volver a tocar "Pagar" tras salir al
    // navegador sea inofensivo.
    if (preferenciaViva?.initPoint) {
      // La misma comprobación que al crearla. NO es redundante: este camino
      // no pasa por `elegirInitPoint`, así que un enlace guardado por una
      // versión anterior del código —o por un `MP_USE_SANDBOX_INIT_POINT`
      // que ya se quitó— se seguiría entregando indefinidamente sin que
      // ninguna guarda lo mirara. Ya pasó: las preferencias creadas mientras
      // el código forzaba sandbox quedaron guardadas con ese enlace.
      //
      // Aquí se responde en vez de lanzar: esta rama está FUERA del
      // try/catch del handler, y una excepción en un handler async de
      // Express no la recoge nadie — la petición se quedaría colgada.
      const motivo = motivoEnlaceInutilizable(preferenciaViva.initPoint);
      if (motivo) {
        console.error(
          `[pagos] Orden ${orden.id}: la preferencia guardada no se puede entregar `
          + `(${motivo}). Se creó con una configuración que ya no está vigente. `
          + 'Se podrá pagar en cuanto caduque y se cree una nueva.',
        );
        return res.status(502).json({
          error: 'No se pudo iniciar el pago. Vuelve a intentarlo en unos minutos.',
        });
      }

      return res.json({
        orderId: orden.id,
        preferenceId: preferenciaViva.id,
        initPoint: preferenciaViva.initPoint,
        amount: total,
      });
    }

    // Reservada pero sin enlace todavía: otra petición de esta misma orden
    // está hablando con Mercado Pago ahora mismo. No se crea una segunda
    // —serían dos enlaces vivos— y tampoco se puede devolver la suya, que
    // aún no existe.
    if (preferenciaViva) {
      return res.status(409).json({
        error: 'Ya estamos preparando tu pago. Espera unos segundos e intenta de nuevo.',
        motivo: 'preferencia_en_curso',
      });
    }

    try {
      const tokenVendedor = await tokenVigenteDeVendedor(orden.vendor_id);
      if (!tokenVendedor?.accessToken) {
        return res.status(409).json({
          error: `${vendedor?.name || 'Este vendedor'} necesita reconectar su cuenta de pagos.`,
        });
      }

      const vuelta = `${cfg.config.appPublicUrl}/api/payments/wallet/return`;

      // Mismo criterio que el cobro con tarjeta: si la comisión no se puede
      // cobrar, el campo no se manda. Aquí MP es más traicionero — una
      // preferencia con un marketplace_fee que no aplica se crea SIN error
      // y el comprador paga: lo que falla en silencio es el reparto.
      const comisionAEnviar = await comisionCobrable(
        comision, tokenVendedor.mpUserId, `Orden ${orden.id} (wallet)`,
      );

      // La preferencia se arma desde `orden.items`, no desde el body: es lo
      // que hace que el desglose que ve el comprador en Mercado Pago sea el
      // mismo que vio en la app. `unit_price` sale de order_items, donde
      // quedó CONGELADO al crear la orden — así que si el vendedor cambió el
      // precio (o el descuento) desde entonces, se cobra el acordado.
      // Ventana en la que Mercado Pago aceptará este pago. Es también el
      // tiempo que la orden queda bloqueada para los demás métodos, así que
      // es un equilibrio: de más, quien abandona el pago se queda esperando
      // para poder pagar con tarjeta; de menos, no da tiempo a completar un
      // checkout con 3-D Secure de por medio.
      const caduca = new Date(Date.now() + VENTANA_PREFERENCIA_MS);

      // El candado se echa ANTES de hablar con Mercado Pago, porque la
      // carrera ocurre justo durante esa espera: Node atiende otra petición
      // mientras tanto, y sin esto las dos llegarían a crear su propia
      // preferencia. De dos simultáneas, exactamente una entra aquí.
      if (!store.reservarPreferencia(orden.id, caduca)) {
        return res.status(409).json({
          error: 'Ya estamos preparando tu pago. Espera unos segundos e intenta de nuevo.',
          motivo: 'preferencia_en_curso',
        });
      }

      // Marca para el límite de intentos: a partir de aquí la petición sí
      // consume cuota, porque sí crea una preferencia en la cuenta del
      // vendedor. Se pone ANTES de la llamada para que un fallo de MP
      // también cuente: si no, un error repetible daría intentos infinitos.
      res.locals.salioAMercadoPago = true;

      // El payload se arma aparte para poder registrarlo tal cual salió.
      // Reconstruirlo en el log sería peor que no tenerlo: acabaría
      // divergiendo de lo que de verdad se envió, que es justo el dato que
      // hace falta cuando MP acepta la preferencia y su checkout falla.
      const payloadPreferencia = {
        // La clave lleva la ventana, no solo la orden. Atada solo a la
        // orden, Mercado Pago devolvería para siempre la PRIMERA
        // preferencia: en cuanto caducara, esa orden quedaría imposible de
        // pagar por este camino y sin ningún error que lo explicara.
        //
        // Y no puede ser un valor aleatorio: dos toques seguidos al botón
        // crearían dos preferencias vivas, que es el cobro duplicado que
        // todo este bloque existe para evitar. El reintento dentro de la
        // misma ventana tiene que colapsar en la misma preferencia.
        idempotencyKey: `pref-${orden.id}-${Math.floor(Date.now() / VENTANA_PREFERENCIA_MS)}`,
        preferencia: {
          items: orden.items.map(item => ({
            id: item.product_id,
            title: String(item.title_snapshot || 'Producto').slice(0, 250),
            quantity: item.quantity,
            unit_price: item.unit_price,
            currency_id: orden.currency,
          })),
          // Con un vendedor de PRUEBA el correo del comprador se omite a
          // propósito. Mercado Pago rechaza los pagos de prueba cuyo
          // `payer.email` no corresponde a la cuenta con la que se entra al
          // checkout, y el correo de Mercadito nunca es el del usuario de
          // prueba comprador (`test_user_…@testuser.com`). Sin el campo, MP
          // usa el de la sesión. En producción sí va: ahí el correo es el
          // bueno y quitarlo obligaría a escribirlo a mano.
          payer: esCuentaDePrueba(usuarioMpVendedor)
            ? undefined
            : { email: comprador.email },

          // El split, con el nombre que tiene en ESTE endpoint. En
          // /v1/payments se llama `application_fee`; aquí `marketplace_fee`.
          // Escribir el otro no da error: simplemente no se cobra comisión.
          marketplace_fee: comisionAEnviar > 0 ? comisionAEnviar : undefined,

          // Mismo external_reference que el cobro con tarjeta. Es lo que
          // permite que el webhook —que ya resuelve la orden por este
          // campo— concilie este pago sin una sola línea nueva.
          external_reference: orden.id,
          notification_url: `${cfg.config.appPublicUrl}/api/payments/webhook`,
          statement_descriptor: 'MERCADITOUM',

          back_urls: {
            success: `${vuelta}?orden=${encodeURIComponent(orden.id)}&r=ok`,
            pending: `${vuelta}?orden=${encodeURIComponent(orden.id)}&r=pendiente`,
            failure: `${vuelta}?orden=${encodeURIComponent(orden.id)}&r=error`,
          },
          auto_return: 'approved',

          // Sin caducidad, una preferencia abandonada sigue siendo pagable
          // días después, cuando el producto ya se vendió a otra persona y
          // el stock que se comprobó arriba no significa nada.
          expires: true,
          expiration_date_to: fechaMp(caduca),
        },
      };

      const preferencia = await mp.crearPreferencia({
        accessTokenVendedor: tokenVendedor.accessToken,
        ...payloadPreferencia,
      });

      registrarDiagnosticoPreferencia({
        orden,
        payload: payloadPreferencia.preferencia,
        respuesta: preferencia,
        usuarioMpVendedor,
      });

      const initPoint = elegirInitPoint({ orden, preferencia, usuarioMpVendedor });

      // Qué enlace se entregó de verdad. La línea de arriba dice qué se
      // DECIDIÓ; esta dice qué salió. "Lo probamos" y "creemos que lo
      // probamos" son cosas distintas cuando se descartan hipótesis.
      console.log(
        `[pagos][diag] Orden ${orden.id}: enlace devuelto al comprador: ${initPoint || '(ninguno)'}`,
      );

      if (!initPoint) {
        // Sin enlace no se puede mandar a nadie a pagar, pero si Mercado
        // Pago devolvió un id, esa preferencia EXISTE y puede ser pagable.
        // Se apunta para que el bloqueo la tenga en cuenta: soltar aquí el
        // candado dejaría cobrar con tarjeta una orden con un enlace de
        // pago vivo del que no sabríamos nada.
        if (preferencia?.id) {
          store.guardarPreferenciaDeOrden(orden.id, {
            preferenceId: preferencia.id, initPoint: '', expiraEn: caduca,
          });
        }
        throw new mp.MpError('Preferencia creada sin init_point');
      }

      // Se apunta ANTES de responder. Si se guardara después —o no se
      // guardara— existiría una preferencia pagable en Mercado Pago de la
      // que este servidor no sabe nada, y el bloqueo del cobro con tarjeta
      // no la vería: justo el agujero de cobro duplicado.
      store.guardarPreferenciaDeOrden(orden.id, {
        preferenceId: preferencia.id,
        initPoint,
        expiraEn: caduca,
      });

      // Última red antes de que la URL salga de este proceso. Va DESPUÉS de
      // apuntarla por lo mismo que el caso de arriba: la preferencia ya
      // existe en MP y tiene que quedar registrada aunque esto lance.
      verificarEnlaceCoherente({ orden, url: initPoint });

      console.log(`[pagos] Orden ${orden.id}: preferencia ${preferencia.id} creada`);

      // Se comprueba contra MP qué quedó guardado de verdad. Va antes de
      // responder —y no en segundo plano— para que el log del fallo salga
      // junto al de la creación: perseguir un problema de pagos con las dos
      // mitades separadas en el tiempo es la diferencia entre diagnosticarlo
      // y adivinarlo. Cuesta una llamada más a MP en un flujo que ya está
      // esperando a MP, y no puede fallar (ver la función).
      await comprobarPreferenciaGuardada({
        orden,
        preferenciaId: preferencia.id,
        comisionEnviada: comisionAEnviar > 0 ? comisionAEnviar : 0,
        accessTokenVendedor: tokenVendedor.accessToken,
      });

      // NO se toca el estado de la orden: crear una preferencia no es haber
      // pagado. Quien la mueve es el webhook, igual que con la tarjeta.
      res.json({
        orderId: orden.id,
        preferenceId: preferencia.id,
        initPoint,
        amount: total,
      });
    } catch (err) {
      // El candado solo se suelta cuando Mercado Pago RECHAZÓ la petición
      // (4xx): ahí es seguro que no creó nada. Ante un timeout o un 5xx no
      // se sabe si la preferencia llegó a existir, y soltarlo permitiría
      // cobrar con tarjeta una orden que quizá tiene un enlace de pago
      // vivo. Quedarse bloqueado unos minutos es recuperable; un cobro
      // duplicado no. `liberarPreferencia` no hace nada si ya se guardó una
      // preferencia, así que no puede desbloquear un enlace real.
      if (err instanceof mp.MpError && err.status >= 400 && err.status < 500) {
        store.liberarPreferencia(orden.id);
      }

      if (err instanceof mp.MpError && (err.status === 401 || err.status === 403)) {
        conexion.desconectar(orden.vendor_id, {
          motivo: 'Mercado Pago rechazó el token del vendedor al crear la preferencia',
          por: 'token_check',
        });
        store.marcarRequiereOtroMetodo(orden.id);
        avisarPagoNoDisponible(orden, vendedor);
        return fallo(res, `Preferencia de la orden ${orden.id} (token revocado)`, err, {
          status: 409,
          mensaje: `${vendedor?.name || 'Este vendedor'} ya no puede cobrar por Mercado Pago. `
                 + 'Contáctalo por chat para acordar otra forma de pago.',
        });
      }
      fallo(res, `Preferencia de la orden ${orden.id}`, err);
    }
  });

  // Puente de vuelta desde Mercado Pago hacia la app.
  //
  // Sin `requireAuth`: quien llega aquí es un navegador que viene de un
  // redirect de MP, sin la sesión de la app. Y da igual, porque esta ruta no
  // consulta ni modifica nada — solo pinta un botón hacia el deep link. El
  // estado real del pago lo resuelve la app preguntando por su orden con su
  // propio token, y la verdad la escribe el webhook.
  //
  // Deliberadamente NO se cree lo que dice el parámetro `r`: es el resultado
  // que afirma un redirect, y un redirect lo puede fabricar cualquiera
  // escribiendo la URL a mano. Solo cambia el texto que se lee mientras la
  // app termina de comprobarlo.
  app.get('/api/payments/wallet/return', (req, res) => {
    const orden = String(req.query.orden || '');
    const resultado = String(req.query.r || '');

    const { titulo, texto, ok } = resultado === 'ok'
      ? { titulo: 'Pago enviado', texto: 'Vuelve a Mercadito UM para ver la confirmación.', ok: true }
      : resultado === 'pendiente'
        ? { titulo: 'Pago en revisión', texto: 'Mercado Pago está revisando tu pago. Vuelve a la app para seguirlo.', ok: true }
        : { titulo: 'Pago no completado', texto: 'No se completó el pago. Puedes intentarlo de nuevo desde la app.', ok: false };

    res.send(paginaPuente({
      titulo,
      texto,
      ok,
      deepLink: `${cfg.config.appDeepLinkScheme}://payments/wallet-return`
        + `?orden=${encodeURIComponent(orden)}`,
    }));
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
    // Antes que nada, y a propósito: una notificación que llega y se rechaza
    // deja rastro, pero una que NUNCA llega no deja ninguno. Sin esta línea
    // "MP no nos avisó" y "nos avisó y lo tiramos" se ven igual desde el
    // log, y son problemas completamente distintos (uno es de red o de
    // notification_url, el otro es del secreto de firma).
    //
    // Solo metadatos: nada del cuerpo, que aquí todavía no está autenticado.
    // Todo pasa por `paraLog`: son valores de quien llame, sin firmar
    // todavía. Un salto de línea aquí escribiría una línea falsa en el log,
    // y este log es donde miramos para saber si un pago entró.
    //
    // El `if` es para no pagar los cuatro `paraLog` —cada uno un regex— en
    // cada notificación cuando la traza está apagada, que es lo normal. Es
    // el único sitio donde compensa: este corre en TODAS las entregas, y MP
    // reenvía cada evento varias veces.
    if (cfg.depuracionPagos()) {
      cfg.traza(
        `webhook recibido: topic=${cfg.paraLog(req.body?.type || req.body?.topic
          || req.query.type || req.query.topic)} `
        + `action=${cfg.paraLog(req.body?.action)} `
        + `data.id=${cfg.paraLog(req.body?.data?.id || req.query['data.id'])} `
        + `x-request-id=${cfg.paraLog(req.headers['x-request-id'])}`,
      );
    }

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
      //
      // Con traza porque este `return` silencioso se parece demasiado a un
      // éxito: si MP empezara a mandar los pagos con otro topic, todo
      // seguiría respondiendo 200 y ninguna orden se marcaría jamás.
      cfg.traza(
        `webhook ignorado: topic=${cfg.paraLog(topic)} data.id=${cfg.paraLog(paymentId)}`,
      );
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
