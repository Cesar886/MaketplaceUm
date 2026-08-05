// Comprobación de que el link de red social de un negocio realmente existe.
//
// Deliberadamente TOLERANTE con el resultado: la validación fuerte es el
// dominio (validarLinkRedSocial en validation/verificacion.js), y esta
// comprobación solo descarta URLs inventadas dentro de un dominio válido.
// Facebook e Instagram responden 302 a login, 403 o el status 999 de bloqueo
// a cualquier petición automática, así que exigir un 200 rechazaría negocios
// legítimos. Solo se rechaza cuando la respuesta prueba que el recurso no
// está ahí (404/410), el servidor está caído (5xx), o no hay respuesta.
//
// ESTRICTA, en cambio, con el DESTINO. Esta es la única parte del sistema
// donde un dato del usuario decide a qué dirección se conecta el servidor, y
// varios hosts de la whitelist son acortadores (maps.app.goo.gl) que pueden
// redirigir a cualquier parte. Sin control, un short link apuntando a
// 127.0.0.1 o a 169.254.169.254 (metadata de la nube) convertiría este
// endpoint en un escáner de la red interna: aunque solo devuelve "responde /
// no responde", ese booleano basta para mapear qué servicios existen.
//
// Por eso las redirecciones se siguen A MANO y cada salto se valida con
// `comprobarDestino` (ver services/redDestino.js) antes de conectarse.

const { esDestinoPermitido } = require('./redDestino');

const TIMEOUT_MS = 5000;
const MAX_REDIRECCIONES = 5;

// Sin User-Agent de navegador varios sitios cortan la conexión de inmediato.
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

const MOTIVO_DESTINO_INVALIDO =
  'No se puede abrir ese link. Revisa que sea la dirección pública de tu página.';

async function pedir(url, metodo, timeoutMs, cabecerasExtra = {}) {
  const abortar = new AbortController();
  const temporizador = setTimeout(() => abortar.abort(), timeoutMs);
  try {
    return await fetch(url, {
      method: metodo,
      // Manual: seguir automáticamente saltaría el control de destino en
      // cada salto, que es justo lo que evita el SSRF.
      redirect: 'manual',
      signal: abortar.signal,
      headers: { 'User-Agent': USER_AGENT, ...cabecerasExtra },
    });
  } finally {
    clearTimeout(temporizador);
  }
}

const esRedireccion = status =>
  status === 301 || status === 302 || status === 303 || status === 307 || status === 308;

/**
 * @param {string} url
 * @param {{ timeoutMs?: number, comprobarDestino?: (host: string) => Promise<boolean> }} opciones
 *   `comprobarDestino` se inyecta para poder probar el comportamiento frente
 *   a redirecciones contra un servidor local (que por definición vive en una
 *   dirección privada). El guardián real es el default.
 * @returns {Promise<{ ok: boolean, motivo: string|null }>}
 */
async function verificarLink(
  url,
  { timeoutMs = TIMEOUT_MS, comprobarDestino = esDestinoPermitido } = {},
) {
  let actual = url;

  for (let salto = 0; salto <= MAX_REDIRECCIONES; salto++) {
    let parsed;
    try {
      parsed = new URL(actual);
    } catch {
      return { ok: false, motivo: MOTIVO_DESTINO_INVALIDO };
    }
    // Una redirección puede apuntar a file://, gopher:// u otros esquemas que
    // no tienen nada que hacer aquí.
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
      return { ok: false, motivo: MOTIVO_DESTINO_INVALIDO };
    }
    if (!(await comprobarDestino(parsed.hostname))) {
      return { ok: false, motivo: MOTIVO_DESTINO_INVALIDO };
    }

    let respuesta;
    try {
      respuesta = await pedir(actual, 'HEAD', timeoutMs);

      // Algunos servidores no implementan HEAD. Se reintenta con GET pidiendo
      // solo el primer byte, para no descargar la página entera.
      if (respuesta.status === 405 || respuesta.status === 501) {
        respuesta = await pedir(actual, 'GET', timeoutMs, { Range: 'bytes=0-0' });
      }
    } catch (err) {
      if (err.name === 'AbortError' || err.name === 'TimeoutError') {
        return { ok: false, motivo: 'El link no respondió a tiempo. Revisa que sea correcto.' };
      }
      return { ok: false, motivo: 'No pudimos abrir el link. Revisa que sea correcto.' };
    }

    if (esRedireccion(respuesta.status)) {
      const destino = respuesta.headers.get('location');
      if (!destino) {
        // Redirección sin destino: no hay a dónde seguir, pero el host
        // respondió, así que existe.
        return { ok: true, motivo: null };
      }
      // Location puede ser relativa; se resuelve contra la URL actual.
      actual = new URL(destino, actual).toString();
      continue;
    }

    if (respuesta.status === 404 || respuesta.status === 410) {
      return { ok: false, motivo: 'La página del link no existe.' };
    }
    if (respuesta.status >= 500 && respuesta.status < 600) {
      return { ok: false, motivo: 'El link no está disponible en este momento. Inténtalo de nuevo.' };
    }
    return { ok: true, motivo: null };
  }

  return {
    ok: false,
    motivo: 'El link tiene demasiadas redirecciones. Usa la dirección directa de tu página.',
  };
}

module.exports = { verificarLink, TIMEOUT_MS, MAX_REDIRECCIONES };
