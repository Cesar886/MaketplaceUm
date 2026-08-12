const db = require('./database');

// ─── Inicializar base de datos (se ejecuta al importar) ────
db.initDatabase();

// ─── Exportar datos como arrays (compatible con las rutas existentes) ────

const categories = db.getCategories();
const sellers = db.getSellers();
const highlightPlans = db.getHighlightPlans();

// Limpiar ofertas expiradas al arrancar
db.expireStaleOffers();

// Cargar products, cart y ownListings desde SQLite
let products = db.getAllProducts();

// El carrito NO se cachea en memoria: es por usuario y se consulta siempre
// contra SQLite desde routes/cart.js. La versión anterior lo mantenía como
// un array global que `saveData()` volcaba con DELETE+INSERT, lo que además
// de compartir el carrito entre usuarios borraba el de todos cada vez que
// se guardaba cualquier producto.

let ownListings = db.getAllListings().map(row => ({
  id: row.id,
  productId: row.productId,
}));

// ─── Registrar un nuevo vendedor (DB + en memoria) ────────────
function registerSeller(sellerData) {
  // Insertar en SQLite
  db.getDb().prepare(`
    INSERT OR IGNORE INTO sellers (id, name, email, phone, avatarInitials, major, isBusiness, logoUrl, rating, reviews, verified, password_hash, businessHours, paymentMethods, tipo_cuenta)
    VALUES (@id, @name, @email, @phone, @avatarInitials, @major, @isBusiness, @logoUrl, @rating, @reviews, @verified, @password_hash, @businessHours, @paymentMethods, @tipo_cuenta)
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
    paymentMethods: JSON.stringify(sellerData.paymentMethods || []),
  });
  // Refrescar la lista en memoria desde DB
  sellers.length = 0;
  sellers.push(...db.getSellers());
}

// ─── Persistencia ─────────────────────────────────────────────
function saveData() {
  // products → SQLite (upsert, NUNCA borrar-y-reinsertar).
  // product_ratings tiene ON DELETE CASCADE hacia products: un DELETE FROM
  // products aquí (aunque se reinserten los mismos IDs después) borra
  // permanentemente TODAS las calificaciones de TODOS los productos en cada
  // guardado. insertProduct ya hace INSERT OR REPLACE, así que un upsert por
  // fila logra lo mismo sin ese efecto secundario. Los productos eliminados
  // de verdad se borran explícitamente en su propio endpoint (db.deleteProduct).
  db.getDb().transaction(() => {
    for (const p of products) {
      db.insertProduct(p);
    }

    // Listings
    db.getDb().prepare('DELETE FROM listings').run();
    for (const l of ownListings) {
      db.addListing(l);
    }
  })();
}

function updateSellerField(sellerId, field, value) {
  db.getDb().prepare(
    `UPDATE sellers SET ${field} = ? WHERE id = ?`
  ).run(value, sellerId);
  // Refrescar la lista en memoria desde DB
  sellers.length = 0;
  sellers.push(...db.getSellers());
}

module.exports = { categories, sellers, products, ownListings, highlightPlans, saveData, registerSeller, updateSellerField };
