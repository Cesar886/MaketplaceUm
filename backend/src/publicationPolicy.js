// Fuente canonica de los valores iniciales. SQLite recibe estas cifras al
// crear cada fila y DELETE /api/admin/config/:key las reutiliza para resetear;
// durante la operacion normal los limites efectivos se leen de la tabla.
const DEFAULT_PUBLICATION_POLICIES = Object.freeze({
  negocio_verificado: {
    productsActive: 40,
    productsDaily: 8,
    wantedActive: 10,
    wantedDaily: 3,
    durationDays: 60
  },
  um_verificado: {
    productsActive: 30,
    productsDaily: 6,
    wantedActive: 10,
    wantedDaily: 3,
    durationDays: 60
  },
  negocio_sin_verificar: {
    productsActive: 15,
    productsDaily: 3,
    wantedActive: 4,
    wantedDaily: 1,
    durationDays: 20
  },
  um_sin_verificar: {
    productsActive: 10,
    productsDaily: 3,
    wantedActive: 5,
    wantedDaily: 2,
    durationDays: 30
  },
  externo: {
    productsActive: 8,
    productsDaily: 2,
    wantedActive: 3,
    wantedDaily: 1,
    durationDays: 30
  }
});
const PUBLICATION_POLICY_KEYS = Object.freeze(Object.keys(DEFAULT_PUBLICATION_POLICIES));
const PUBLICATION_POLICY_RANGES = Object.freeze({
  productsActive: Object.freeze({
    min: 0,
    max: 1000
  }),
  productsDaily: Object.freeze({
    min: 0,
    max: 100
  }),
  wantedActive: Object.freeze({
    min: 0,
    max: 500
  }),
  wantedDaily: Object.freeze({
    min: 0,
    max: 100
  }),
  durationDays: Object.freeze({
    min: 1,
    max: 365
  })
});
const PUBLICATION_POLICY_FIELDS = Object.freeze(Object.keys(PUBLICATION_POLICY_RANGES));
function publicationPolicyKey(seller) {
  let key = 'externo';
  if (seller && seller.tipoCuenta !== 'particular') {
    if (seller.tipoCuenta === 'negocio' || seller.isBusiness) {
      key = seller.verified ? 'negocio_verificado' : 'negocio_sin_verificar';
    } else {
      key = seller.verified ? 'um_verificado' : 'um_sin_verificar';
    }
  }
  return key;
}
function rowToPublicationPolicy(row) {
  return {
    key: row.key,
    productsActive: row.products_active,
    productsDaily: row.products_daily,
    wantedActive: row.wanted_active,
    wantedDaily: row.wanted_daily,
    durationDays: row.duration_days,
    updatedByAdminId: row.updated_by_admin_id ?? null,
    updatedAt: row.updated_at || null
  };
}
async function getPublicationPolicy(seller) {
  const key = publicationPolicyKey(seller);
  let database;
  try {
    // Import diferido: database.js usa los defaults para sembrar la tabla.
    // Mantener este require dentro de la funcion evita una dependencia
    // circular y permite que los tests unitarios puros usen el fallback.
    database = require('./database').getDb();
  } catch (error) {
    if (error?.message === 'Database not initialized. Call initDatabase() first.') {
      return {
        key,
        ...DEFAULT_PUBLICATION_POLICIES[key]
      };
    }
    throw error;
  }
  const row = await database.prepare(`SELECT key, products_active, products_daily, wanted_active, wanted_daily,
       duration_days, updated_by_admin_id, updated_at
     FROM config WHERE key = ?`).get(key);
  if (!row) {
    throw new Error(`Falta la configuracion de publicaciones para ${key}.`);
  }
  return rowToPublicationPolicy(row);
}
const expiresAtFromNow = days => new Date(Date.now() + days * 86400000).toISOString();
function isExpired(item, now = Date.now()) {
  if (!item?.expiresAt) return false; // publicaciones legacy: siguen activas
  const timestamp = new Date(item.expiresAt).getTime();
  // Una fecha corrupta se retira del feed en vez de quedar pública para
  // siempre. La fila se conserva y el dueño todavía puede renovarla.
  return !Number.isFinite(timestamp) || timestamp <= now;
}
module.exports = {
  // Alias conservado para consumidores existentes; representa defaults, no
  // la configuracion efectiva durante la ejecucion.
  POLICIES: DEFAULT_PUBLICATION_POLICIES,
  DEFAULT_PUBLICATION_POLICIES,
  PUBLICATION_POLICY_FIELDS,
  PUBLICATION_POLICY_KEYS,
  PUBLICATION_POLICY_RANGES,
  expiresAtFromNow,
  getPublicationPolicy,
  isExpired,
  publicationPolicyKey,
  rowToPublicationPolicy
};
