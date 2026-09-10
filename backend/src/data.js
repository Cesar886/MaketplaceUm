'use strict';

const db = require('./database');

// Se conservan las referencias a estos arrays porque varias rutas antiguas
// las importan una vez. initializeData rellena las mismas instancias antes de
// abrir el puerto HTTP, de modo que ninguna petición ve una carga parcial.
const categories = [];
const sellers = [];
const highlightPlans = [];
const products = [];
const ownListings = [];
let initialization;
function replaceContents(target, values) {
  target.splice(0, target.length, ...values);
}
async function initializeData() {
  if (initialization) return initialization;
  initialization = (async () => {
    await db.initDatabase();
    await db.anularMetodosPagoCuentasDueno();
    await db.expireStaleOffers();
    const [categoryRows, sellerRows, plans, productRows, listingRows] = await Promise.all([await db.getCategories(), await db.getSellers(), await db.getHighlightPlans(), await db.getAllProducts(), await db.getAllListings()]);
    replaceContents(categories, categoryRows);
    replaceContents(sellers, sellerRows);
    replaceContents(highlightPlans, plans);
    replaceContents(products, productRows);
    replaceContents(ownListings, listingRows.map(row => ({
      id: row.id,
      productId: row.productId
    })));
  })();
  try {
    await initialization;
  } catch (error) {
    initialization = null;
    throw error;
  }
}
async function refrescarSellers() {
  await db.refrescarCuentasDueno();
  replaceContents(sellers, await db.getSellers());
}
async function registerSeller(sellerData) {
  await db.getDb().prepare(`
    INSERT OR IGNORE INTO sellers (
      id, name, email, phone, avatarInitials, major, isBusiness, logoUrl,
      rating, reviews, verified, password_hash, businessHours,
      paymentMethods, tipo_cuenta, created_at
    ) VALUES (
      @id, @name, @email, @phone, @avatarInitials, @major, @isBusiness,
      @logoUrl, @rating, @reviews, @verified, @password_hash, @businessHours,
      @paymentMethods, @tipo_cuenta, datetime('now')
    )
  `).run({
    ...sellerData,
    email: sellerData.email || null,
    tipo_cuenta: sellerData.tipo_cuenta || 'particular',
    phone: sellerData.phone || null,
    isBusiness: sellerData.isBusiness ? 1 : 0,
    verified: sellerData.verified ? 1 : 0,
    rating: sellerData.rating ?? 0,
    reviews: sellerData.reviews ?? 0,
    logoUrl: sellerData.logoUrl || null,
    password_hash: sellerData.password_hash || null,
    businessHours: JSON.stringify(sellerData.businessHours || {}),
    paymentMethods: JSON.stringify(sellerData.paymentMethods || [])
  });
  await db.anularMetodosPagoCuentasDueno();
  await refrescarSellers();
}
async function saveData() {
  await db.getDb().transaction(async () => {
    for (const product of products) await db.insertProduct(product);
    await db.getDb().prepare('DELETE FROM listings').run();
    for (const listing of ownListings) await db.addListing(listing);
  })();
}
async function updateSellerField(sellerId, field, value) {
  // Los nombres de columna nunca vienen de una petición directa. Esta lista
  // evita que una futura llamada accidental convierta el template en SQL
  // inyectable.
  const allowedFields = new Set(['password_hash', 'phone', 'name', 'avatarInitials', 'major', 'isBusiness', 'logoUrl', 'businessDescription', 'businessCategory', 'businessHours', 'paymentMethods', 'location_lat', 'location_lng', 'colorAcento', 'producto_fijado_id', 'facebook_url', 'instagram_url', 'whatsapp_number', 'tiktok_url', 'twitter_url', 'insignias_ocultas']);
  if (!allowedFields.has(field)) throw new Error(`Campo de vendedor no permitido: ${field}`);
  const valorPersistido = field === 'paymentMethods' && db.esUsuarioTodosLosBadges(sellerId) ? null : value;
  await db.getDb().prepare(`UPDATE sellers SET ${field} = ? WHERE id = ?`).run(valorPersistido, sellerId);
  await refrescarSellers();
}

// La suite existente usa SQLite temporal y consulta estos arrays justo al
// importar el módulo. Mantener esta carga síncrona en NODE_ENV=test permite
// validar el comportamiento legacy mientras producción usa sólo PostgreSQL.
if (process.env.NODE_ENV === 'test' && process.env.MERCADITO_DB_PATH && !process.env.DATABASE_URL) {
  db.initDatabase();
  db.anularMetodosPagoCuentasDueno();
  db.expireStaleOffers();
  replaceContents(categories, db.getCategories());
  replaceContents(sellers, db.getSellers());
  replaceContents(highlightPlans, db.getHighlightPlans());
  replaceContents(products, db.getAllProducts());
  replaceContents(ownListings, db.getAllListings().map(row => ({
    id: row.id,
    productId: row.productId,
  })));
  initialization = Promise.resolve();
}
module.exports = {
  categories,
  sellers,
  products,
  ownListings,
  highlightPlans,
  initializeData,
  saveData,
  registerSeller,
  updateSellerField,
  refrescarSellers
};
