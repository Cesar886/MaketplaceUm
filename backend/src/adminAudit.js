const MAX_ACTION_LENGTH = 80;
const MAX_ENTITY_TYPE_LENGTH = 80;
const MAX_ENTITY_ID_LENGTH = 180;
const MAX_DETAILS_JSON_BYTES = 8 * 1024;
const AUDIT_KEY_PATTERN = /^[a-z][a-z0-9._-]*$/;

function textoAuditable(value, field, maxLength, pattern = null) {
  if (
    typeof value !== 'string'
    || value.length === 0
    || value.length > maxLength
    || /[\u0000-\u001f\u007f]/.test(value)
    || (pattern && !pattern.test(value))
  ) {
    throw new TypeError(`${field} invalido para la auditoria administrativa.`);
  }
  return value;
}

function serializarDetallesAuditoria(details = {}) {
  let serialized;
  try {
    serialized = JSON.stringify(details);
  } catch {
    throw new TypeError('Los detalles de auditoria deben ser JSON serializable.');
  }
  if (serialized === undefined) serialized = '{}';
  if (Buffer.byteLength(serialized, 'utf8') > MAX_DETAILS_JSON_BYTES) {
    throw new RangeError(
      `Los detalles de auditoria no pueden superar ${MAX_DETAILS_JSON_BYTES} bytes.`,
    );
  }
  return serialized;
}

/**
 * Registra una accion usando exclusivamente la identidad que puso el
 * middleware requireAdmin en req.admin. La funcion no acepta un actor como
 * argumento ni tiene fallback a headers, para evitar atribuciones falsificadas.
 * Debe invocarse dentro de la misma transaccion que la mutacion sensible.
 */
function registrarAuditoriaAdmin(database, req, {
  action,
  entityType,
  entityId,
  details = {},
  createdAt = new Date().toISOString(),
}) {
  const admin = req?.admin;
  if (
    !admin
    || !Number.isSafeInteger(admin.id)
    || admin.id <= 0
    || typeof admin.username !== 'string'
    || admin.username.length < 3
    || admin.username.length > 64
    || /[\u0000-\u001f\u007f]/.test(admin.username)
  ) {
    throw new Error('Se requiere un administrador autenticado para registrar la auditoria.');
  }

  const safeAction = textoAuditable(
    action,
    'action',
    MAX_ACTION_LENGTH,
    AUDIT_KEY_PATTERN,
  );
  const safeEntityType = textoAuditable(
    entityType,
    'entityType',
    MAX_ENTITY_TYPE_LENGTH,
    AUDIT_KEY_PATTERN,
  );
  const safeEntityId = textoAuditable(
    String(entityId),
    'entityId',
    MAX_ENTITY_ID_LENGTH,
  );
  const safeCreatedAt = textoAuditable(createdAt, 'createdAt', 40);
  const detailsJson = serializarDetallesAuditoria(details);

  return database.prepare(
    `INSERT INTO admin_audit_log (
       admin_id, action, entity_type, entity_id, details_json, created_at
     ) VALUES (?, ?, ?, ?, ?, ?)`,
  ).run(
    admin.id,
    safeAction,
    safeEntityType,
    safeEntityId,
    detailsJson,
    safeCreatedAt,
  );
}

module.exports = {
  MAX_DETAILS_JSON_BYTES,
  registrarAuditoriaAdmin,
  serializarDetallesAuditoria,
};
