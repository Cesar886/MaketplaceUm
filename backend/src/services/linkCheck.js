// Comprobación de que el link de red social de un negocio realmente existe.
//
// Deliberadamente TOLERANTE: la validación fuerte es el dominio
// (validarLinkRedSocial en validation/verificacion.js), y esta comprobación
// solo descarta URLs inventadas dentro de un dominio válido. Facebook e
// Instagram responden 302 a login, 403 o el status 999 de bloqueo a cualquier
// petición automática, así que exigir un 200 rechazaría negocios legítimos.
//
// Solo se rechaza cuando la respuesta prueba que el recurso NO está ahí
// (404/410), cuando el servidor está caído (5xx), o cuando no hay respuesta
// (DNS, red, timeout).

const TIMEOUT_MS = 5000;

// Sin User-Agent de navegador varios sitios cortan la conexión de inmediato.
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

async function pedir(url, metodo, timeoutMs, cabecerasExtra = {}) {
  const abortar = new AbortController();
  const temporizador = setTimeout(() => abortar.abort(), timeoutMs);
  try {
    return await fetch(url, {
      method: metodo,
      redirect: 'follow',
      signal: abortar.signal,
      headers: { 'User-Agent': USER_AGENT, ...cabecerasExtra },
    });
  } finally {
    clearTimeout(temporizador);
  }
}

/**
 * @returns {Promise<{ ok: boolean, motivo: string|null }>}
 */
async function verificarLink(url, { timeoutMs = TIMEOUT_MS } = {}) {
  let respuesta;
  try {
    respuesta = await pedir(url, 'HEAD', timeoutMs);

    // Algunos servidores no implementan HEAD. Se reintenta con GET pidiendo
    // solo el primer byte, para no descargar la página entera.
    if (respuesta.status === 405 || respuesta.status === 501) {
      respuesta = await pedir(url, 'GET', timeoutMs, { Range: 'bytes=0-0' });
    }
  } catch (err) {
    if (err.name === 'AbortError' || err.name === 'TimeoutError') {
      return { ok: false, motivo: 'El link no respondió a tiempo. Revisa que sea correcto.' };
    }
    return { ok: false, motivo: 'No pudimos abrir el link. Revisa que sea correcto.' };
  }

  if (respuesta.status === 404 || respuesta.status === 410) {
    return { ok: false, motivo: 'La página del link no existe.' };
  }
  if (respuesta.status >= 500 && respuesta.status < 600) {
    return { ok: false, motivo: 'El link no está disponible en este momento. Inténtalo de nuevo.' };
  }
  return { ok: true, motivo: null };
}

module.exports = { verificarLink, TIMEOUT_MS };
