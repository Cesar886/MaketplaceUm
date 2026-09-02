const jwt = require('jsonwebtoken');
const { randomUUID } = require('crypto');
const db = require('./database');

// Sin fallback: un valor por defecto silencioso (`|| 'algo-fijo'`) es
// exactamente lo que enmascaró el incidente de 2026-08 — cuando el .env no
// cargaba, el proceso arrancaba igual pero firmaba/verificaba con un secreto
// distinto al de la corrida anterior, invalidando todos los tokens ya
// emitidos sin ningún error visible al arrancar. Mejor reventar temprano.
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
  throw new Error(
    'JWT_SECRET no está definido en el entorno. Revisa que backend/.env exista ' +
    'y que PM2 lo esté cargando (pm2 restart mercadito-backend --update-env).',
  );
}
// Mitigación temporal (auditoría 2026-08, hallazgo M-04) mientras el
// tráfico siga viajando en HTTP plano (C-03): un token capturado en la red
// del campus vale 24 h en vez de una semana. NO sustituye a la revocación en
// logout ni a los refresh tokens — sin ellos, este TTL es lo único que acota
// la ventana de un token robado, y por eso no puede volver a subir hasta que
// exista una lista de revocación.
const JWT_EXPIRES_IN = '24h';

// Se fija el algoritmo en la VERIFICACIÓN, no solo al firmar. `jwt.verify`
// sin esta opción acepta cualquier algoritmo compatible con la clave, y deja
// la elección en manos de la cabecera del token — que la escribe quien lo
// manda. Con un secreto HMAC el riesgo real es acotado, pero fijarlo cuesta
// una línea y elimina la categoría entera (hallazgo M-04).
const ALGORITMO = 'HS256';

function sesionRevocada(decoded) {
  if (!decoded.jti) return false;
  try {
    const database = db.getDb();
    return !!database?.prepare(
      'SELECT 1 FROM revoked_sessions WHERE jti = ? AND expires_at > unixepoch()',
    ).get(decoded.jti);
  } catch {
    // Durante arranque/pruebas la base puede no estar inicializada todavía.
    // La firma y expiración del JWT siguen verificándose normalmente.
    return false;
  }
}

/**
 * Genera un token JWT para un usuario dado.
 * @param {string} userId - ID del usuario/seller
 * @returns {string} token JWT
 */
function generateToken(userId) {
  return jwt.sign({ sub: userId }, JWT_SECRET, {
    jwtid: randomUUID(),
    expiresIn: JWT_EXPIRES_IN,
    algorithm: ALGORITMO,
  });
}

// Los invitados conservan sus conversaciones entre sesiones (era justo lo que
// hacía el UUID en SharedPreferences que este token sustituye), así que un
// TTL de 24 h les borraría el chat cada día. El riesgo que asume este plazo
// más largo está acotado: un token anónimo no da acceso a ninguna cuenta, solo
// a las conversaciones de ese mismo invitado.
const JWT_ANON_EXPIRES_IN = '30d';

/**
 * Token de invitado: permite chatear sin cuenta.
 *
 * El identificador lo genera el SERVIDOR y nunca se acepta del cliente. Es la
 * diferencia entre probar una identidad y afirmarla: el id anónimo viaja
 * dentro de cada mensaje (`senderId`), así que cualquiera que haya leído un
 * chat conoce ids ajenos. Si este endpoint firmara el id que le pasen,
 * suplantar a un invitado sería tan fácil como copiar el suyo de un mensaje.
 *
 * El claim `anon` marca la sesión como invitada para que las rutas que exigen
 * cuenta real (pagos, verificación, perfil) puedan rechazarla; hoy solo el
 * chat acepta invitados.
 */
function generateAnonToken() {
  const anonId = `anon_${randomUUID()}`;
  return {
    anonId,
    token: jwt.sign({ sub: anonId, anon: true }, JWT_SECRET, {
      jwtid: randomUUID(),
      expiresIn: JWT_ANON_EXPIRES_IN,
      algorithm: ALGORITMO,
    }),
  };
}

/**
 * Middleware de autenticación.
 * Valida que el request tenga un Bearer token válido.
 * Si es válido, deja el payload en req.user y continúa.
 * Si no, responde 401.
 */
function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader) {
    return res.status(401).json({ error: 'Token requerido. Envía Authorization: Bearer <token>' });
  }

  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0] !== 'Bearer') {
    return res.status(401).json({ error: 'Formato de token inválido. Usa: Bearer <token>' });
  }

  const token = parts[1];

  try {
    const decoded = jwt.verify(token, JWT_SECRET, { algorithms: [ALGORITMO] });
    if (sesionRevocada(decoded)) return res.status(401).json({ error: 'SESSION_INVALIDATED', message: 'Sesión cerrada.' });
    req.user = { id: decoded.sub, anon: decoded.anon === true, jti: decoded.jti, exp: decoded.exp };
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expirado. Vuelve a iniciar sesión.' });
    }
    if (err.name === 'JsonWebTokenError' && err.message === 'invalid signature') {
      // El secreto usado para firmar el token no coincide con el JWT_SECRET
      // actual (típicamente: el .env no cargó en algún restart y el proceso
      // firmó/verificó con secretos distintos entre corridas). El token no
      // es recuperable — el usuario debe volver a loguearse.
      return res.status(401).json({ error: 'SESSION_INVALIDATED', message: 'Tu sesión expiró, inicia sesión de nuevo.' });
    }
    return res.status(401).json({ error: 'Token inválido.' });
  }
}

/**
 * Middleware de autenticación opcional.
 * Si viene un Bearer token válido, deja el payload en req.user.
 * Si no viene token o es inválido, continúa sin bloquear (req.user queda undefined).
 * Útil para endpoints públicos que exponen más datos cuando el solicitante
 * resulta ser el dueño del recurso.
 */
function optionalAuth(req, _res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader) return next();

  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0] !== 'Bearer') return next();

  try {
    const decoded = jwt.verify(parts[1], JWT_SECRET, { algorithms: [ALGORITMO] });
    if (sesionRevocada(decoded)) return next();
    req.user = { id: decoded.sub, anon: decoded.anon === true };
  } catch (err) {
    // Token ausente/expirado/inválido: se ignora, el request sigue como anónimo.
  }
  next();
}

/**
 * Resuelve un token a su userId, o null si no es válido.
 *
 * Lo usa el handshake de Socket.IO, que no pasa por los middlewares de
 * Express y no tiene un `res` al que responder 401: ahí lo único que hace
 * falta es saber si el `userId` que dice el cliente es realmente suyo.
 */
function verificarToken(token) {
  if (!token || typeof token !== 'string') return null;
  try {
    const decoded = jwt.verify(token, JWT_SECRET, { algorithms: [ALGORITMO] });
    if (sesionRevocada(decoded)) return null;
    return decoded.sub || null;
  } catch (err) {
    return null;
  }
}

/**
 * ¿Esta fila de `sellers` es una cuenta que entra con Google?
 *
 * Se pregunta por `auth_provider`, NUNCA por "no tiene password_hash": las
 * cuentas legacy anteriores a la migración 21 tampoco lo tienen y sí deben
 * poder ponerse una contraseña. Confundir ambos casos es exactamente lo que
 * permitiría apropiarse de una cuenta de Google sabiendo solo su correo.
 */
function esCuentaDeGoogle(row) {
  return !!row && row.auth_provider === 'google';
}

module.exports = {
  generateToken,
  esCuentaDeGoogle,
  generateAnonToken,
  requireAuth,
  optionalAuth,
  verificarToken,
  JWT_SECRET,
};
