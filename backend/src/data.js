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

let cart = db.getAllCartItems().map(row => ({
  id: row.id,
  productId: row.productId,
  quantity: row.quantity,
  meetingPoint: row.meetingPoint,
}));

let ownListings = db.getAllListings().map(row => ({
  id: row.id,
  productId: row.productId,
}));

// ─── Registrar un nuevo vendedor (DB + en memoria) ────────────
function registerSeller(sellerData) {
  // Insertar en SQLite
  db.getDb().prepare(`
    INSERT OR IGNORE INTO sellers (id, name, email, phone, avatarInitials, major, isBusiness, logoUrl, rating, reviews, verified, password_hash)
    VALUES (@id, @name, @email, @phone, @avatarInitials, @major, @isBusiness, @logoUrl, @rating, @reviews, @verified, @password_hash)
  `).run({
    ...sellerData,
    email: sellerData.email || null,
    phone: sellerData.phone || null,
    isBusiness: sellerData.isBusiness ? 1 : 0,
    verified: sellerData.verified ? 1 : 0,
    rating: sellerData.rating ?? 0,
    reviews: sellerData.reviews ?? 0,
    logoUrl: sellerData.logoUrl || null,
    password_hash: sellerData.password_hash || null,
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

    // Cart
    db.getDb().prepare('DELETE FROM cart').run();
    for (const c of cart) {
      db.addCartItem(c);
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

module.exports = { categories, sellers, products, cart, ownListings, highlightPlans, saveData, registerSeller, updateSellerField };
