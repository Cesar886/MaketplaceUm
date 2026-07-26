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
    INSERT OR IGNORE INTO sellers (id, name, email, phone, avatarInitials, major, isBusiness, logoUrl, rating, reviews, verified)
    VALUES (@id, @name, @email, @phone, @avatarInitials, @major, @isBusiness, @logoUrl, @rating, @reviews, @verified)
  `).run({
    ...sellerData,
    email: sellerData.email || null,
    phone: sellerData.phone || null,
    isBusiness: sellerData.isBusiness ? 1 : 0,
    verified: sellerData.verified ? 1 : 0,
    rating: sellerData.rating ?? 0,
    reviews: sellerData.reviews ?? 0,
    logoUrl: sellerData.logoUrl || null,
  });
  // Refrescar la lista en memoria desde DB
  sellers.length = 0;
  sellers.push(...db.getSellers());
}

// ─── Persistencia ─────────────────────────────────────────────
function saveData() {
  // products → SQLite (reescribir todos)
  db.getDb().transaction(() => {
    // Eliminar todos los products y re-insertarlos
    db.getDb().prepare('DELETE FROM products').run();
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
