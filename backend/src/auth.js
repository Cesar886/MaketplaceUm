const jwt = require('jsonwebtoken');

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
const JWT_EXPIRES_IN = '7d';

/**
 * Genera un token JWT para un usuario dado.
 * @param {string} userId - ID del usuario/seller
 * @returns {string} token JWT
 */
function generateToken(userId) {
  return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

/**
 * Middleware de autenticación.
 * Valida que el request tenga un Bearer token válido.
 * Si es válido, deja el payload en req.user y continúa.
 * Si no, responde 401.
 */
// Muestra solo los primeros/últimos 6 caracteres del token, nunca el token
// completo, para poder diferenciar tokens en los logs sin exponerlos.
function maskToken(token) {
  if (!token) return '(vacío)';
  if (token.length <= 12) return '(token corto, oculto)';
  return `${token.slice(0, 6)}…${token.slice(-6)} (len=${token.length})`;
}

// TEMPORAL — diagnóstico del incidente de 401 masivo en /api/products tras
// restarts de PM2. Quitar una vez confirmada la causa raíz (ver auth.js
// JWT_SECRET) y que el fix esté validado en producción.
function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader) {
    console.log(`[auth] ${req.method} ${req.originalUrl} — sin header Authorization`);
    return res.status(401).json({ error: 'Token requerido. Envía Authorization: Bearer <token>' });
  }

  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0] !== 'Bearer') {
    console.log(`[auth] ${req.method} ${req.originalUrl} — header Authorization con formato inválido: "${authHeader.slice(0, 15)}..."`);
    return res.status(401).json({ error: 'Formato de token inválido. Usa: Bearer <token>' });
  }

  const token = parts[1];
  console.log(`[auth] ${req.method} ${req.originalUrl} — token recibido y parseado`);

  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    console.log(`[auth] ${req.method} ${req.originalUrl} — token válido, sub=${decoded.sub}`);
    req.user = { id: decoded.sub };
    next();
  } catch (err) {
    console.log(`[auth] ${req.method} ${req.originalUrl} — jwt.verify falló: ${err.name}: ${err.message}`);
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
    const decoded = jwt.verify(parts[1], JWT_SECRET);
    req.user = { id: decoded.sub };
  } catch (err) {
    // Token ausente/expirado/inválido: se ignora, el request sigue como anónimo.
  }
  next();
}

module.exports = { generateToken, requireAuth, optionalAuth, JWT_SECRET };
