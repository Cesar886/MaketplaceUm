/**
 * ÚNICO punto del backend que habla con la API de Mercado Pago.
 *
 * Todo lo que salga hacia api.mercadopago.com pasa por aquí, para que
 * auditar la integración sea leer un archivo. Cada función documenta:
 * qué endpoint llama, con qué credencial, y por qué.
 *
 * Hay tres credenciales distintas y confundirlas es el error clásico:
 *
 *   1. MP_PUBLIC_KEY      → solo el cliente (Flutter), solo para tokenizar.
 *   2. MP_ACCESS_TOKEN    → nuestra plataforma. Customers y tarjetas.
 *   3. token del VENDEDOR → cobrar en su nombre con comisión. Solo en
 *                           crearPago(), y sale cifrado de la base de datos.
 *
 * REGLA INVIOLABLE DE LOGS: en este archivo no se imprime jamás un token, un
 * card_token, un número de tarjeta ni un CVV — ni en modo debug. `redactar()`
 * limpia cualquier objeto antes de que se acerque a un console.*.
 */

const { config, MP_API_BASE, MP_AUTH_BASE, redirectUri } = require('./config');

/** Error de la API de MP. Su detalle es SOLO para el log del servidor. */
class MpError extends Error {
  constructor(mensaje, { status, detalle, causa } = {}) {
    super(mensaje);
    this.name = 'MpError';
    this.status = status;
    this.detalle = detalle;
    this.causa = causa;
  }
}

// Claves cuyo valor nunca puede aparecer en un log, venga de donde venga.
const CLAVES_SENSIBLES = new Set([
  'access_token', 'refresh_token', 'accessToken', 'refreshToken',
  'token', 'card_token', 'cardToken', 'security_code', 'securityCode',
  'cvv', 'card_number', 'cardNumber', 'number', 'public_key', 'client_secret',
  'authorization', 'password',
]);

/** Copia un objeto sustituyendo por '[REDACTADO]' todo lo sensible. */
function redactar(valor, profundidad = 0) {
  if (profundidad > 6 || valor == null) return valor;
  if (Array.isArray(valor)) return valor.map(v => redactar(v, profundidad + 1));
  if (typeof valor !== 'object') return valor;
  const salida = {};
  for (const [clave, v] of Object.entries(valor)) {
    salida[clave] = CLAVES_SENSIBLES.has(clave.toLowerCase())
      ? '[REDACTADO]'
      : redactar(v, profundidad + 1);
  }
  return salida;
}

/**
 * Petición a MP. `accessToken` decide en nombre de quién se actúa.
 * Nunca propaga el cuerpo crudo del error hacia quien llama: lo envuelve en
 * un MpError cuyo `.message` es apto para el log y cuyo `.detalle` queda
 * disponible para diagnosticar, pero que las rutas nunca reenvían al cliente.
 */
async function peticion(metodo, ruta, { accessToken, body, headers = {}, base = MP_API_BASE } = {}) {
  const url = `${base}${ruta}`;
  let res;
  try {
    res = await fetch(url, {
      method: metodo,
      headers: {
        'Content-Type': 'application/json',
        ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
        ...headers,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(20000),
    });
  } catch (err) {
    // Red caída, DNS, timeout: nunca llegó a haber respuesta.
    throw new MpError(`No se pudo contactar a Mercado Pago (${metodo} ${ruta})`, { causa: err.message });
  }

  const texto = await res.text();
  let datos = null;
  try {
    datos = texto ? JSON.parse(texto) : null;
  } catch {
    datos = null; // MP devolvió algo que no es JSON (un 502 de su CDN, p.ej.).
  }

  if (!res.ok) {
    // El detalle va redactado incluso aquí: los errores de MP a veces hacen
    // eco de parte del payload enviado.
    throw new MpError(`Mercado Pago respondió ${res.status} en ${metodo} ${ruta}`, {
      status: res.status,
      detalle: datos ? redactar(datos) : texto.slice(0, 500),
    });
  }
  return datos;
}

// ─── OAuth del vendedor ─────────────────────────────────────
//
// Flujo "Marketplace": el vendedor autoriza a nuestra aplicación a cobrar en
// su nombre. Resultado: un access_token suyo que guardamos cifrado.

/**
 * URL de autorización a la que se manda al vendedor.
 * Endpoint: auth.mercadopago.com.mx/authorization (navegador, no API).
 * Credencial: MP_CLIENT_ID (público por naturaleza, va en la URL).
 */
function urlAutorizacion(state) {
  const params = new URLSearchParams({
    client_id: config.clientId,
    response_type: 'code',
    platform_id: 'mp',
    state,
    redirect_uri: redirectUri(),
  });
  return `${MP_AUTH_BASE}/authorization?${params.toString()}`;
}

/**
 * Canjea el `code` del callback por los tokens del vendedor.
 * Endpoint: POST /oauth/token
 * Credencial: MP_CLIENT_ID + MP_CLIENT_SECRET (jamás salen del servidor).
 */
async function canjearCodigoOAuth(code) {
  return peticion('POST', '/oauth/token', {
    body: {
      client_id: config.clientId,
      client_secret: config.clientSecret,
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri(),
    },
  });
}

/**
 * Renueva el access_token de un vendedor antes de que caduque.
 * Endpoint: POST /oauth/token (grant_type=refresh_token)
 * Credencial: MP_CLIENT_ID + MP_CLIENT_SECRET + refresh_token del vendedor.
 */
async function refrescarTokenVendedor(refreshToken) {
  return peticion('POST', '/oauth/token', {
    body: {
      client_id: config.clientId,
      client_secret: config.clientSecret,
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
    },
  });
}

// ─── Customers y tarjetas guardadas (comprador) ─────────────
//
// Van con el token DEL VENDEDOR, no con el de la plataforma. En el modo
// marketplace de MP un Customer y sus tarjetas pertenecen a la cuenta que
// los creó: una tarjeta guardada bajo la plataforma NO es cobrable con el
// token de un vendedor — MP responde "Card Token not found". Se comprobó
// contra la API real antes de elegir este modelo.
//
// Consecuencia de producto: el comprador registra su tarjeta una vez por
// cada vendedor al que le compra. No hay forma de compartirla entre
// vendedores sin que la plataforma pase a ser quien cobra.

/**
 * Busca un Customer por email dentro de la cuenta de un vendedor.
 * Endpoint: GET /v1/customers/search
 * Credencial: access_token DEL VENDEDOR.
 */
async function buscarCustomerPorEmail(email, accessTokenVendedor) {
  const datos = await peticion('GET', `/v1/customers/search?email=${encodeURIComponent(email)}`, {
    accessToken: accessTokenVendedor,
  });
  return datos?.results?.[0] || null;
}

/**
 * Crea un Customer dentro de la cuenta de un vendedor.
 * Endpoint: POST /v1/customers
 * Credencial: access_token DEL VENDEDOR.
 */
async function crearCustomer({ email, nombre }, accessTokenVendedor) {
  return peticion('POST', '/v1/customers', {
    accessToken: accessTokenVendedor,
    body: { email, first_name: nombre || undefined },
  });
}

/**
 * Asocia una tarjeta ya tokenizada a un Customer del vendedor.
 * Endpoint: POST /v1/customers/{customer_id}/cards
 * Credencial: access_token DEL VENDEDOR.
 *
 * `token` es el card_token de un solo uso generado EN EL CLIENTE contra la
 * API pública de MP — y con la PUBLIC KEY DEL VENDEDOR, no la de la
 * plataforma: un token creado con otra public key no pertenece a esta cuenta
 * y MP lo rechaza. Nunca vemos el PAN ni el CVV: llegan a MP directo desde
 * el dispositivo. El token se usa aquí y se descarta — no se guarda.
 */
async function guardarTarjetaEnCustomer(customerId, token, accessTokenVendedor) {
  return peticion('POST', `/v1/customers/${encodeURIComponent(customerId)}/cards`, {
    accessToken: accessTokenVendedor,
    body: { token },
  });
}

/**
 * Elimina una tarjeta guardada.
 * Endpoint: DELETE /v1/customers/{customer_id}/cards/{card_id}
 * Credencial: access_token DEL VENDEDOR.
 */
async function eliminarTarjetaDeCustomer(customerId, cardId, accessTokenVendedor) {
  return peticion(
    'DELETE',
    `/v1/customers/${encodeURIComponent(customerId)}/cards/${encodeURIComponent(cardId)}`,
    { accessToken: accessTokenVendedor },
  );
}

/**
 * Comprobación barata de que un access_token de vendedor sigue siendo
 * válido. Se usa como red de seguridad cuando el webhook de revocación no
 * llegó: si el vendedor quitó la autorización desde su panel de MP, esto
 * responde 401 y la app se entera antes de intentar cobrarle a alguien.
 *
 * Endpoint: GET /users/me
 * Credencial: access_token DEL VENDEDOR.
 */
async function validarTokenVendedor(accessTokenVendedor) {
  return peticion('GET', '/users/me', { accessToken: accessTokenVendedor });
}

// ─── Cobro con split ────────────────────────────────────────

/**
 * Crea el pago. ESTE es el split: el dinero entra a la cuenta del VENDEDOR
 * y `application_fee` es lo que se queda la plataforma.
 *
 * Endpoint: POST /v1/payments
 * Credencial: access_token DEL VENDEDOR (descifrado de
 *             vendor_payment_accounts). Usar aquí MP_ACCESS_TOKEN cobraría
 *             a nuestra propia cuenta y el split no ocurriría.
 *
 * `X-Idempotency-Key` es obligatorio en la práctica: sin él, un reintento
 * por timeout de red genera un SEGUNDO cargo real al comprador. La clave va
 * atada al id de la orden, así que MP devuelve el mismo pago en vez de
 * cobrar de nuevo.
 */
async function crearPago({ accessTokenVendedor, idempotencyKey, pago }) {
  return peticion('POST', '/v1/payments', {
    accessToken: accessTokenVendedor,
    headers: { 'X-Idempotency-Key': idempotencyKey },
    body: pago,
  });
}

/**
 * Consulta un pago. Se usa desde el webhook: la notificación de MP solo
 * trae un id, y el estado SIEMPRE se lee de la API — nunca del cuerpo de la
 * notificación, que no es una fuente de verdad confiable.
 *
 * Endpoint: GET /v1/payments/{id}
 * Credencial: la del vendedor si se conoce; si no, la de la plataforma.
 */
async function obtenerPago(paymentId, accessToken) {
  return peticion('GET', `/v1/payments/${encodeURIComponent(paymentId)}`, {
    accessToken: accessToken || config.accessToken,
  });
}

module.exports = {
  MpError,
  redactar,
  urlAutorizacion,
  canjearCodigoOAuth,
  refrescarTokenVendedor,
  buscarCustomerPorEmail,
  crearCustomer,
  guardarTarjetaEnCustomer,
  eliminarTarjetaDeCustomer,
  validarTokenVendedor,
  crearPago,
  obtenerPago,
};
