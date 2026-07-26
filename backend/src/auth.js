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

module.exports = { generateToken, requireAuth, JWT_SECRET };
