const jwt = require('jsonwebtoken');
const { createHash, randomBytes, randomUUID } = require('crypto');
const db = require('./database');
const {
  getSellerAccess,
  getSellerTokenAccess,
  sendSellerAccessError,
} = require('./sellerAccess');

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
// El JWT de acceso dura bastante más de una semana para que la app siga
// funcionando incluso si pasa varios días sin poder renovar. La continuidad
// indefinida no depende de alargarlo eternamente: la da la sesión persistente
// revocable que emite uno nuevo antes de que éste caduque.
const JWT_EXPIRES_IN = '30d';

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
  // `iat` solo tiene precision de segundos. Este claim permite cortar una
  // sesion en el mismo segundo en que se emitio, sin una ventana reutilizable.
  return jwt.sign({ sub: userId, auth_time_ms: Date.now() }, JWT_SECRET, {
    jwtid: randomUUID(),
    expiresIn: JWT_EXPIRES_IN,
    algorithm: ALGORITMO,
  });
}

function hashRefreshToken(token) {
  return createHash('sha256').update(token).digest('hex');
}

/**
 * Crea una credencial persistente de alta entropía. El valor en claro solo
 * sale una vez hacia el dispositivo; la base conserva únicamente su hash.
 */
function generateRefreshToken(userId) {
  const refreshToken = randomBytes(48).toString('base64url');
  db.getDb().prepare(
    `INSERT INTO refresh_sessions (token_hash, user_id)
     VALUES (?, ?)`,
  ).run(hashRefreshToken(refreshToken), userId);
  return refreshToken;
}

function generateSession(userId) {
  return {
    token: generateToken(userId),
    refreshToken: generateRefreshToken(userId),
  };
}

/** Renueva el JWT sin contraseña y sin límite temporal. */
function refreshSession(refreshToken) {
  if (typeof refreshToken !== 'string' || refreshToken.length < 40) return null;
  const database = db.getDb();
  const tokenHash = hashRefreshToken(refreshToken);
  const row = database.prepare(
    `SELECT rs.user_id
       FROM refresh_sessions rs
       JOIN sellers s ON s.id = rs.user_id
      WHERE rs.token_hash = ? AND rs.revoked_at IS NULL`,
  ).get(tokenHash);
  if (!row) return null;

  // No basta con hacer JOIN: una fila suspendida sigue existiendo. Se usa la
  // misma puerta que REST, sockets y login para que refresh no sea un bypass.
  const access = getSellerAccess(database, row.user_id);
  if (!access.allowed) return null;

  database.prepare(
    `UPDATE refresh_sessions SET last_used_at = datetime('now')
      WHERE token_hash = ?`,
  ).run(tokenHash);
  return { token: generateToken(row.user_id), userId: row.user_id };
}

function revokeRefreshToken(refreshToken, expectedUserId = null) {
  if (typeof refreshToken !== 'string' || refreshToken.length < 40) return;
  const params = [hashRefreshToken(refreshToken)];
  let sql = `UPDATE refresh_sessions SET revoked_at = datetime('now')
              WHERE token_hash = ? AND revoked_at IS NULL`;
  if (expectedUserId) {
    sql += ' AND user_id = ?';
    params.push(expectedUserId);
  }
  db.getDb().prepare(sql).run(...params);
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

  let decoded;
  try {
    decoded = jwt.verify(token, JWT_SECRET, { algorithms: [ALGORITMO] });
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

  if (sesionRevocada(decoded)) {
    return res.status(401).json({ error: 'SESSION_INVALIDATED', message: 'Sesión cerrada.' });
  }

  const isAnonymous = decoded.anon === true;
  if (isAnonymous) {
    // Un token de invitado sigue siendo valido sin una fila en sellers.
    // Se comprueba el formato emitido por generateAnonToken para que el claim
    // anon no pueda convertir otra identidad firmada por error en invitado.
    if (typeof decoded.sub !== 'string' || !/^anon_[0-9a-f-]{36}$/i.test(decoded.sub)) {
      return res.status(401).json({ error: 'Token inválido.' });
    }
  } else {
    let access;
    try {
      access = getSellerTokenAccess(db.getDb(), decoded);
    } catch (error) {
      console.error('[auth] no se pudo validar el estado de la cuenta:', error.message);
      return res.status(503).json({
        error: 'AUTHORIZATION_UNAVAILABLE',
        message: 'No se pudo validar la sesión. Intenta de nuevo.',
      });
    }
    if (!access.allowed) return sendSellerAccessError(res, access);
  }

  req.user = {
    id: decoded.sub,
    anon: isAnonymous,
    jti: decoded.jti,
    exp: decoded.exp,
  };
  return next();
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
    if (decoded.anon === true) {
      if (typeof decoded.sub !== 'string' || !/^anon_[0-9a-f-]{36}$/i.test(decoded.sub)) {
        return next();
      }
      req.user = { id: decoded.sub, anon: true };
      return next();
    }
    const access = getSellerTokenAccess(db.getDb(), decoded);
    if (access.allowed) req.user = { id: decoded.sub, anon: false };
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
    if (decoded.anon === true) {
      return typeof decoded.sub === 'string' && /^anon_[0-9a-f-]{36}$/i.test(decoded.sub)
        ? decoded.sub
        : null;
    }
    const access = getSellerTokenAccess(db.getDb(), decoded);
    if (!access.allowed) return null;
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
  generateSession,
  refreshSession,
  revokeRefreshToken,
  esCuentaDeGoogle,
  generateAnonToken,
  requireAuth,
  optionalAuth,
  verificarToken,
  JWT_SECRET,
};
