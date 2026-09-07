const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const speakeasy = require('speakeasy');
const db = require('./database');

const ADMIN_TOKEN_ISSUER = 'marketplace-um-api';
const ADMIN_TOKEN_AUDIENCE = 'marketplace-um-admin';
const ADMIN_TOKEN_TTL_SECONDS = 30 * 60;
const ADMIN_TOKEN_ALGORITHM = 'HS256';
const USERNAME_PATTERN = /^[a-z0-9._-]{3,64}$/;
const ENCRYPTED_TOTP_PATTERN = /^v1\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)$/;

// Comparar siempre contra un hash bcrypt, incluso cuando el usuario no existe,
// evita convertir el tiempo de respuesta en un enumerador de administradores.
const DUMMY_PASSWORD_HASH = bcrypt.hashSync(
  'credencial-administrativa-inexistente',
  12,
);

function configuredSecret(name) {
  const value = String(process.env[name] || '');
  return value.length >= 32 ? value : null;
}

function adminAuthConfigured() {
  return !!configuredSecret('ADMIN_JWT_SECRET')
    && !!configuredSecret('ADMIN_TOTP_ENCRYPTION_KEY');
}

function normalizeAdminUsername(value) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim().toLowerCase();
  return USERNAME_PATTERN.test(normalized) ? normalized : null;
}

function encryptionKey() {
  const secret = configuredSecret('ADMIN_TOTP_ENCRYPTION_KEY');
  if (!secret) {
    throw new Error('ADMIN_TOTP_ENCRYPTION_KEY debe tener al menos 32 caracteres.');
  }
  return crypto.createHash('sha256').update(secret, 'utf8').digest();
}

function encryptTotpSecret(base32Secret) {
  if (typeof base32Secret !== 'string' || !/^[A-Z2-7]+=*$/i.test(base32Secret)) {
    throw new Error('Secreto TOTP invalido.');
  }
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const encrypted = Buffer.concat([
    cipher.update(base32Secret.toUpperCase(), 'utf8'),
    cipher.final(),
  ]);
  return [
    'v1',
    iv.toString('base64url'),
    cipher.getAuthTag().toString('base64url'),
    encrypted.toString('base64url'),
  ].join('.');
}

function decryptTotpSecret(value) {
  const match = typeof value === 'string' ? ENCRYPTED_TOTP_PATTERN.exec(value) : null;
  if (!match) throw new Error('Secreto TOTP almacenado con formato invalido.');
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    encryptionKey(),
    Buffer.from(match[1], 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(match[2], 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(match[3], 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}

function issueAdminToken(admin) {
  const secret = configuredSecret('ADMIN_JWT_SECRET');
  if (!secret) throw new Error('ADMIN_JWT_SECRET debe tener al menos 32 caracteres.');
  return jwt.sign(
    {
      typ: 'admin',
      username: admin.username,
      ver: admin.token_version,
    },
    secret,
    {
      algorithm: ADMIN_TOKEN_ALGORITHM,
      audience: ADMIN_TOKEN_AUDIENCE,
      expiresIn: ADMIN_TOKEN_TTL_SECONDS,
      issuer: ADMIN_TOKEN_ISSUER,
      jwtid: crypto.randomUUID(),
      subject: String(admin.id),
    },
  );
}

function bearerToken(req) {
  const authorization = req.get('authorization');
  if (!authorization || authorization.length > 8192) return null;
  const match = /^Bearer ([A-Za-z0-9._-]+)$/.exec(authorization);
  return match ? match[1] : null;
}

function requireAdmin(req, res, next) {
  const secret = configuredSecret('ADMIN_JWT_SECRET');
  if (!secret) {
    return res.status(503).json({ error: 'La autenticacion administrativa no esta configurada.' });
  }
  const token = bearerToken(req);
  if (!token) return res.status(401).json({ error: 'Sesion administrativa requerida.' });

  try {
    const payload = jwt.verify(token, secret, {
      algorithms: [ADMIN_TOKEN_ALGORITHM],
      audience: ADMIN_TOKEN_AUDIENCE,
      issuer: ADMIN_TOKEN_ISSUER,
    });
    if (
      payload.typ !== 'admin'
      || typeof payload.sub !== 'string'
      || typeof payload.jti !== 'string'
      || !Number.isSafeInteger(payload.exp)
      || !Number.isSafeInteger(payload.ver)
    ) {
      return res.status(401).json({ error: 'Sesion administrativa invalida.' });
    }
    const admin = db.getDb().prepare(
      `SELECT id, username, token_version FROM admins
       WHERE id = ? AND active = 1`,
    ).get(payload.sub);
    if (!admin || admin.token_version !== payload.ver) {
      return res.status(401).json({ error: 'Sesion administrativa invalida.' });
    }
    const revoked = db.getDb().prepare(
      'SELECT 1 FROM admin_revoked_tokens WHERE jti = ? AND expires_at > unixepoch()',
    ).get(payload.jti);
    if (revoked) return res.status(401).json({ error: 'Sesion administrativa invalida.' });
    req.admin = { id: admin.id, username: admin.username };
    req.adminSession = { jti: payload.jti, expiresAt: payload.exp };
    return next();
  } catch {
    return res.status(401).json({ error: 'Sesion administrativa invalida o expirada.' });
  }
}

async function authenticateAdmin({ username, password, totp }) {
  if (!adminAuthConfigured()) return { configurationError: true };
  const normalizedUsername = normalizeAdminUsername(username);
  const safePassword = typeof password === 'string' && password.length <= 512
    ? password
    : '';
  const safeTotp = typeof totp === 'string' && /^\d{6}$/.test(totp.trim())
    ? totp.trim()
    : '';

  const admin = normalizedUsername
    ? db.getDb().prepare(
      `SELECT id, username, password_hash, totp_secret_encrypted,
       token_version, last_totp_step
       FROM admins WHERE username = ? AND active = 1`,
    ).get(normalizedUsername)
    : null;
  const passwordMatches = await bcrypt.compare(
    safePassword,
    admin?.password_hash || DUMMY_PASSWORD_HASH,
  );
  if (!admin || !passwordMatches || !safeTotp) return { authenticated: false };

  let secret;
  try {
    secret = decryptTotpSecret(admin.totp_secret_encrypted);
  } catch (error) {
    console.error(`[admin-auth] No se pudo descifrar TOTP para admin ${admin.id}:`, error.message);
    return { configurationError: true };
  }

  const verification = speakeasy.totp.verifyDelta({
    secret,
    encoding: 'base32',
    token: safeTotp,
    step: 30,
    window: 1,
  });
  if (!verification) return { authenticated: false };

  // El mismo codigo TOTP no se puede reutilizar durante su ventana de tiempo.
  // El UPDATE condicional hace atomica la defensa incluso con dos logins juntos.
  const totpStep = Math.floor(Date.now() / 30_000) + verification.delta;
  const claimed = db.getDb().prepare(
    `UPDATE admins SET last_totp_step = ?, last_login_at = datetime('now'),
       updated_at = datetime('now')
     WHERE id = ? AND (last_totp_step IS NULL OR last_totp_step < ?)`,
  ).run(totpStep, admin.id, totpStep);
  if (claimed.changes !== 1) return { authenticated: false };

  return {
    authenticated: true,
    admin: { id: admin.id, username: admin.username },
    token: issueAdminToken(admin),
    expiresIn: ADMIN_TOKEN_TTL_SECONDS,
  };
}

module.exports = {
  ADMIN_TOKEN_AUDIENCE,
  ADMIN_TOKEN_ISSUER,
  ADMIN_TOKEN_TTL_SECONDS,
  adminAuthConfigured,
  authenticateAdmin,
  decryptTotpSecret,
  encryptTotpSecret,
  issueAdminToken,
  normalizeAdminUsername,
  requireAdmin,
};
