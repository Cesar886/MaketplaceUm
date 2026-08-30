// Verificación de los idToken que emite Google Sign-In en la app.
//
// El cliente NUNCA es autoridad de identidad: la app manda el `idToken` que
// le dio Google y es este módulo el que comprueba, contra las claves
// públicas de Google, que ese token (a) lo firmó Google, (b) va dirigido a
// UNA de nuestras audiencias y (c) no expiró. Aceptar el correo que mande la
// app sin esto sería tan seguro como creerle a cualquiera que diga ser otro.
//
// ─── Qué hay que poner en backend/.env ───────────────────────
//
//   GOOGLE_CLIENT_IDS=<android>.apps.googleusercontent.com,<ios>...,<web>...
//   GOOGLE_ALLOWED_DOMAINS=            (vacío = sin restricción de dominio)
//
// TODO(credenciales): pegar en backend/.env los Client ID de OAuth generados
// en Google Cloud Console. Van los TRES (Android, iOS y Web) separados por
// coma, porque el `aud` del token cambia según la plataforma desde la que se
// autenticó el usuario. Mientras esté vacío, /api/auth/google responde 503 y
// el resto del login (correo/contraseña) sigue funcionando igual.

const { OAuth2Client } = require('google-auth-library');

/** Error con un código y un status HTTP que la ruta puede devolver tal cual. */
class GoogleAuthError extends Error {
  constructor(mensaje, codigo, status) {
    super(mensaje);
    this.name = 'GoogleAuthError';
    this.codigo = codigo;
    this.status = status;
  }
}

/**
 * Parte una variable de entorno separada por comas en una lista limpia.
 * Se lee en cada llamada (no se cachea al cargarse el módulo) para que los
 * tests puedan cambiar el entorno y para que un `pm2 restart --update-env`
 * baste para cambiar la configuración.
 */
function listaDeEntorno(nombre) {
  return (process.env[nombre] || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);
}

/** Client IDs de OAuth aceptados como `aud` del idToken. */
function audiencias() {
  return listaDeEntorno('GOOGLE_CLIENT_IDS');
}

/** ¿Hay credenciales suficientes para verificar tokens de Google? */
function estaConfigurado() {
  return audiencias().length > 0;
}

/**
 * Dominios de correo permitidos, o lista vacía = sin restricción.
 *
 * Está APAGADO por defecto a propósito: en este marketplace las cuentas se
 * registran con cualquier correo y lo institucional se comprueba aparte, por
 * OTP, durante la verificación (ver routes/verificacion.js). Encenderlo
 * dejaría fuera a negocios y particulares, que no tienen correo UM.
 */
function dominiosPermitidos() {
  return listaDeEntorno('GOOGLE_ALLOWED_DOMAINS').map(d => d.toLowerCase());
}

/**
 * ¿El correo pertenece a un dominio permitido?
 *
 * Compara el dominio COMPLETO (lo que va después del último arroba), no un
 * sufijo: con `endsWith`, un dominio como `evil-um.edu.mx` o
 * `um.edu.mx.evil.com` pasaría el filtro.
 */
function dominioPermitido(email) {
  const permitidos = dominiosPermitidos();
  if (permitidos.length === 0) return true;
  if (typeof email !== 'string') return false;
  const i = email.lastIndexOf('@');
  if (i === -1) return false;
  return permitidos.includes(email.slice(i + 1).toLowerCase());
}

let clienteCache = null;
let clienteCacheKey = null;

function cliente() {
  const key = audiencias().join(',');
  if (clienteCacheKey !== key) {
    clienteCache = new OAuth2Client();
    clienteCacheKey = key;
  }
  return clienteCache;
}

/**
 * Verifica un idToken de Google y devuelve el perfil que afirma.
 *
 * @throws {GoogleAuthError} si falta configuración, el token no es válido,
 *   el correo no está verificado por Google, o el dominio no está permitido.
 * @returns {Promise<{sub: string, email: string, nombre: string, foto: string|null}>}
 */
async function verificarIdToken(idToken) {
  if (!estaConfigurado()) {
    throw new GoogleAuthError(
      'El inicio de sesión con Google no está configurado en el servidor.',
      'GOOGLE_NO_CONFIGURADO',
      503,
    );
  }
  if (!idToken || typeof idToken !== 'string') {
    throw new GoogleAuthError('idToken requerido', 'GOOGLE_TOKEN_INVALIDO', 401);
  }

  let payload;
  try {
    const ticket = await cliente().verifyIdToken({
      idToken,
      audience: audiencias(),
    });
    payload = ticket.getPayload();
  } catch (err) {
    // El mensaje real de la librería (audiencia equivocada, token expirado,
    // firma mala) va al log y no a la respuesta: al cliente le basta saber
    // que el token no sirve.
    console.warn('[google-auth] idToken rechazado:', err.message);
    throw new GoogleAuthError('Token de Google inválido.', 'GOOGLE_TOKEN_INVALIDO', 401);
  }

  if (!payload || !payload.sub || !payload.email) {
    throw new GoogleAuthError('Token de Google inválido.', 'GOOGLE_TOKEN_INVALIDO', 401);
  }

  // Google marca `email_verified: false` en cuentas cuyo correo no ha
  // demostrado ser suyo (típico de cuentas de Workspace recién creadas o de
  // alias). Sin esta comprobación, alguien podría reclamar el correo de otra
  // persona y quedarse con su cuenta del marketplace por coincidencia de email.
  if (payload.email_verified !== true) {
    throw new GoogleAuthError(
      'Google no ha verificado ese correo.',
      'GOOGLE_EMAIL_NO_VERIFICADO',
      401,
    );
  }

  if (!dominioPermitido(payload.email)) {
    throw new GoogleAuthError(
      'Ese correo no pertenece a un dominio permitido.',
      'GOOGLE_DOMINIO_NO_PERMITIDO',
      403,
    );
  }

  return {
    sub: payload.sub,
    email: payload.email,
    nombre: payload.name || '',
    foto: payload.picture || null,
  };
}

module.exports = {
  GoogleAuthError,
  audiencias,
  estaConfigurado,
  dominiosPermitidos,
  dominioPermitido,
  verificarIdToken,
};
