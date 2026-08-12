/**
 * Obtención del access_token vigente de un vendedor.
 *
 * Los tokens de OAuth de Mercado Pago caducan (típicamente a los 180 días).
 * Si se deja caducar, los cobros de ese vendedor empiezan a fallar con un
 * 401 opaco y nadie lo relaciona con el token. Aquí se renueva de forma
 * anticipada usando el refresh_token.
 */

const store = require('./store');
const { refrescarTokenVendedor, MpError } = require('./mpClient');

// Margen de renovación: si caduca dentro de los próximos 7 días, se renueva
// ya. Esperar al último momento significa que el primer comprador del día
// de la caducidad se come el fallo.
const MARGEN_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * @returns {Promise<{accessToken: string, mpUserId: string}|null>}
 *   null si el vendedor no tiene cuenta conectada o si el token caducó y no
 *   se pudo renovar (hace falta que vuelva a autorizar).
 */
async function tokenVigenteDeVendedor(sellerId) {
  const cuenta = store.getCuentaVendedorConToken(sellerId);
  if (!cuenta || !cuenta.accessToken) return null;

  const expira = cuenta.mp_token_expires_at
    ? new Date(cuenta.mp_token_expires_at).getTime()
    : null;
  const caducaPronto = expira !== null && Number.isFinite(expira)
    && expira - Date.now() < MARGEN_MS;

  if (!caducaPronto) {
    return { accessToken: cuenta.accessToken, mpUserId: cuenta.mp_user_id };
  }

  if (!cuenta.refreshToken) {
    console.warn(`[pagos] Token de ${sellerId} por caducar y sin refresh_token`);
    return { accessToken: cuenta.accessToken, mpUserId: cuenta.mp_user_id };
  }

  try {
    // Endpoint: POST /oauth/token (grant_type=refresh_token)
    const datos = await refrescarTokenVendedor(cuenta.refreshToken);
    if (!datos?.access_token) throw new Error('Respuesta sin access_token');

    store.actualizarTokensVendedor(sellerId, {
      accessToken: datos.access_token,
      refreshToken: datos.refresh_token,
      expiresIn: datos.expires_in,
    });
    console.log(`[pagos] Token de ${sellerId} renovado`);
    return { accessToken: datos.access_token, mpUserId: cuenta.mp_user_id };
  } catch (err) {
    const detalle = err instanceof MpError ? JSON.stringify(err.detalle) : err.message;
    console.error(`[pagos] No se pudo renovar el token de ${sellerId}: ${detalle}`);
    // Se devuelve el token viejo: puede que aún funcione, y fallar aquí
    // dejaría al vendedor sin cobrar por un problema que quizá no existe.
    return { accessToken: cuenta.accessToken, mpUserId: cuenta.mp_user_id };
  }
}

module.exports = { tokenVigenteDeVendedor };
