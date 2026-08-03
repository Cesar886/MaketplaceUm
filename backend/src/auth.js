const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'mercadito-um-dev-secret-2026';
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
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = { id: decoded.sub };
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expirado. Vuelve a iniciar sesión.' });
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
