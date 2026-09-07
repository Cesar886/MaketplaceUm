/**
 * Autorizacion central de cuentas del marketplace.
 *
 * Este modulo es deliberadamente independiente de Express y de JWT: recibe
 * la fila/claims ya autenticados y decide si la cuenta puede actuar. Asi la
 * misma regla se aplica a REST, Socket.IO, refresh tokens y ambos logins sin
 * que una ruta pueda olvidar una comprobacion distinta.
 */

const ACCOUNT_STATUSES = Object.freeze({
  ACTIVE: 'active',
  SUSPENDED: 'suspended',
  BANNED: 'banned',
});

const VALID_ACCOUNT_STATUSES = new Set(Object.values(ACCOUNT_STATUSES));

function parseTimestampMs(value) {
  if (value === null || value === undefined || value === '') return null;

  if (typeof value === 'number' || /^\d+$/.test(String(value))) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric < 0) return null;
    // auth_invalid_before se guarda en milisegundos. Aceptar segundos hace
    // que un despliegue mixto no vuelva validos tokens que otro proceso ya
    // habia invalidado usando unixepoch().
    return numeric > 0 && numeric < 1_000_000_000_000 ? numeric * 1000 : numeric;
  }

  let normalized = String(value).trim();
  // SQLite datetime('now') no incluye zona. Sus timestamps son UTC.
  if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?$/.test(normalized)) {
    normalized = `${normalized.replace(' ', 'T')}Z`;
  }
  const parsed = Date.parse(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function denied(code, message, extra = {}) {
  return { allowed: false, code, message, ...extra };
}

/**
 * Lee el estado administrativo y reactiva de manera atomica una suspension
 * temporal ya vencida. Una fecha corrupta se trata como suspension
 * indefinida: fallar cerrado es preferible a levantarla por accidente.
 */
function getSellerAccess(database, userId, { nowMs = Date.now() } = {}) {
  if (!database || typeof database.prepare !== 'function') {
    throw new TypeError('Se requiere una conexion SQLite valida.');
  }
  if (typeof userId !== 'string' || !userId || userId.length > 180) {
    return denied('SESSION_INVALIDATED', 'La sesion ya no esta disponible.');
  }

  let row = database.prepare(
    `SELECT id, admin_status, admin_status_reason, admin_status_until,
            auth_invalid_before
       FROM sellers
      WHERE id = ?`,
  ).get(userId);

  if (!row) {
    return denied('SESSION_INVALIDATED', 'La sesion ya no esta disponible.');
  }

  let status = row.admin_status || ACCOUNT_STATUSES.ACTIVE;
  if (!VALID_ACCOUNT_STATUSES.has(status)) {
    return denied('ACCOUNT_DISABLED', 'La cuenta no esta disponible.');
  }

  if (status === ACCOUNT_STATUSES.SUSPENDED) {
    const untilMs = parseTimestampMs(row.admin_status_until);
    if (untilMs !== null && untilMs <= nowMs) {
      // La condicion evita que una expiracion le gane una carrera a un ban o
      // a una extension de la suspension aplicada por un administrador.
      const updated = database.prepare(
        `UPDATE sellers
            SET admin_status = 'active',
                admin_status_reason = NULL,
                admin_status_until = NULL
          WHERE id = ?
            AND admin_status = 'suspended'
            AND admin_status_until IS ?`,
      ).run(userId, row.admin_status_until);

      if (updated.changes === 1) {
        status = ACCOUNT_STATUSES.ACTIVE;
        row = { ...row, admin_status: status, admin_status_reason: null, admin_status_until: null };
      } else {
        // Hubo un cambio concurrente. Releer una sola vez y decidir sobre el
        // estado ganador; nunca asumir que sigue activa.
        row = database.prepare(
          `SELECT id, admin_status, admin_status_reason, admin_status_until,
                  auth_invalid_before
             FROM sellers WHERE id = ?`,
        ).get(userId);
        if (!row) return denied('SESSION_INVALIDATED', 'La sesion ya no esta disponible.');
        status = row.admin_status || ACCOUNT_STATUSES.ACTIVE;
      }
    }
  }

  if (status === ACCOUNT_STATUSES.BANNED) {
    return denied('ACCOUNT_BANNED', 'Esta cuenta fue inhabilitada.');
  }

  if (status === ACCOUNT_STATUSES.SUSPENDED) {
    return denied(
      'ACCOUNT_SUSPENDED',
      'Esta cuenta esta suspendida temporalmente.',
      { suspendedUntil: row.admin_status_until || null },
    );
  }

  if (status !== ACCOUNT_STATUSES.ACTIVE) {
    return denied('ACCOUNT_DISABLED', 'La cuenta no esta disponible.');
  }

  return {
    allowed: true,
    userId: row.id,
    status,
    authInvalidBeforeMs: parseTimestampMs(row.auth_invalid_before) || 0,
  };
}

/** Valida ademas que el JWT haya nacido despues del corte de sesiones. */
function getSellerTokenAccess(database, decoded, options) {
  const access = getSellerAccess(database, decoded && decoded.sub, options);
  if (!access.allowed) return access;

  const preciseIssuedAt = Number(decoded && decoded.auth_time_ms);
  const issuedAtMs = Number.isSafeInteger(preciseIssuedAt) && preciseIssuedAt > 0
    ? preciseIssuedAt
    : Number.isFinite(Number(decoded && decoded.iat))
      ? Number(decoded.iat) * 1000
      : 0;

  if (!issuedAtMs || issuedAtMs < access.authInvalidBeforeMs) {
    return denied('SESSION_INVALIDATED', 'La sesion ya no esta disponible.');
  }

  return access;
}

/**
 * Corta JWT existentes y revoca todas las credenciales persistentes del
 * usuario en una sola transaccion. Los endpoints administrativos deben usar
 * este helper al cambiar un estado para que no quede una via de refresh.
 */
function invalidateSellerSessions(database, userId, { nowMs = Date.now() } = {}) {
  const cutoff = Math.max(1, Math.trunc(nowMs) + 1);
  return database.transaction(() => {
    const result = database.prepare(
      `UPDATE sellers
          SET auth_invalid_before = MAX(COALESCE(auth_invalid_before, 0), ?)
        WHERE id = ?`,
    ).run(cutoff, userId);
    if (result.changes !== 1) return false;

    database.prepare(
      `UPDATE refresh_sessions
          SET revoked_at = COALESCE(revoked_at, datetime('now'))
        WHERE user_id = ? AND revoked_at IS NULL`,
    ).run(userId);
    return true;
  })();
}

function sendSellerAccessError(res, access) {
  const forbidden = access && (
    access.code === 'ACCOUNT_BANNED' ||
    access.code === 'ACCOUNT_SUSPENDED' ||
    access.code === 'ACCOUNT_DISABLED'
  );
  const payload = {
    error: access?.code || 'SESSION_INVALIDATED',
    message: access?.message || 'La sesion ya no esta disponible.',
  };
  if (access?.suspendedUntil) payload.suspendedUntil = access.suspendedUntil;
  return res.status(forbidden ? 403 : 401).json(payload);
}

module.exports = {
  ACCOUNT_STATUSES,
  getSellerAccess,
  getSellerTokenAccess,
  invalidateSellerSessions,
  parseTimestampMs,
  sendSellerAccessError,
};
